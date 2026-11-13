import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import { SESSION_COOKIE, sessionToken } from '../src/auth.js';

const session = `${SESSION_COOKIE}=${await sessionToken({ WRITE_PASSPHRASE: 'open sesame' })}`;

function env(rows = []) {
  return {
    WRITE_PASSPHRASE: 'open sesame',
    DB: { prepare: () => ({ all: async () => ({ results: rows }) }) },
    ASSETS: { fetch: async (req) => new Response(`asset ${new URL(req.url).pathname}`) },
  };
}

// Requests carry a valid session cookie unless init.headers says otherwise.
const call = (path, rows, init = {}, overrides = {}) =>
  worker.fetch(
    new Request(`https://example.com${path}`, { ...init, headers: { cookie: session, ...init.headers } }),
    { ...env(rows), ...overrides },
  );

test('/ redirects to /home', async () => {
  const res = await call('/');
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), 'https://example.com/home');
});

test('/home is served by the Flutter app', async () => {
  const res = await call('/home');
  assert.equal(await res.text(), 'asset /home');
});

test('/api/flats returns an empty list when the table is empty', async () => {
  const res = await call('/api/flats');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /application\/json/);
  assert.deepEqual(await res.json(), []);
});

test('/api/flats returns the rows of the flat table', async () => {
  const rows = [{ id: 1, name: 'Test flat', price: 9500000, size_sqft: 1100, distance_m: 1800, discarded: 0 }];
  assert.deepEqual(await (await call('/api/flats', rows)).json(), rows);
});

test('other methods are refused and unknown API paths are 404', async () => {
  assert.equal((await call('/api/flats', [], { method: 'PUT' })).status, 405);
  assert.equal((await call('/api/nope')).status, 404);
});

for (const value of [undefined, '']) {
  test(`every path is the error page when WRITE_PASSPHRASE is ${JSON.stringify(value)}`, async () => {
    for (const path of ['/', '/home', '/api/flats', '/main.dart.js']) {
      const res = await call(path, [], undefined, { WRITE_PASSPHRASE: value });
      assert.equal(res.status, 503, path);
      assert.match(res.headers.get('content-type'), /text\/html/);
      assert.match(await res.text(), /Set the WRITE_PASSPHRASE secret on this Worker\./);
    }
  });
}

test('without a session, pages show the login page and the API is 401', async () => {
  for (const cookie of ['', `${SESSION_COOKIE}=wrong`]) {
    const page = await call('/home?x=1', [], { headers: { cookie } });
    assert.equal(page.status, 401);
    const html = await page.text();
    assert.match(html, /<form method="post" action="\/login">/);
    // Signing in replaces the login page, so Back skips it.
    assert.match(html, /location\.replace\(res\.url\)/);
    assert.match(html, /name="next" value="\/home\?x=1"/);
    for (const path of ['/', '/main.dart.js']) {
      assert.equal((await call(path, [], { headers: { cookie } })).status, 401, path);
    }
    const api = await call('/api/flats', [], { headers: { cookie } });
    assert.equal(api.status, 401);
    assert.deepEqual(await api.json(), { error: 'Passphrase needed' });
  }
});
