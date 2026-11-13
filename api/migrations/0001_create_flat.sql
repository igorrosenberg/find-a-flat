-- One row per candidate flat. Columns follow requirements.md.
CREATE TABLE flat (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  price INTEGER,
  size_sqft INTEGER,
  bedrooms INTEGER,
  bathrooms INTEGER,
  listing_url TEXT,
  lat REAL,
  lng REAL,
  distance_m INTEGER,
  notes TEXT,
  discarded INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
