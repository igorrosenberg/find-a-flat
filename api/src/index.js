// Find a flat: one Worker serving the Flutter web app (static assets from
// ../app/build/web) and a small JSON API, backed by D1 (binding DB).

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

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
