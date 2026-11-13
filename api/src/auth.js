// Access control: the whole app (every page, static file and API call) needs
// the shared passphrase from the Worker secret WRITE_PASSPHRASE.
//
// Without a valid session cookie, pages get a login page and /api/* gets 401.
// POST /login with the right passphrase sets an HttpOnly session cookie for a
// year. The cookie value is an HMAC of the passphrase, so changing the secret
// signs everyone out.
//
// index.js calls `gate(request, env)` first on every request. Write endpoints
// may also call `const denied = await requireWrite(request, env); if (denied)
// return denied;` as a second check.

export const NO_PASSPHRASE_MESSAGE =
  'Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker.';

export const SESSION_COOKIE = 'faf_session';
const SESSION_MAX_AGE_S = 365 * 24 * 60 * 60;

// Failed logins per client IP before logins from it are refused for a while.
export const MAX_FAILURES = 5;
export const FAILURE_WINDOW_S = 15 * 60;

export function passphraseIsSet(env) {
  return typeof env.WRITE_PASSPHRASE === 'string' && env.WRITE_PASSPHRASE.length > 0;
}

// Returns the Response to send instead of the app, or null when the request
// may go on to the app or API.
export async function gate(request, env) {
  if (!passphraseIsSet(env)) return noPassphrasePage();
  const url = new URL(request.url);
  if (url.pathname === '/login' && request.method === 'POST') return login(request, env);
  if (await hasSession(request, env)) return null;
  if (url.pathname.startsWith('/api/')) {
    return json({ error: 'Passphrase needed' }, 401);
  }
  const next = url.pathname === '/login' ? url.searchParams.get('next') : url.pathname + url.search;
  return loginPage({ next, status: 401 });
}

// Second line of defence for write endpoints; the gate already ran.
export async function requireWrite(request, env) {
  if (!passphraseIsSet(env)) return json({ error: NO_PASSPHRASE_MESSAGE }, 503);
  if (await hasSession(request, env)) return null;
  return json({ error: 'Passphrase needed' }, 401);
}

export async function sessionToken(env) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(env.WRITE_PASSPHRASE), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, enc.encode('find-a-flat session v1'));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function hasSession(request, env) {
  const cookie = readCookie(request.headers.get('cookie'), SESSION_COOKIE);
  if (!cookie) return false;
  return safeEqual(cookie, await sessionToken(env));
}

async function login(request, env) {
  const form = await request.formData().catch(() => null);
  const next = safeNext(form?.get('next'));
  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  const now = Math.floor(Date.now() / 1000);

  const row = await env.DB
    .prepare('SELECT failures, window_start FROM write_failure WHERE ip = ?1')
    .bind(ip)
    .first();
  if (row && now - row.window_start < FAILURE_WINDOW_S && row.failures >= MAX_FAILURES) {
    const retryAfter = FAILURE_WINDOW_S - (now - row.window_start);
    const minutes = Math.ceil(retryAfter / 60);
    const res = loginPage({
      next,
      status: 429,
      error: `Too many wrong passphrases. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`,
    });
    res.headers.set('retry-after', String(retryAfter));
    return res;
  }

  const given = typeof form?.get('passphrase') === 'string' ? form.get('passphrase') : '';
  if (await safeEqual(given, env.WRITE_PASSPHRASE)) {
    return new Response(null, {
      status: 303,
      headers: {
        location: new URL(next, request.url).toString(),
        'set-cookie': `${SESSION_COOKIE}=${await sessionToken(env)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${SESSION_MAX_AGE_S}`,
        'cache-control': 'no-store',
      },
    });
  }

  // Count the failure, starting a new window when the old one has expired.
  await env.DB
    .prepare(
      `INSERT INTO write_failure (ip, failures, window_start) VALUES (?1, 1, ?2)
       ON CONFLICT(ip) DO UPDATE SET
         failures = CASE WHEN ?2 - window_start >= ?3 THEN 1 ELSE failures + 1 END,
         window_start = CASE WHEN ?2 - window_start >= ?3 THEN ?2 ELSE window_start END`,
    )
    .bind(ip, now, FAILURE_WINDOW_S)
    .run();
  return loginPage({ next, status: 401, error: 'Wrong passphrase' });
}

// Only same-site paths, so the login form can't redirect elsewhere.
function safeNext(value) {
  if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) {
    return '/home';
  }
  return value;
}

function readCookie(header, name) {
  for (const part of (header ?? '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=');
  }
  return null;
}

// Constant-time comparison: hash both sides so lengths match, then compare
// every byte whatever the result.
export async function safeEqual(a, b) {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b)),
  ]);
  if (typeof crypto.subtle.timingSafeEqual === 'function') {
    return crypto.subtle.timingSafeEqual(ha, hb);
  }
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// The only thing the Worker serves, on every path, while the secret is unset.
export function noPassphrasePage() {
  return page(
    503,
    'Flats is not configured',
    `<p>${NO_PASSPHRASE_MESSAGE}</p>
<p>Run <code>wrangler secret put WRITE_PASSPHRASE</code>, or add it in the Cloudflare dashboard under the Worker's Settings, Variables and Secrets.</p>`,
  );
}

export function loginPage({ next, status = 401, error = null }) {
  return page(
    status,
    'Flats',
    `<form method="post" action="/login">
<label for="passphrase">Passphrase</label>
<input id="passphrase" name="passphrase" type="password" autocomplete="current-password" autofocus required>
<input type="hidden" name="next" value="${escapeHtml(safeNext(next))}">
${error ? `<p class="error" role="alert">${escapeHtml(error)}</p>` : ''}
<button type="submit">Enter</button>
</form>
<p class="hint">This browser stays signed in for a year, or until the passphrase changes.</p>`,
  );
}

function page(status, title, body) {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-mobile-web-app-title" content="Flats">
<title>${escapeHtml(title)}</title>
<style>
  :root { --bg: #fff; --fg: #1b1b1b; --muted: #5f5f5f; --line: #c4c4c4; --accent: #00695c; --error: #b3261e; --code: #eee; }
  @media (prefers-color-scheme: dark) { :root { --bg: #121212; --fg: #e6e6e6; --muted: #a8a8a8; --line: #555; --accent: #4db6ac; --error: #f2b8b5; --code: #333; } }
  body { font-family: system-ui, sans-serif; margin: 0; padding: 48px 16px; background: var(--bg); color: var(--fg); }
  main { max-width: 400px; margin: 0 auto; }
  code { background: var(--code); padding: 1px 4px; border-radius: 3px; }
  label { display: block; font-weight: 600; margin-bottom: 6px; }
  input[type=password] { box-sizing: border-box; width: 100%; font-size: 16px; padding: 10px; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); }
  button { margin-top: 16px; font-size: 16px; padding: 10px 20px; border: 0; border-radius: 20px; background: var(--accent); color: var(--bg); cursor: pointer; }
  .error { color: var(--error); margin: 8px 0 0; }
  .hint { color: var(--muted); font-size: 14px; margin-top: 24px; }
</style>
</head>
<body>
<main>
<h1>${escapeHtml(title)}</h1>
${body}
</main>
</body>
</html>
`;
  return new Response(html, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
  });
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function json(body, status, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
