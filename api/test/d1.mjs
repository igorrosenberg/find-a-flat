// A tiny D1 stand-in over node:sqlite, with the real migrations applied.
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';

export function memoryD1() {
  const db = new DatabaseSync(':memory:');
  const dir = new URL('../migrations/', import.meta.url);
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    db.exec(readFileSync(new URL(f, dir), 'utf8'));
  }
  const plain = (row) => (row ? { ...row } : null);
  const statement = (sql, args = []) => ({
    bind: (...a) => statement(sql, a),
    first: async () => plain(db.prepare(sql).get(...args)),
    all: async () => ({ results: db.prepare(sql).all(...args).map(plain) }),
    run: async () => {
      const r = db.prepare(sql).run(...args);
      return { meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
    },
  });
  return { prepare: (sql) => statement(sql), raw: db };
}
