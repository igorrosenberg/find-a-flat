// Find a flat: one Worker serving the Flutter web app (static assets from
// ../app/build/web) and a small JSON API, backed by D1 (binding DB).

import { gate, requireWrite } from './auth.js';
import { handleFlat, NOTES_MAX } from './flat.js';
import { geocode, distanceToDeodarM } from './geo.js';

export default {
  async fetch(request, env) {
    // Nothing is served without the passphrase: an error page while the
    // secret is unset, otherwise a login page until a session cookie is set.
    const blocked = await gate(request, env);
    if (blocked) return blocked;
    const url = new URL(request.url);
    if (url.pathname === '/') {
      return Response.redirect(new URL('/home', url).toString(), 302);
    }
    if (url.pathname === '/api/flats') {
      if (request.method === 'GET' || request.method === 'HEAD') {
        return json(await listFlats(env.DB));
      }
      if (request.method === 'POST') {
        return createFlat(request, env);
      }
      return json({ error: 'Method not allowed' }, 405, { allow: 'GET, HEAD, POST' });
    }
    const one = url.pathname.match(/^\/api\/flats\/(\d+)$/);
    if (one) {
      return handleFlat(request, env, Number(one[1]));
    }
    if (url.pathname.startsWith('/api/')) {
      return json({ error: 'Not found' }, 404);
    }
    // Everything else is the Flutter app; unknown paths such as /home fall
    // back to index.html (single-page-application mode in wrangler.toml).
    return env.ASSETS.fetch(request);
  },
};

export async function listFlats(db) {
  const { results } = await db
    .prepare(
      'SELECT id, name, price, size_sqft, distance_m, lat, lng, discarded FROM flat ORDER BY created_at DESC, id DESC',
    )
    .all();
  return results ?? [];
}

// POST /api/flats: validate, geocode the address, store the distance to the
// reference point, and return the new row with 201.
async function createFlat(request, env) {
  const denied = await requireWrite(request, env);
  if (denied) return denied;

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Body must be JSON' }, 400);
  }
  const { flat, errors } = validateFlat(body);
  if (errors) return json({ error: 'Some fields are invalid', fields: errors }, 400);

  const point = await geocode(flat.address);
  const row = {
    ...flat,
    lat: point?.lat ?? null,
    lng: point?.lng ?? null,
    distance_m: point ? distanceToDeodarM(point.lat, point.lng) : null,
  };
  const saved = await env.DB.prepare(
    `INSERT INTO flat (name, address, price, size_sqft, bedrooms, bathrooms, listing_url, lat, lng, distance_m, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`,
  )
    .bind(
      row.name, row.address, row.price, row.size_sqft, row.bedrooms, row.bathrooms,
      row.listing_url, row.lat, row.lng, row.distance_m, row.notes,
    )
    .first();
  return json(saved, 201, { location: `/api/flats/${saved.id}` });
}

// Returns { flat } with normalised values, or { errors } keyed by field name.
export function validateFlat(body) {
  const errors = {};
  const flat = {};
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return { errors: { body: 'Expected a JSON object' } };
  }
  for (const field of ['name', 'address']) {
    const v = typeof body[field] === 'string' ? body[field].trim() : '';
    if (!v) errors[field] = 'Required';
    else if (v.length > 500) errors[field] = 'At most 500 characters';
    flat[field] = v;
  }
  const number = (field, { min, whole, label }) => {
    const v = body[field];
    if (v === undefined || v === null || v === '') return (flat[field] = null);
    const n = typeof v === 'number' ? v : Number(v);
    if (!Number.isFinite(n) || (whole && !Number.isInteger(n)) || n < min || n > 1e12) {
      errors[field] = label;
    }
    flat[field] = whole ? n : Math.round(n);
  };
  number('price', { min: 1, whole: false, label: 'Must be a positive number' });
  number('size_sqft', { min: 1, whole: false, label: 'Must be a positive number' });
  number('bedrooms', { min: 0, whole: true, label: 'Must be a whole number, 0 or more' });
  number('bathrooms', { min: 0, whole: true, label: 'Must be a whole number, 0 or more' });

  const link = typeof body.listing_url === 'string' ? body.listing_url.trim() : '';
  flat.listing_url = link || null;
  if (link) {
    let ok = false;
    try {
      ok = ['http:', 'https:'].includes(new URL(link).protocol);
    } catch {}
    if (!ok) errors.listing_url = 'Must be an http or https link';
  }

  // Optional free text, kept as typed; blank means no notes.
  const notes = body.notes;
  if (notes === undefined || notes === null || notes === '') flat.notes = null;
  else if (typeof notes !== 'string') errors.notes = 'Must be text';
  else if (notes.length > NOTES_MAX) errors.notes = `At most ${NOTES_MAX} characters`;
  else flat.notes = notes.trim() ? notes : null;
  return Object.keys(errors).length ? { errors } : { flat };
}

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
