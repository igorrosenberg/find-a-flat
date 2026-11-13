# api

The Cloudflare Worker for Find a flat, backed by a D1 database (binding `DB`).
It also serves the Flutter web build from `../app/build/web`.

- `/` redirects to `/home`.
- `/home` is the Flutter app, which lists the rows of the `flat` table.
- `/api/flats` returns those rows as JSON.

## Run locally

    (cd ../app && flutter build web --release)
    npx wrangler@4 d1 migrations apply DB --local
    npx wrangler@4 dev

Then open http://localhost:8787/. Tests: `node --test "test/*.test.mjs"`.

## Deploy

The Deploy workflow runs on every push to `main`. It builds the Flutter app,
finds or creates the D1 database `find-a-flat`, applies the migrations, deploys
the Worker, then fails if the `WRITE_PASSPHRASE` Worker secret is missing.
Add two repository secrets first (Settings, Secrets and variables, Actions):

- `CLOUDFLARE_API_TOKEN`: a token from the "Edit Cloudflare Workers" template,
  with "Account, D1, Edit" added.
- `CLOUDFLARE_ACCOUNT_ID`: shown on the Workers & Pages overview in the dashboard.
