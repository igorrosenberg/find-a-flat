// Geocoding and distance, shared by every write that sets an address.

// 16/1 Deodar St, Ballygunge, Kolkata 700019: distances are measured from here.
export const REFERENCE_POINT = { lat: 22.5261, lng: 88.3598 };

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
// Nominatim's usage policy asks for an identifying User-Agent with a contact.
const USER_AGENT = 'find-a-flat/0.1 (+https://github.com/igorrosenberg/find-a-flat)';

// Tunables, exported so tests can make geocoding instant.
export const config = { geocodeIntervalMs: 1000, geocodeTimeoutMs: 5000 };

// Nominatim allows one request per second; queue calls within this isolate.
let nextGeocodeAt = 0;

// Returns { lat, lng } for an address, or null if it can't be found or the
// geocoder fails. Never throws: a flat is saved even without coordinates.
export async function geocode(address) {
  const now = Date.now();
  const wait = Math.max(0, nextGeocodeAt - now);
  nextGeocodeAt = now + wait + config.geocodeIntervalMs;
  if (wait) await new Promise((r) => setTimeout(r, wait));
  try {
    const url = new URL(NOMINATIM_URL);
    url.search = new URLSearchParams({ q: address, format: 'jsonv2', limit: '1', countrycodes: 'in' });
    const res = await fetch(url, {
      headers: { 'user-agent': USER_AGENT, accept: 'application/json' },
      signal: AbortSignal.timeout(config.geocodeTimeoutMs),
    });
    if (!res.ok) return null;
    const [hit] = await res.json();
    const lat = Number(hit?.lat);
    const lng = Number(hit?.lon);
    return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
  } catch {
    return null;
  }
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
