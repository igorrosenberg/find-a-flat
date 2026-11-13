// Find a flat: one Worker, server-rendered pages, backed by D1 (binding DB).

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
    }
    if (url.pathname === '/') {
      return Response.redirect(new URL('/home', url).toString(), 302);
    }
    if (url.pathname === '/home') {
      const flats = await listFlats(env.DB);
      return new Response(renderHome(flats), {
        headers: { 'content-type': 'text/html; charset=utf-8' },
      });
    }
    return new Response('Not found', { status: 404 });
  },
};

export async function listFlats(db) {
  const { results } = await db
    .prepare('SELECT id, name, price, size_sqft, distance_m, discarded FROM flat ORDER BY created_at DESC, id DESC')
    .all();
  return results ?? [];
}

// Price is always shown in crore, two decimals, never lakh.
export function formatCrore(rupees) {
  if (rupees == null) return '–';
  return `₹${(rupees / 1e7).toFixed(2)} Cr`;
}

export function formatKm(metres) {
  if (metres == null) return '–';
  return `${(metres / 1000).toFixed(1)} km`;
}

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
}

export function renderHome(flats) {
  const rows = flats.map((f) => `
      <tr${f.discarded ? ' class="discarded"' : ''}>
        <td>${escapeHtml(f.name)}</td>
        <td>${formatCrore(f.price)}</td>
        <td>${f.size_sqft ?? '–'}</td>
        <td>${formatKm(f.distance_m)}</td>
      </tr>`).join('');
  const body = flats.length
    ? `<div class="scroll"><table>
      <thead><tr><th>Name</th><th>Price</th><th>Size (sq ft)</th><th>Distance to Deodar Street</th></tr></thead>
      <tbody>${rows}
      </tbody>
    </table></div>`
    : '<p class="empty">No flats yet.</p>';
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Find a flat</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0 auto; max-width: 960px; padding: 16px; }
    .scroll { overflow-x: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; white-space: nowrap; }
    tr.discarded td { text-decoration: line-through; color: #999; }
    .empty { color: #666; }
  </style>
</head>
<body>
  <h1>Find a flat</h1>
  ${body}
</body>
</html>`;
}
