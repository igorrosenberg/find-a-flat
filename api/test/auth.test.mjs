import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_FAILURES, requireWrite, safeEqual } from '../src/auth.js';

// A tiny stand-in for D1 that understands the write_failure queries.
function fakeDb() {
  const rows = new Map();
  return {
    rows,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async first() {
              return rows.get(args[0]) ?? null;
            },
            async run() {
              assert.match(sql, /INSERT INTO write_failure/);
              const [ip, now, windowS] = args;
              const row = rows.get(ip);
              if (!row || now - row.window_start >= windowS) {
                rows.set(ip, { failures: 1, window_start: now });
              } else {
                row.failures += 1;
              }
            },
          };
        },
      };
    },
  };
}

const write = (passphrase, ip = '1.2.3.4') =>
  new Request('https://example.com/api/flats', {
    method: 'POST',
    headers: {
      'cf-connecting-ip': ip,
      ...(passphrase === undefined ? {} : { 'x-passphrase': passphrase }),
    },
  });

test('the right passphrase is allowed', async () => {
  const env = { WRITE_PASSPHRASE: 'open sesame', DB: fakeDb() };
  assert.equal(await requireWrite(write('open sesame'), env), null);
});

test('a missing or wrong passphrase is 401 Wrong passphrase', async () => {
  const env = { WRITE_PASSPHRASE: 'open sesame', DB: fakeDb() };
  for (const p of [undefined, '', 'open sesam', 'Open sesame']) {
    const res = await requireWrite(write(p), env);
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: 'Wrong passphrase' });
  }
});

test('writes are 503 when the secret is unset', async () => {
  for (const value of [undefined, '']) {
    const res = await requireWrite(write('x'), { WRITE_PASSPHRASE: value, DB: fakeDb() });
    assert.equal(res.status, 503);
  }
});

test('too many failures from one IP are rate limited, even with the right passphrase', async () => {
  const env = { WRITE_PASSPHRASE: 'open sesame', DB: fakeDb() };
  for (let i = 0; i < MAX_FAILURES; i++) {
    assert.equal((await requireWrite(write('nope'), env)).status, 401);
  }
  const blocked = await requireWrite(write('open sesame'), env);
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  // Another IP is unaffected.
  assert.equal(await requireWrite(write('open sesame', '5.6.7.8'), env), null);
  // Once the window has passed, the IP may try again.
  env.DB.rows.get('1.2.3.4').window_start -= 3600;
  assert.equal(await requireWrite(write('open sesame'), env), null);
});

test('safeEqual', async () => {
  assert.equal(await safeEqual('abc', 'abc'), true);
  assert.equal(await safeEqual('abc', 'abd'), false);
  assert.equal(await safeEqual('abc', 'abcd'), false);
});
