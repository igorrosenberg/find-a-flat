# api

The Cloudflare Worker for Find a flat, backed by a D1 database (binding `DB`).

- `/` redirects to `/home`.
- `/home` lists the rows of the `flat` table (empty until flats are added).

## Run locally

    npx wrangler@4 d1 migrations apply DB --local
    npx wrangler@4 dev

Then open http://localhost:8787/. Tests: `node --test "test/*.test.mjs"`.

## Deploy

The Deploy workflow runs on every push to `main`. It finds or creates the D1
database `find-a-flat`, applies the migrations, and deploys the Worker. Add two
repository secrets first (Settings, Secrets and variables, Actions):

- `CLOUDFLARE_API_TOKEN`: a token from the "Edit Cloudflare Workers" template,
  with "Account, D1, Edit" added.
- `CLOUDFLARE_ACCOUNT_ID`: shown on the Workers & Pages overview in the dashboard.
