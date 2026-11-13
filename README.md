# find-a-flat

## Architecture

Find a flat runs as a single Cloudflare Worker. The same Worker serves the
Flutter web app as static assets and answers a small JSON API backed by a D1
(SQLite) database.

```mermaid
flowchart LR
  browser["Browser"]
  subgraph cf["Cloudflare"]
    worker["Worker<br/>api/src/index.js"]
    assets[("Static assets<br/>Flutter build: app/build/web")]
    d1[("D1 database<br/>table: flat")]
  end
  browser -- "GET /" --> worker
  worker -- "302 to /home" --> browser
  browser -- "GET /home and other app paths" --> assets
  browser -- "GET /api/flats" --> worker
  worker -- "SELECT ... FROM flat" --> d1
```

| Path | Handled by | What it does |
| --- | --- | --- |
| `/` | Worker | Redirects to `/home` |
| `/home` (and any other app path) | Static assets | Serves the Flutter app (`index.html` fallback), which routes itself |
| `/api/flats` | Worker | Returns the rows of the `flat` table as JSON |

### Repository layout

| Folder | Contents |
| --- | --- |
| `app/` | Flutter web app (Flutter 3.47.9) |
| `api/` | Worker code, `wrangler.toml`, D1 migrations, Node tests |
| `.github/workflows/` | `check.yml` on every pull request, `deploy.yml` on every push to `main` |

### CI/CD

```mermaid
flowchart LR
  pr["Pull request"] --> check["Check: flutter analyze and build,<br/>node tests, local D1 migrations,<br/>wrangler deploy --dry-run"]
  main["Push to main"] --> deploy["Deploy: flutter build,<br/>find or create D1, apply migrations,<br/>wrangler deploy, verify Worker secrets"]
```

Deploy needs two GitHub secrets, `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID`. The Worker secret `WRITE_PASSPHRASE` will be needed once the app can add or edit flats.
