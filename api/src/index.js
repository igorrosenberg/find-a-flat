// Find a flat: one Worker serving the Flutter web app (static assets from
// ../app/build/web) and a small JSON API, backed by D1 (binding DB).

import { handleFlat, json } from './flat.js';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/') {
      return Response.redirect(new URL('/home', url).toString(), 302);
    }
    if (url.pathname === '/api/flats') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ error: 'Method not allowed' }, 405, { allow: 'GET, HEAD' });
      }
      return json(await listFlats(env.DB));
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
      'SELECT id, name, price, size_sqft, distance_m, discarded FROM flat ORDER BY created_at DESC, id DESC',
    )
    .all();
  return results ?? [];
}
