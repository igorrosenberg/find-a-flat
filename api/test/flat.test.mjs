import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import { handleFlat } from '../src/flat.js';
import { distanceToDeodarM } from '../src/geo.js';
import { memoryD1 } from './d1.mjs';

const PASS = 'open sesame';

function setup() {
  const DB = memoryD1();
  DB.raw
    .prepare(
      `INSERT INTO flat (name, address, price, size_sqft, lat, lng, distance_m)
       VALUES ('Park flat', '1 Park St, Kolkata', 9500000, 1100, 22.55, 88.35, 2800)`,
    )
    .run();
  return { DB, WRITE_PASSPHRASE: PASS, ASSETS: { fetch: async () => new Response('asset') } };
}

const req = (method, body, pass = PASS) =>
  new Request('https://example.com/api/flats/1', {
    method,
    headers: { 'content-type': 'application/json', ...(pass == null ? {} : { 'x-passphrase': pass }) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

test('GET returns every column of one flat', async () => {
  const res = await worker.fetch(new Request('https://example.com/api/flats/1'), setup());
  assert.equal(res.status, 200);
  const flat = await res.json();
  assert.equal(flat.name, 'Park flat');
  assert.equal(flat.address, '1 Park St, Kolkata');
  assert.equal(flat.discarded, 0);
  assert.ok('notes' in flat && 'bedrooms' in flat && 'listing_url' in flat);
});

test('GET of an unknown or malformed id is 404', async () => {
  const env = setup();
  assert.equal((await worker.fetch(new Request('https://example.com/api/flats/99'), env)).status, 404);
  assert.equal((await worker.fetch(new Request('https://example.com/api/flats/abc'), env)).status, 404);
});

test('writes need the passphrase', async () => {
  const env = setup();
  assert.equal((await worker.fetch(req('PATCH', { notes: 'x' }, null), env)).status, 401);
  assert.equal((await worker.fetch(req('DELETE', undefined, 'wrong'), env)).status, 401);
  const unset = { ...env, WRITE_PASSPHRASE: '' };
  const res = await worker.fetch(req('PATCH', { notes: 'x' }), unset);
  assert.equal(res.status, 503);
  assert.match((await res.json()).error, /WRITE_PASSPHRASE/);
});

test('PATCH saves notes and discarded', async () => {
  const env = setup();
  const res = await worker.fetch(req('PATCH', { notes: 'Nice balcony', discarded: true }), env);
  assert.equal(res.status, 200);
  const flat = await res.json();
  assert.equal(flat.notes, 'Nice balcony');
  assert.equal(flat.discarded, 1);
  assert.equal(flat.price, 9500000);
});

test('PATCH rejects bad fields and notes over 10,000 characters', async () => {
  const env = setup();
  const res = await worker.fetch(
    req('PATCH', { name: ' ', price: -1, bedrooms: 1.5, notes: 'x'.repeat(10001), listing_url: 'nope' }),
    env,
  );
  assert.equal(res.status, 400);
  const { fields } = await res.json();
  assert.deepEqual(Object.keys(fields).sort(), ['bedrooms', 'listing_url', 'name', 'notes', 'price']);
});

test('a changed address is geocoded again', async () => {
  const env = setup();
  const hit = { lat: 22.5261, lng: 88.3598 };
  let res = await handleFlat(req('PATCH', { address: 'Deodar St' }), env, 1, { geocode: async () => hit });
  let flat = await res.json();
  assert.deepEqual([flat.lat, flat.lng, flat.distance_m], [22.5261, 88.3598, 0]);

  res = await handleFlat(req('PATCH', { address: 'Nowhere' }), env, 1, { geocode: async () => null });
  flat = await res.json();
  assert.deepEqual([flat.lat, flat.lng, flat.distance_m], [null, null, null]);
});

test('a manual pin sets coordinates and distance', async () => {
  const env = setup();
  const res = await handleFlat(req('PATCH', { lat: 22.5351, lng: 88.3598 }), env, 1, {
    geocode: async () => assert.fail('pin must not geocode'),
  });
  const flat = await res.json();
  assert.equal(flat.lat, 22.5351);
  assert.ok(Math.abs(flat.distance_m - 1001) <= 2, `distance ${flat.distance_m}`);
});

test('DELETE removes the flat', async () => {
  const env = setup();
  assert.equal((await worker.fetch(req('DELETE'), env)).status, 204);
  assert.equal((await worker.fetch(req('DELETE'), env)).status, 404);
  assert.equal((await worker.fetch(new Request('https://example.com/api/flats/1'), env)).status, 404);
});

test('distance is 0 at Deodar Street', () => {
  assert.equal(distanceToDeodarM(22.5261, 88.3598), 0);
});
