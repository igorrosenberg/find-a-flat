// Write check for every write endpoint. Minimal stand-in: the passphrase
// issue (#8) owns the full behaviour (rate limiting, error page) and replaces
// this file. Returns a Response to send back, or null when the write may go on:
// 503 when no secret is set, 401 when X-Passphrase is missing or wrong.
export async function requireWrite(request, env) {
  const secret = env.WRITE_PASSPHRASE;
  if (!secret) {
    return json(
      { error: 'Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker.' },
      503,
    );
  }
  if (!constantTimeEqual(request.headers.get('x-passphrase') ?? '', secret)) {
    return json({ error: 'Wrong passphrase' }, 401);
  }
  return null;
}

function constantTimeEqual(a, b) {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < y.length; i++) diff |= (x[i] ?? 0) ^ y[i];
  return diff === 0;
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}
