// Geocoding (OpenStreetMap Nominatim, called from the Worker only) and the
// straight-line distance to the Deodar Street reference point.

export const DEODAR_STREET = { lat: 22.5261, lng: 88.3598 };

const NOMINATIM = 'https://nominatim.openstreetmap.org/search';
const USER_AGENT = 'find-a-flat (https://github.com/igorrosenberg/find-a-flat)';

/** Returns {lat, lng} for an address, or null when it can't be found. */
export async function geocode(address, fetchImpl = fetch) {
  const url = new URL(NOMINATIM);
  url.searchParams.set('q', address);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('limit', '1');
  url.searchParams.set('countrycodes', 'in');
  try {
    const res = await fetchImpl(url.toString(), {
      headers: { 'user-agent': USER_AGENT, accept: 'application/json' },
      signal: AbortSignal.timeout(8000),
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

/** Haversine distance in whole metres from (lat, lng) to Deodar Street. */
export function distanceToDeodarM(lat, lng) {
  const r = 6371008.8;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(DEODAR_STREET.lat - lat);
  const dLng = rad(DEODAR_STREET.lng - lng);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat)) * Math.cos(rad(DEODAR_STREET.lat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * r * Math.asin(Math.sqrt(a)));
}
