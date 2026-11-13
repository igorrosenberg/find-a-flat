import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import { config, distanceMetres, distanceToDeodarM, REFERENCE_POINT } from '../src/geo.js';

config.geocodeIntervalMs = 0;

// A D1 stand-in that records the INSERT and returns the row it would store.
function env({ passphrase = 'secret' } = {}) {
  const inserts = [];
  return {
    inserts,
    WRITE_PASSPHRASE: passphrase,
    DB: {
      prepare: (sql) => ({
        bind: (...args) => ({
          first: async () => {
            inserts.push({ sql, args });
            const [name, address, price, size_sqft, bedrooms, bathrooms, listing_url, lat, lng, distance_m] = args;
            return { id: 7, name, address, price, size_sqft, bedrooms, bathrooms, listing_url, lat, lng, distance_m, discarded: 0 };
          },
        }),
      }),
    },
  };
}

const realFetch = globalThis.fetch;
let geocodeRequests;
let geocodeReply;
beforeEach(() => {
  geocodeRequests = [];
  geocodeReply = () => Response.json([{ lat: '22.5361', lon: '88.3598' }]);
  globalThis.fetch = async (url, init) => {
    geocodeRequests.push({ url: new URL(url), init });
    return geocodeReply();
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

const post = (body, e = env(), headers = { 'x-passphrase': 'secret' }) =>
  worker.fetch(
    new Request('https://example.com/api/flats', {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
    e,
  );

const valid = {
  name: '2-bed near park',
  address: '12 Gariahat Road, Kolkata',
  price: 10500000,
  size_sqft: 1100,
  bedrooms: 2,
  bathrooms: 0,
  listing_url: 'https://example.com/ad/1',
};

test('POST /api/flats geocodes, stores the distance and returns 201', async () => {
  const e = env();
  const res = await post(valid, e);
  assert.equal(res.status, 201);
  assert.equal(res.headers.get('location'), '/api/flats/7');
  const flat = await res.json();
  assert.equal(flat.id, 7);
  assert.equal(flat.lat, 22.5361);
  assert.equal(flat.lng, 88.3598);
  // 0.01 degree of latitude is about 1.11 km.
  assert.ok(Math.abs(flat.distance_m - 1112) <= 1, `got ${flat.distance_m}`);
  assert.match(e.inserts[0].sql, /INSERT INTO flat/);

  const { url, init } = geocodeRequests[0];
  assert.equal(url.hostname, 'nominatim.openstreetmap.org');
  assert.equal(url.searchParams.get('q'), valid.address);
  assert.match(init.headers['user-agent'], /find-a-flat/);
});

test('a flat is still saved when geocoding finds nothing or fails', async () => {
  geocodeReply = () => Response.json([]);
  let flat = await (await post(valid)).json();
  assert.deepEqual([flat.lat, flat.lng, flat.distance_m], [null, null, null]);

  geocodeReply = () => new Response('busy', { status: 503 });
  flat = await (await post(valid)).json();
  assert.equal(flat.distance_m, null);

  geocodeReply = () => {
    throw new TypeError('network down');
  };
  const res = await post(valid);
  assert.equal(res.status, 201);
  assert.equal((await res.json()).distance_m, null);
});

test('optional fields can be left out', async () => {
  const flat = await (await post({ name: 'Bare', address: 'Somewhere' })).json();
  assert.deepEqual(
    [flat.price, flat.size_sqft, flat.bedrooms, flat.bathrooms, flat.listing_url],
    [null, null, null, null, null],
  );
});

test('invalid fields are reported per field and nothing is saved', async () => {
  const e = env();
  const res = await post(
    { name: ' ', price: -1, size_sqft: 'big', bedrooms: 1.5, bathrooms: -1, listing_url: 'ftp://x' },
    e,
  );
  assert.equal(res.status, 400);
  const { fields } = await res.json();
  assert.deepEqual(Object.keys(fields).sort(), [
    'address', 'bathrooms', 'bedrooms', 'listing_url', 'name', 'price', 'size_sqft',
  ]);
  assert.equal(e.inserts.length, 0);
  assert.equal(geocodeRequests.length, 0);
  assert.equal((await post('not json', e)).status, 400);
});

test('writes need the passphrase', async () => {
  const e = env();
  assert.equal((await post(valid, e, {})).status, 401);
  const wrong = await post(valid, e, { 'x-passphrase': 'nope' });
  assert.equal(wrong.status, 401);
  assert.deepEqual(await wrong.json(), { error: 'Wrong passphrase' });
  assert.equal((await post(valid, env({ passphrase: '' }))).status, 503);
  assert.equal(e.inserts.length, 0);
});

test('distance helpers', () => {
  assert.equal(distanceToDeodarM(REFERENCE_POINT.lat, REFERENCE_POINT.lng), 0);
  // Deodar St to Howrah station (22.5839, 88.3424) is roughly 6.6 km.
  const d = distanceMetres(REFERENCE_POINT, { lat: 22.5839, lng: 88.3424 });
  assert.ok(d > 6400 && d < 6800, `got ${d}`);
});
