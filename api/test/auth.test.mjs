import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gate, MAX_FAILURES, requireWrite, safeEqual, SESSION_COOKIE, sessionToken } from '../src/auth.js';

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

const makeEnv = () => ({ WRITE_PASSPHRASE: 'open sesame', DB: fakeDb() });

const login = (passphrase, { ip = '1.2.3.4', next = '/flats/3' } = {}) =>
  new Request('https://example.com/login', {
    method: 'POST',
    headers: { 'cf-connecting-ip': ip },
    body: new URLSearchParams({ passphrase, next }),
  });

const cookieFrom = (res) => res.headers.get('set-cookie').split(';')[0];

test('the right passphrase sets a session cookie and goes to next', async () => {
  const env = makeEnv();
  const res = await gate(login('open sesame'), env);
  assert.equal(res.status, 303);
  assert.equal(res.headers.get('location'), 'https://example.com/flats/3');
  const setCookie = res.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /Secure/);
  assert.match(setCookie, /SameSite=Lax/);
  assert.equal(cookieFrom(res), `${SESSION_COOKIE}=${await sessionToken(env)}`);

  // With that cookie, the gate lets requests through and writes are allowed.
  const req = new Request('https://example.com/api/flats', { method: 'POST', headers: { cookie: cookieFrom(res) } });
  assert.equal(await gate(req, env), null);
  assert.equal(await requireWrite(req, env), null);
});

test('next must stay on this site', async () => {
  for (const next of ['https://evil.example', '//evil.example', '/\\evil.example', 'home']) {
    const res = await gate(login('open sesame', { next }), makeEnv());
    assert.equal(res.headers.get('location'), 'https://example.com/home', next);
  }
});

test('a wrong passphrase shows the login page again with Wrong passphrase', async () => {
  for (const p of ['', 'open sesam', 'Open sesame']) {
    const res = await gate(login(p), makeEnv());
    assert.equal(res.status, 401);
    assert.equal(res.headers.get('set-cookie'), null);
    const html = await res.text();
    assert.match(html, /Wrong passphrase/);
    assert.match(html, /name="next" value="\/flats\/3"/);
  }
});

test('changing the passphrase ends old sessions', async () => {
  const old = `${SESSION_COOKIE}=${await sessionToken({ WRITE_PASSPHRASE: 'old' })}`;
  const req = new Request('https://example.com/home', { headers: { cookie: old } });
  assert.equal((await gate(req, makeEnv())).status, 401);
});

test('too many failures from one IP are rate limited, even with the right passphrase', async () => {
  const env = makeEnv();
  for (let i = 0; i < MAX_FAILURES; i++) {
    assert.equal((await gate(login('nope'), env)).status, 401);
  }
  const blocked = await gate(login('open sesame'), env);
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  assert.match(await blocked.text(), /Too many wrong passphrases/);
  // Another IP is unaffected.
  assert.equal((await gate(login('open sesame', { ip: '5.6.7.8' }), env)).status, 303);
  // Once the window has passed, the IP may try again.
  env.DB.rows.get('1.2.3.4').window_start -= 3600;
  assert.equal((await gate(login('open sesame'), env)).status, 303);
});

test('everything is the error page while the secret is unset', async () => {
  for (const value of [undefined, '']) {
    const res = await gate(login('x'), { WRITE_PASSPHRASE: value, DB: fakeDb() });
    assert.equal(res.status, 503);
    const write = new Request('https://example.com/api/flats', { method: 'POST' });
    assert.equal((await requireWrite(write, { WRITE_PASSPHRASE: value })).status, 503);
  }
});

test('safeEqual', async () => {
  assert.equal(await safeEqual('abc', 'abc'), true);
  assert.equal(await safeEqual('abc', 'abd'), false);
  assert.equal(await safeEqual('abc', 'abcd'), false);
});
