// Demo durability adapter: one authority process, one owner row. This is not a
// distributed database or a shared-file multi-node coordination protocol.
import {DatabaseSync} from 'node:sqlite';
export function openStore(path) {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS owner (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL, snapshot TEXT NOT NULL)');
  const read = db.prepare('SELECT snapshot FROM owner WHERE id=1');
  const insert = db.prepare('INSERT INTO owner(id, revision, snapshot) VALUES(1, ?, ?)');
  const update = db.prepare('UPDATE owner SET revision=?, snapshot=? WHERE id=1 AND revision=?');
  return {
    load() { const row = read.get(); return row ? JSON.parse(row.snapshot) : undefined; },
    commit(snapshot, expected) {
      db.exec('BEGIN IMMEDIATE');
      try {
        if (!read.get()) { if (expected !== 0) throw new Error('missing durable revision'); insert.run(snapshot.revision, JSON.stringify(snapshot)); }
        else if (update.run(snapshot.revision, JSON.stringify(snapshot), expected).changes !== 1) throw new Error('durable revision conflict');
        db.exec('COMMIT');
      } catch (error) { db.exec('ROLLBACK'); throw error; }
    },
    close() { db.close(); }
  };
}
