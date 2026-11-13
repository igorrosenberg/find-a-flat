# Flat finder webapp: requirements

Started 2026-11-04 by Igor Rosenberg, updated on 2026-11-13 to match what is built. This file is the only copy of the requirements.

## Overview

A small public webapp to track candidate flats: list them in a table, add new ones, keep notes on each, mark rejects as discarded, and see them all on a map. It runs on Cloudflare Workers with a D1 database. Anyone can read it; writes need a shared passphrase.

Out of scope for v1: user accounts, photos and file uploads, scraping listings from property sites, editing history, multi-user conflict handling, and travel time in traffic, which is planned as phase 2.

## Pages and functional requirements

Four pages, each at its own URL, sharing a top bar with links to List, Map and Add property. The pages are routes of the Flutter web app; `/` redirects to `/home`. As of 2026-11-13 only the list page exists, showing the rows from `GET /api/flats`.

| Page | URL | What it does |
| --- | --- | --- |
| Property list (home) | /home | Table of all properties, Add property button |
| Add property | /flats/new | Form to create a property |
| Property detail | /flats/:id | All fields, notes, discarded flag, edit and delete |
| Map | /map | All properties as pins on one map |

### Property list (home)

1. Shows a table with columns Name, Price, Size (sq ft), Distance to Deodar Street.
2. Clicking anywhere on a row opens that property's detail page.
3. Discarded properties stay in the table but are shown struck through and greyed out.
4. Clicking a column header sorts by that column; default sort is newest first.
5. A toggle hides discarded properties; it is off by default.
6. An Add property button sits above the table and opens the add form.
7. Empty state: a short message and the Add property button.

### Add property

1. Fields: Name (required), Address (required), Price, Size in sq ft, Bedrooms (optional), Bathrooms (optional), Listing URL (optional).
2. On save, the server geocodes the address to latitude and longitude and computes the distance to Deodar Street.
3. If geocoding fails, the property is still saved, distance shows as a dash, and the detail page lets the user correct the address or drop a pin by hand.
4. After save, the browser goes to the new property's detail page.
5. Validation: price and size must be positive numbers, and bedrooms and bathrooms whole numbers of 0 or more; errors show next to the field.

### Property detail

1. Shows every field from the add form, plus the computed distance and a small map with the property's pin.
2. Notes: a free-text area, saved with a Save button (or on blur), no length limit beyond a sane cap of 10,000 characters.
3. Discarded: a checkbox. When ticked, the property name on this page and in the list is struck through.
4. Edit: the same fields as the add form can be changed; changing the address re-runs geocoding and distance.
5. Delete: a button with a confirm prompt.

### Map

1. Shows every property with coordinates as a pin, plus a distinct marker for Deodar Street.
2. The map zooms to fit all pins on load.
3. Clicking a pin opens a popup with name, price, size and a link to the detail page.
4. Discarded properties show as grey pins, hidden when the list's hide-discarded toggle is on.

### Write passphrase

1. Reads stay public: every page and every GET on the API works without a passphrase.
2. Every write needs the passphrase: add, edit, saving notes, ticking discarded, and delete. The Worker checks it on the server.
3. The passphrase is a Worker secret named `WRITE_PASSPHRASE`, set with `wrangler secret put WRITE_PASSPHRASE` or in the Cloudflare dashboard under the Worker's Settings, Variables and Secrets. It is never committed to the repo.
4. If `WRITE_PASSPHRASE` is undefined or empty, all writes are blocked with HTTP 503 and the message "Writes are disabled until a passphrase is set. Set the WRITE_PASSPHRASE secret on this Worker." Every page shows that message as a banner, and the Add, Save and Delete buttons are disabled.
5. A missing or wrong passphrase returns HTTP 401 "Wrong passphrase", and the form keeps what was typed.
6. The first write asks for the passphrase. The browser remembers it until "Forget passphrase" in the top bar is clicked, and sends it in an `X-Passphrase` header over HTTPS.
7. The check uses a constant-time comparison, and failed attempts are rate limited.

## Data model

One D1 table, `flat` (migration `api/migrations/0001_create_flat.sql`). The Deodar Street reference point is a config value, not a row: 16/1 Deodar St, Ballygunge, Kolkata 700019, at 22.5261, 88.3598.

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
| notes | TEXT | Detail-page text area |
| discarded | INTEGER 0/1 | Default 0 |
| created_at, updated_at | TEXT | ISO 8601 timestamps |

Distance is recomputed whenever the address, the pin or the reference point changes.

## Architecture and non-functional requirements

A single Cloudflare Worker serves the Flutter web app as static assets and a small JSON API, backed by one D1 database. See the README for the diagram.

- **Frontend:** Flutter web app in `app/`, built with `flutter build web` and served from `app/build/web` by the Worker's static assets. Unknown paths fall back to `index.html` so Flutter does its own routing.
- **API:** `GET/POST /api/flats`, `GET/PATCH/DELETE /api/flats/:id`. `GET /api/flats` and `POST /api/flats` exist so far. The Worker runs first for `/` and `/api/*`.
- **Map:** OpenStreetMap tiles drawn with the `flutter_map` package. Free, no API key.
- **Geocoding:** called from the Worker on save, never from the browser, so any key stays secret. Default is OpenStreetMap Nominatim (free, 1 request per second, needs a contact User-Agent); Mapbox or Google are drop-in alternatives if accuracy is poor.
- **Distance:** straight-line (haversine) from the property to the Deodar Street reference point, stored in metres.
- **Access:** public reads, passphrase-protected writes (see Write passphrase), no user accounts.
- **Deploy:** the Check workflow runs on every pull request; the Deploy workflow builds the app, applies D1 migrations and runs `wrangler deploy` on every push to `main`. Fits in the Workers and D1 free tiers.
- **Devices:** usable on a phone; the table scrolls horizontally on narrow screens.

## Defaults assumed

These are filled in so building can start; each one maps to a question below.

| Topic | Default |
| --- | --- |
| Distance meaning | Straight-line distance to 16/1 Deodar St, Ballygunge, Kolkata (22.5261, 88.3598) |
| Distance unit | Kilometres, one decimal (stored in metres) |
| Price | Purchase price in rupees, stored as whole rupees, always shown in crore with two decimals, never lakh (e.g. ₹1.05 Cr, ₹0.95 Cr) |
| Size unit | Square feet, as asked |
| Map provider | OpenStreetMap via flutter_map |
| Geocoder | Nominatim, with manual pin as fallback |
| Discarded rows | Shown struck through in list, not hidden |
| Write access | Reads public; writes need the WRITE_PASSPHRASE secret, blocked if it is unset |

## Open questions for Igor

The reference point is confirmed. None of the rest blocks a first version, and each can change after v1 ships.

- [x] Reference point: confirmed as 16/1 Deodar St, Ballygunge, Kolkata 700019 (22.5261, 88.3598).
- [ ] Phase 2 adds driving time in traffic to Deodar St. Which departure time and direction (e.g. weekday 9:00, flat to Deodar St)? It needs a routing API with live traffic, such as Google Routes, which needs an API key and is billed per request after a free allowance.
- [x] Kilometres confirmed for v1.
- [x] Price confirmed as purchase price in rupees, around ₹1 crore.
- [ ] Should discarded properties be shown struck through, hidden by default, or sorted to the bottom?
- [x] Write access confirmed: a shared passphrase stored as a Cloudflare secret, reads stay public.
- [x] Extra fields confirmed: optional bedrooms and bathrooms. Any status beyond discarded worth adding later (e.g. viewing booked)?
- [x] Code is in github.com/igorrosenberg/find-a-flat and deploys to Cloudflare from GitHub Actions.
