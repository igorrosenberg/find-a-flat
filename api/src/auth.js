// Write protection: reads are public, every write needs the shared passphrase
// from the Worker secret WRITE_PASSPHRASE, sent in the X-Passphrase header.
//
// Write endpoints call:
//   const denied = await requireWrite(request, env);
//   if (denied) return denied;

export const NO_PASSPHRASE_MESSAGE =
  'Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker.';

// Failed attempts per client IP before writes from it are refused for a while.
export const MAX_FAILURES = 5;
export const FAILURE_WINDOW_S = 15 * 60;

export function passphraseIsSet(env) {
  return typeof env.WRITE_PASSPHRASE === 'string' && env.WRITE_PASSPHRASE.length > 0;
}

// The only thing the Worker serves, on every path, while the secret is unset.
export function noPassphrasePage() {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Find a flat: not configured</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; padding: 48px 16px; background: #fff; color: #1b1b1b; }
  main { max-width: 560px; margin: 0 auto; }
  code { background: #eee; padding: 1px 4px; border-radius: 3px; }
  @media (prefers-color-scheme: dark) { body { background: #121212; color: #e6e6e6; } code { background: #333; } }
</style>
</head>
<body>
<main>
<h1>Find a flat is not configured</h1>
<p>${NO_PASSPHRASE_MESSAGE}</p>
<p>Run <code>wrangler secret put WRITE_PASSPHRASE</code>, or add it in the Cloudflare dashboard under the Worker's Settings, Variables and Secrets.</p>
</main>
</body>
</html>
`;
  return new Response(html, {
    status: 503,
    headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
  });
}

// Returns null when the request may write, otherwise the Response to send back.
export async function requireWrite(request, env) {
  if (!passphraseIsSet(env)) {
    return json({ error: NO_PASSPHRASE_MESSAGE }, 503);
  }
  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  const now = Math.floor(Date.now() / 1000);

  const row = await env.DB
    .prepare('SELECT failures, window_start FROM write_failure WHERE ip = ?1')
    .bind(ip)
    .first();
  if (row && now - row.window_start < FAILURE_WINDOW_S && row.failures >= MAX_FAILURES) {
    const retryAfter = FAILURE_WINDOW_S - (now - row.window_start);
    return json({ error: 'Too many wrong passphrases. Try again later.' }, 429, {
      'retry-after': String(retryAfter),
    });
  }

  const given = request.headers.get('x-passphrase') ?? '';
  if (await safeEqual(given, env.WRITE_PASSPHRASE)) return null;

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
  return json({ error: 'Wrong passphrase' }, 401);
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

function json(body, status, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
