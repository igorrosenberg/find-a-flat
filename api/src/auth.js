// Write check: every write needs the WRITE_PASSPHRASE secret in an
// X-Passphrase header. Minimal version for the detail page; the passphrase
// work (issue #8) owns this module and may replace it.

export const WRITES_DISABLED =
  'Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker.';

/** Returns an error Response when the write is not allowed, or null. */
export function requireWrite(request, env) {
  const secret = env.WRITE_PASSPHRASE;
  if (typeof secret !== 'string' || secret === '') {
    return errorResponse(WRITES_DISABLED, 503);
  }
  const given = request.headers.get('x-passphrase') ?? '';
  if (!constantTimeEqual(given, secret)) {
    return errorResponse('Wrong passphrase', 401);
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

function errorResponse(error, status) {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}
