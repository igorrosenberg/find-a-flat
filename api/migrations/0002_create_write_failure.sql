-- Failed write-passphrase attempts per client IP, for rate limiting.
CREATE TABLE write_failure (
  ip TEXT PRIMARY KEY,
  failures INTEGER NOT NULL,
  window_start INTEGER NOT NULL -- Unix seconds
);
