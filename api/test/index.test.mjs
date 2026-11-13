import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

function env(rows = []) {
  return {
    DB: { prepare: () => ({ all: async () => ({ results: rows }) }) },
    ASSETS: { fetch: async (req) => new Response(`asset ${new URL(req.url).pathname}`) },
  };
}

const call = (path, rows, init) =>
  worker.fetch(new Request(`https://example.com${path}`, init), env(rows));

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
