import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { config, geocode, geocodeQueries } from '../src/geo.js';

config.geocodeIntervalMs = 0;

const realFetch = globalThis.fetch;
const realWarn = console.warn;
const realLog = console.log;
let requests;
let reply;
beforeEach(() => {
  requests = [];
  globalThis.fetch = async (url) => {
    const u = new URL(url);
    requests.push(u);
    return reply(u);
  };
  console.warn = console.log = () => {};
});
afterEach(() => {
  globalThis.fetch = realFetch;
  console.warn = realWarn;
  console.log = realLog;
});

const messy = 'Ward No. 7, New),PS, P.S, 709, Kusumba Rd, Old, Narendrapur, Rajpur Sonarpur, Kolkata';
// Narendrapur, south of Kolkata.
const NARENDRAPUR = { lat: '22.4370', lon: '88.3946' };
const service = (u) => (u.hostname.startsWith('nominatim') ? 'nominatim' : 'photon');
const asks = () => requests.map((u) => `${service(u)}: ${u.searchParams.get('q')}`);

test('a messy address is cleaned and simplified step by step', () => {
  assert.deepEqual(geocodeQueries(messy), [
    '709 Kusumba Rd, Narendrapur, Rajpur Sonarpur, Kolkata',
    'Kusumba Rd, Narendrapur, Rajpur Sonarpur, Kolkata',
    'Kusumba Rd, Narendrapur, Rajpur Sonarpur',
    'Kusumba Rd, Narendrapur',
    'Kusumba Rd',
    'Narendrapur, Rajpur Sonarpur, Kolkata',
    'Narendrapur, Rajpur Sonarpur',
    'Narendrapur',
  ]);
  assert.deepEqual(geocodeQueries('16/1 Deodar St, Ballygunge, Kolkata 700019, India').slice(0, 2), [
    '16/1 Deodar St, Ballygunge, Kolkata',
    'Deodar St, Ballygunge, Kolkata',
  ]);
  assert.deepEqual(geocodeQueries('Flat 3B, Near City Centre, Salt Lake Sector 1, Kolkata - 700064'), [
    'Salt Lake Sector 1, Kolkata',
    'Salt Lake Sector 1',
  ]);
  assert.deepEqual(geocodeQueries('Somewhere'), ['Somewhere']);
});

test('simpler queries are tried until one is found', async () => {
  reply = (u) => Response.json(u.searchParams.get('q') === 'Kusumba Rd, Narendrapur' ? [NARENDRAPUR] : []);
  assert.deepEqual(await geocode(messy), { lat: 22.437, lng: 88.3946 });
  assert.equal(requests.length, 4);
  const u = requests[0];
  assert.equal(u.searchParams.get('countrycodes'), 'in');
  assert.ok(u.searchParams.get('viewbox'), 'biased to Kolkata');
});

test('a match far from Kolkata is ignored', async () => {
  // A Kusumba Road in another state, then the right Narendrapur.
  reply = (u) =>
    Response.json(
      u.searchParams.get('q') === 'Kusumba Rd' ? [{ lat: '26.85', lon: '80.95' }]
      : u.searchParams.get('q') === 'Narendrapur, Rajpur Sonarpur, Kolkata' ? [NARENDRAPUR]
      : [],
    );
  assert.deepEqual(await geocode(messy), { lat: 22.437, lng: 88.3946 });
});

test('Photon takes over when Nominatim refuses', async () => {
  reply = (u) =>
    service(u) === 'nominatim'
      ? new Response('blocked', { status: 403 })
      : Response.json({ features: [{ geometry: { coordinates: [88.3946, 22.437] } }] });
  assert.deepEqual(await geocode(messy), { lat: 22.437, lng: 88.3946 });
  assert.deepEqual(asks(), [
    'nominatim: 709 Kusumba Rd, Narendrapur, Rajpur Sonarpur, Kolkata',
    'photon: 709 Kusumba Rd, Narendrapur, Rajpur Sonarpur, Kolkata',
  ]);
  assert.equal(requests[1].searchParams.get('lat'), '22.5261');
});

test('Photon gets the queries Nominatim found nothing for', async () => {
  reply = (u) =>
    Response.json(service(u) === 'nominatim' ? [] : { features: [{ geometry: { coordinates: [88.3946, 22.437] } }] });
  assert.deepEqual(await geocode(messy), { lat: 22.437, lng: 88.3946 });
  assert.equal(requests.filter((u) => service(u) === 'nominatim').length, 8);
});

test('nothing found anywhere gives null', async () => {
  reply = (u) => Response.json(service(u) === 'nominatim' ? [] : { features: [] });
  assert.equal(await geocode(messy), null);
  reply = () => {
    throw new TypeError('network down');
  };
  assert.equal(await geocode(messy), null);
});
