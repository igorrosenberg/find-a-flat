// One flat: GET, PATCH and DELETE /api/flats/:id.

import { requireWrite } from './auth.js';
import { distanceToDeodarM, geocode } from './geo.js';

const COLUMNS =
  'id, name, address, price, size_sqft, bedrooms, bathrooms, listing_url, lat, lng, distance_m, notes, discarded, created_at, updated_at';

export const NOTES_MAX = 10000;

export async function handleFlat(request, env, id, deps = {}) {
  switch (request.method) {
    case 'GET':
    case 'HEAD': {
      const flat = await getFlat(env.DB, id);
      return flat ? json(flat) : json({ error: 'Not found' }, 404);
    }
    case 'PATCH': {
      const denied = await requireWrite(request, env);
      if (denied) return denied;
      return patchFlat(request, env.DB, id, deps.geocode ?? geocode);
    }
    case 'DELETE': {
      const denied = await requireWrite(request, env);
      if (denied) return denied;
      const { meta } = await env.DB.prepare('DELETE FROM flat WHERE id = ?').bind(id).run();
      return meta?.changes ? new Response(null, { status: 204 }) : json({ error: 'Not found' }, 404);
    }
    default:
      return json({ error: 'Method not allowed' }, 405, { allow: 'GET, HEAD, PATCH, DELETE' });
  }
}

export function getFlat(db, id) {
  return db.prepare(`SELECT ${COLUMNS} FROM flat WHERE id = ?`).bind(id).first();
}

async function patchFlat(request, db, id, geocodeFn) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Body must be JSON' }, 400);
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return json({ error: 'Body must be a JSON object' }, 400);
  }
  const { values, errors } = validatePatch(body);
  if (Object.keys(errors).length) {
    return json({ error: 'Invalid fields', fields: errors }, 400);
  }

  const current = await getFlat(db, id);
  if (!current) return json({ error: 'Not found' }, 404);

  // A manual pin wins; otherwise a changed address is geocoded again.
  if ('lat' in values) {
    values.distance_m = values.lat === null ? null : distanceToDeodarM(values.lat, values.lng);
  } else if ('address' in values && values.address !== current.address) {
    const hit = await geocodeFn(values.address);
    values.lat = hit?.lat ?? null;
    values.lng = hit?.lng ?? null;
    values.distance_m = hit ? distanceToDeodarM(hit.lat, hit.lng) : null;
  }

  const cols = Object.keys(values);
  if (cols.length) {
    const sets = cols.map((c) => `${c} = ?`).join(', ');
    await db
      .prepare(`UPDATE flat SET ${sets}, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?`)
      .bind(...cols.map((c) => values[c]), id)
      .run();
  }
  return json(await getFlat(db, id));
}

/** Checks the editable fields present in body; unknown keys are ignored. */
export function validatePatch(body) {
  const values = {};
  const errors = {};
  const has = (k) => Object.prototype.hasOwnProperty.call(body, k);

  for (const k of ['name', 'address']) {
    if (!has(k)) continue;
    const v = typeof body[k] === 'string' ? body[k].trim() : '';
    if (v) values[k] = v;
    else errors[k] = 'Required';
  }
  for (const k of ['price', 'size_sqft']) {
    if (!has(k)) continue;
    const v = body[k];
    if (v === null) values[k] = null;
    else if (typeof v === 'number' && Number.isFinite(v) && v > 0) values[k] = Math.round(v);
    else errors[k] = 'Must be a positive number';
  }
  for (const k of ['bedrooms', 'bathrooms']) {
    if (!has(k)) continue;
    const v = body[k];
    if (v === null || (Number.isInteger(v) && v >= 0)) values[k] = v;
    else errors[k] = 'Must be a whole number, 0 or more';
  }
  if (has('listing_url')) {
    const v = body.listing_url;
    if (v === null || v === '') values.listing_url = null;
    else if (typeof v === 'string' && /^https?:\/\/\S+$/i.test(v.trim())) values.listing_url = v.trim();
    else errors.listing_url = 'Must be an http(s) link';
  }
  if (has('notes')) {
    const v = body.notes;
    if (v === null) values.notes = null;
    else if (typeof v !== 'string') errors.notes = 'Must be text';
    else if (v.length > NOTES_MAX) errors.notes = `At most ${NOTES_MAX} characters`;
    else values.notes = v;
  }
  if (has('discarded')) {
    const v = body.discarded;
    if (typeof v === 'boolean' || v === 0 || v === 1) values.discarded = v ? 1 : 0;
    else errors.discarded = 'Must be true or false';
  }
  if (has('lat') || has('lng')) {
    const { lat, lng } = body;
    if (lat === null && lng === null) {
      values.lat = null;
      values.lng = null;
    } else if (
      typeof lat === 'number' && lat >= -90 && lat <= 90 &&
      typeof lng === 'number' && lng >= -180 && lng <= 180
    ) {
      values.lat = lat;
      values.lng = lng;
    } else {
      errors.lat = 'Give lat and lng together, as coordinates';
    }
  }
  return { values, errors };
}

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
