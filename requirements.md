# Flat finder webapp: requirements

Started 2026-11-04 by Igor Rosenberg, updated on 2026-11-13 to match what is built. This file is the only copy of the requirements.

## Overview

A small private webapp to track candidate flats: list them in a table, add new ones, keep notes on each, mark rejects as discarded, and see them all on a map. It runs on Cloudflare Workers with a D1 database. Everything, reading included, needs a shared passphrase.

Out of scope for v1: user accounts, photos and file uploads, scraping listings from property sites, editing history, multi-user conflict handling, and travel time in traffic, which is planned as phase 2.

## Pages and functional requirements

Three pages, each at its own URL, sharing a top bar with links to List and Map. Add property is reached from a button on the list page and on the map page. The pages are routes of the Flutter web app; `/` redirects to `/home`.

Igor, 2026-11-13: there is no separate detail page. Viewing a property and editing it happen on the same page, the property page, which is also the add form when there is no id yet. The flow is Home > property page > Home: Save (and Delete) go back to the list.

| Page | URL | What it does |
| --- | --- | --- |
| Property list (home) | /home | Table of all properties, Add property button |
| Property page, add | /flats/new | Empty form to create a property |
| Property page, view and edit | /flats/:id | The same form filled in, plus discarded flag, distance, small map and delete |
| Map | /map | All properties as pins on one map |

### Property list (home)

1. Shows a table with columns Name, Price, Size (sq ft), B(B), Distance to Deodar Street. B(B) is bedrooms(bathrooms), e.g. "3(2)", taken from the property's Bedrooms and Bathrooms fields; an unknown number shows as a dash ("3(–)"), and a single dash when both are unknown. Sorting by B(B) orders by bedrooms, then bathrooms.
1. On a phone (narrower than 600 px), each property is a compact row: the name, then price, size, B(B) and distance on one line, e.g. "₹0.95 Cr  ·  1100 sq ft  ·  3(2)  ·  1.8 km".
2. Clicking anywhere on a row opens that property's page.
3. Discarded properties stay in the table but are shown struck through and greyed out.
4. Clicking a column header sorts by that column; default sort is newest first.
5. A toggle hides discarded properties; it is off by default. Its label names what it will do: "Hide discarded" while they are shown, "Show discarded" while they are hidden.
6. A single Add property button sits at the end of the list, below the last row, and opens the add form. It is not in the top bar.
7. Empty state: a short message and the Add property button.

### Property page (add, view and edit)

One page does all three. At /flats/new it is an empty form; at /flats/:id it loads that property into the same form, so what you see is what you edit.

1. Fields, in this order: Name (required), Price in crore, Size in sq ft, Bedrooms (optional), Bathrooms (optional), Listing URL (optional), Notes (optional), Address (required). Address is always the last field.
2. Notes is a free-text area with no character counter, capped at 10,000 characters.
3. Validation: price and size must be positive numbers, and bedrooms and bathrooms whole numbers of 0 or more; errors show next to the field, including errors the server returns.
4. One Save button saves the whole form (POST for a new property, PATCH for an existing one). Nothing is saved until Save is pressed. After a save the app goes back to the list, which reloads. When the list is the page underneath, this is the browser's Back, so the history stays Home > property page with no extra entry; from anywhere else (the map, a typed URL) the list takes the property page's place.
5. On save, the server geocodes the address to latitude and longitude and computes the distance to Deodar Street; on an existing property this happens only when the address changed.
6. If geocoding fails, the property is still saved and the distance shows as a dash; opening it again lets the user correct the address or drop a pin by hand.
7. A valid listing URL gets a button in its field that opens the ad in a new tab.

Only on an existing property:

8. Discarded: a checkbox just under the name. When ticked, the name is struck through and greyed, here and in the list. It is saved with Save.
9. Distance to Deodar Street and a small map with the property's pin, the Deodar Street marker, and + and − zoom buttons. "Move pin" (or "Drop pin by hand" when there are no coordinates) lets the user tap the map; the new pin is saved with Save and wins over the address.
10. Delete: a button next to Save, with a confirm prompt; it then goes back to the list like Save.
11. An unknown id shows "Property not found." with a button back to the list.

### Map

1. Shows every property with coordinates as a pin, plus a distinct marker for Deodar Street.
2. The map zooms to fit all pins on load.
3. Clicking a pin opens a popup with name, price, size, B(B) (e.g. "B(B) 3(2)") and an Open link to the property page.
4. Discarded properties show as grey pins, hidden when the list's hide-discarded toggle is on.
5. An Add property button floats over the bottom-left corner of the map and opens the add form.

### Passphrase

Igor, 2026-11-13: the passphrase is the access control for the whole app. Without it nobody sees anything, not even the list.

1. Every page, static file and API call needs the passphrase. Without a valid session, a page shows a login page (HTTP 401) and an API call returns HTTP 401 `{"error":"Passphrase needed"}`.
2. The login page has one password field. The right passphrase sets an HttpOnly, Secure, SameSite=Lax session cookie for a year and goes back to the page that was asked for. The browser then sends the cookie with every request, so the app itself never asks for the passphrase.
3. A wrong passphrase shows the login page again with "Wrong passphrase".
4. There is no "Forget passphrase" or log out button (Igor, 2026-11-13). Changing the secret signs every browser out, because the cookie is derived from the passphrase.
5. The passphrase is a Worker secret named `WRITE_PASSPHRASE`, set with `wrangler secret put WRITE_PASSPHRASE` or in the Cloudflare dashboard under the Worker's Settings, Variables and Secrets. It is never committed to the repo.
6. If `WRITE_PASSPHRASE` is undefined or empty, the Worker serves only an error page on every path, with no app and no API. The page returns HTTP 503 and says "Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker."
7. The check uses a constant-time comparison. After 5 wrong passphrases from one IP within 15 minutes, logins from that IP get HTTP 429 until the 15 minutes are up, even with the right passphrase. Failures are counted in the D1 table `write_failure`.
8. If a write gets 401 (the session ended, e.g. the passphrase changed), the app says "Your session has ended. Reload the page and enter the passphrase." and the form keeps what was typed.
9. In the code, `gate` in `api/src/auth.js` runs first on every request. Write endpoints also call `requireWrite(request, env)`, and the app sends writes through `sendWrite` from `app/lib/passphrase.dart`.

## Data model

One D1 table for the data, `flat` (migration `api/migrations/0001_create_flat.sql`), plus `write_failure` for rate limiting wrong passphrases on the login page (migration `0002_create_write_failure.sql`). The Deodar Street reference point is a config value, not a row: 16/1 Deodar St, Ballygunge, Kolkata 700019, at 22.5261, 88.3598.

| Column | Type | Notes |
| --- | --- | --- |
| id | INTEGER PK | Auto-increment |
| name | TEXT, required | Display name, e.g. "2-bed near park" |
| address | TEXT, required | Free text, used for geocoding |
| price | INTEGER | Purchase price in whole rupees, around 1,00,00,000 |
| size_sqft | INTEGER | Square feet |
| bedrooms | INTEGER, optional | Whole number, 0 or more; null if not given |
| bathrooms | INTEGER, optional | Whole number, 0 or more; null if not given |
| listing_url | TEXT | Optional link to the original ad |
| lat, lng | REAL | From geocoding or a manual pin; null if unknown |
| distance_m | INTEGER | Computed and stored in metres, shown in the chosen unit |
| notes | TEXT | Text area on the property page |
| discarded | INTEGER 0/1 | Default 0 |
| created_at, updated_at | TEXT | ISO 8601 timestamps |

Distance is recomputed whenever the address, the pin or the reference point changes.

## Architecture and non-functional requirements

A single Cloudflare Worker serves the Flutter web app as static assets and a small JSON API, backed by one D1 database. See the README for the diagram.

- **Frontend:** Flutter web app in `app/`, built with `flutter build web` and served from `app/build/web` by the Worker's static assets. Unknown paths fall back to `index.html` so Flutter does its own routing.
- **API:** `GET/POST /api/flats`, `GET/PATCH/DELETE /api/flats/:id`. The Worker runs first on every path, so it can check the session and serve the login or error page.
- **Map:** OpenStreetMap tiles drawn with the `flutter_map` package. Free, no API key.
- **Geocoding:** called from the Worker on save, never from the browser, so any key stays secret. OpenStreetMap Nominatim first (free, 1 request per second, needs an identifying User-Agent, which names only the app and its repository), then Photon (komoot, also OSM data, fuzzier) if Nominatim refuses or finds nothing. Messy addresses are cleaned (ward and P.S. labels, Old/New markers, landmarks and PIN codes dropped) and retried with progressively simpler queries, from street + locality down to the locality alone; a match more than 80 km from Deodar Street is ignored. Mapbox or Google are drop-in alternatives if accuracy is still poor.
- **Distance:** straight-line (haversine) from the property to the Deodar Street reference point, stored in metres.
- **Access:** everything behind one shared passphrase (see Passphrase), no user accounts.
- **Deploy:** the Check workflow runs on every pull request; the Deploy workflow builds the app, applies D1 migrations and runs `wrangler deploy` on every push to `main`. Fits in the Workers and D1 free tiers.
- **Devices:** usable on a phone; below 600 px wide the list shows compact rows instead of the table, and the table scrolls horizontally if it is still too wide.

## Defaults assumed

These are filled in so building can start; each one maps to a question below.

| Topic | Default |
| --- | --- |
| Distance meaning | Straight-line distance to 16/1 Deodar St, Ballygunge, Kolkata (22.5261, 88.3598) |
| Distance unit | Kilometres, one decimal (stored in metres) |
| Price | Purchase price in rupees, stored as whole rupees, always shown in crore with two decimals, never lakh (e.g. ₹1.05 Cr, ₹0.95 Cr) |
| Size unit | Square feet, as asked |
| Map provider | OpenStreetMap via flutter_map |
| Geocoder | Nominatim, then Photon, with manual pin as fallback |
| Discarded rows | Shown struck through in list, not hidden |
| Access | The whole app needs the WRITE_PASSPHRASE secret, entered once per browser on a login page; if it is unset the Worker serves only an error page |

## Open questions for Igor

The reference point is confirmed. None of the rest blocks a first version, and each can change after v1 ships.

- [x] Reference point: confirmed as 16/1 Deodar St, Ballygunge, Kolkata 700019 (22.5261, 88.3598).
- [ ] Phase 2 adds driving time in traffic to Deodar St. Which departure time and direction (e.g. weekday 9:00, flat to Deodar St)? It needs a routing API with live traffic, such as Google Routes, which needs an API key and is billed per request after a free allowance.
- [x] Kilometres confirmed for v1.
- [x] Price confirmed as purchase price in rupees, around ₹1 crore.
- [ ] Should discarded properties be shown struck through, hidden by default, or sorted to the bottom?
- [x] Access confirmed: a shared passphrase stored as a Cloudflare secret guards the whole app, reads included (changed 2026-11-13).
- [x] Extra fields confirmed: optional bedrooms and bathrooms. Any status beyond discarded worth adding later (e.g. viewing booked)?
- [x] Code is in github.com/igorrosenberg/find-a-flat and deploys to Cloudflare from GitHub Actions.
