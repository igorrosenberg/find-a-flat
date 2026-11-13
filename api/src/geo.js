// Geocoding and distance, shared by every write that sets an address.

// 16/1 Deodar St, Ballygunge, Kolkata 700019: distances are measured from here.
export const REFERENCE_POINT = { lat: 22.5261, lng: 88.3598 };

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
const PHOTON_URL = 'https://photon.komoot.io/api/';
// Both services ask for an identifying User-Agent. It names the app and its
// public repository only, no personal data.
const USER_AGENT = 'find-a-flat/0.2 (+https://github.com/igorrosenberg/find-a-flat)';

// Tunables, exported so tests can make geocoding instant.
export const config = {
  geocodeIntervalMs: 1000, // Nominatim allows one request per second.
  geocodeTimeoutMs: 5000, // per request
  geocodeBudgetMs: 15000, // for all the attempts of one address
  maxQueries: 8, // simplified variants tried per address
  maxDistanceKm: 80, // a hit farther than this from Deodar St is a wrong match
};

// Around Greater Kolkata (lng/lat): ranks local matches first without
// excluding anything.
const KOLKATA_VIEWBOX = '87.9,23.1,88.9,21.9';

// Comma-separated pieces that only confuse a geocoder: ward and police
// station labels, "Old"/"New" markers, bare house or plot numbers, PIN codes
// and landmarks ("near ...", "opp. ...").
const NOISE = [
  /^ward(\s*no\.?)?(\s*[-#:]?\s*\d+)?$/i,
  /^(p\.?\s?s\.?|p\.?\s?o\.?|police station|post office)(\s*[-:]?\s*.*)?$/i,
  /^(old|new)$/i,
  /^(near|nr\.?|opp\.?|opposite|beside|behind)\b.*$/i,
  /^(flat|plot|house|holding|premises|door|no\.?)?\s*[#:]?\s*[\d/-]+\s*[a-z]?$/i,
  /^(west bengal|wb|india)$/i,
];
const NUMBERISH = /^[\d/-]+\s*[a-z]?$/i;

// Pieces of an address, cleaned: brackets and stray punctuation dropped,
// noise removed. Keeps house numbers when keepNumbers is set.
function addressParts(address, keepNumbers) {
  return String(address)
    .split(/[,;\n]+/)
    .map((p) => p.replace(/[()[\]{}]/g, ' ').replace(/\b\d{6}\b/g, ' ').replace(/\s+/g, ' ').trim().replace(/^[.\-:#]+|[.\-:#]+$/g, '').trim())
    .map((p) => (keepNumbers ? p : p.replace(/^[\d/-]+[a-z]?\s+(?=\D)/i, '')))
    .filter((p) => p && (keepNumbers && NUMBERISH.test(p) ? true : !NOISE.some((re) => re.test(p))));
}

// The queries to try for an address, most specific first. Geocoders want
// every word to match, so after the cleaned address come runs of consecutive
// pieces: those starting at the street first, longest first, then those
// starting at the locality, and so on. "Kolkata" is dropped in some of them
// because suburbs such as Narendrapur are not inside Kolkata on the map. The
// city alone is never tried: its centre says nothing about the flat.
export function geocodeQueries(address) {
  const queries = [];
  const add = (parts) => {
    const q = parts.join(', ');
    if (q && !queries.includes(q)) queries.push(q);
  };
  // A bare number reads as the house number of the next piece: "709 Kusumba Rd".
  const glued = [];
  for (const p of addressParts(address, true)) {
    if (glued.length && NUMBERISH.test(glued[glued.length - 1])) glued[glued.length - 1] += ` ${p}`;
    else glued.push(p);
  }
  add(glued);
  const parts = addressParts(address, false);
  if (parts.length === 1) add(parts);
  for (let i = 0; i < parts.length - 1; i++) {
    for (let j = parts.length; j > i; j--) add(parts.slice(i, j));
  }
  return queries.slice(0, config.maxQueries);
}

// Nominatim requests are spaced within this isolate.
let nextNominatimAt = 0;
async function nominatimTurn() {
  const now = Date.now();
  const wait = Math.max(0, nextNominatimAt - now);
  nextNominatimAt = now + wait + config.geocodeIntervalMs;
  if (wait) await new Promise((r) => setTimeout(r, wait));
}

class ServiceDown extends Error {}

async function getJson(url) {
  const res = await fetch(url, {
    headers: { 'user-agent': USER_AGENT, accept: 'application/json', 'accept-language': 'en' },
    signal: AbortSignal.timeout(config.geocodeTimeoutMs),
  });
  if (!res.ok) throw new ServiceDown(`HTTP ${res.status}`);
  return res.json();
}

// Candidate points from Nominatim for one query.
async function nominatim(q) {
  await nominatimTurn();
  const url = new URL(NOMINATIM_URL);
  url.search = new URLSearchParams({
    q, format: 'jsonv2', limit: '5', countrycodes: 'in', viewbox: KOLKATA_VIEWBOX, bounded: '0',
  });
  const hits = await getJson(url);
  return (Array.isArray(hits) ? hits : []).map((h) => ({ lat: Number(h?.lat), lng: Number(h?.lon) }));
}

// Candidate points from Photon (komoot), OSM data with fuzzier matching,
// biased towards Deodar St.
async function photon(q) {
  const url = new URL(PHOTON_URL);
  url.search = new URLSearchParams({
    q, limit: '5', lang: 'en', lat: String(REFERENCE_POINT.lat), lon: String(REFERENCE_POINT.lng),
  });
  const body = await getJson(url);
  return (body?.features ?? []).map((f) => {
    const [lng, lat] = f?.geometry?.coordinates ?? [];
    return { lat: Number(lat), lng: Number(lng) };
  });
}

// The first candidate that is a real point near Kolkata.
function nearby(points) {
  return (
    points.find(
      (p) =>
        Number.isFinite(p.lat) && Number.isFinite(p.lng) &&
        distanceMetres(p, REFERENCE_POINT) <= config.maxDistanceKm * 1000,
    ) ?? null
  );
}

// Returns { lat, lng } for an address, or null if it can't be found or the
// geocoders fail. Never throws: a flat is saved even without coordinates,
// and the detail page then offers to drop the pin by hand.
//
// Tries each simplified query on Nominatim; if Nominatim refuses or fails, or
// finds nothing for any of them, the same queries go to Photon.
export async function geocode(address) {
  const deadline = Date.now() + config.geocodeBudgetMs;
  const queries = geocodeQueries(address);
  for (const [name, lookup] of [['nominatim', nominatim], ['photon', photon]]) {
    for (const q of queries) {
      if (Date.now() >= deadline) {
        console.warn(`geocode: out of time for ${JSON.stringify(address)}`);
        return null;
      }
      try {
        const hit = nearby(await lookup(q));
        if (hit) {
          console.log(`geocode: ${name} found ${JSON.stringify(q)}`);
          return hit;
        }
      } catch (err) {
        console.warn(`geocode: ${name} failed (${err?.message ?? err}) for ${JSON.stringify(q)}`);
        break; // this service is down or refusing us: move to the next one
      }
    }
  }
  console.warn(`geocode: nothing found for ${JSON.stringify(address)}, tried ${JSON.stringify(queries)}`);
  return null;
}

// Straight-line (haversine) distance in metres between two points.
export function distanceMetres(a, b) {
  const R = 6371008.8;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// Whole metres from (lat, lng) to the Deodar Street reference point.
export function distanceToDeodarM(lat, lng) {
  return Math.round(distanceMetres({ lat, lng }, REFERENCE_POINT));
}
