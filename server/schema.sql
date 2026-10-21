-- Macro library (Cloudflare D1). Who uploaded / rated / reported is stored only as a SHA-256 of the app's
-- random install id - never shown to anyone.
CREATE TABLE IF NOT EXISTS macros (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL,
  descr      TEXT    NOT NULL DEFAULT '',
  author     TEXT    NOT NULL,
  owner      TEXT    NOT NULL,            -- hash of the uploader's install id (may delete the macro)
  type       TEXT    NOT NULL,            -- move | seq
  hotkey     TEXT    NOT NULL DEFAULT '',
  data       TEXT    NOT NULL,            -- JSON of the macro fields
  created    INTEGER NOT NULL,            -- unix seconds
  rating_sum INTEGER NOT NULL DEFAULT 0,
  rating_cnt INTEGER NOT NULL DEFAULT 0,
  downloads  INTEGER NOT NULL DEFAULT 0,
  reports    INTEGER NOT NULL DEFAULT 0,
  hidden     INTEGER NOT NULL DEFAULT 0,  -- 1 = hidden after reports, 2 = removed by the admin, -1 = approved (no auto-hide)
  game       TEXT    NOT NULL DEFAULT '', -- game tag (filter and search)
  updated    INTEGER NOT NULL DEFAULT 0,  -- unix seconds of the author's last update (0 = never)
  version    INTEGER NOT NULL DEFAULT 1   -- +1 with every update (apps compare it with what they downloaded)
);
-- databases made before these columns: migrations/0002_game.sql, 0003_versions.sql
CREATE INDEX IF NOT EXISTS macros_owner ON macros(owner);
CREATE TABLE IF NOT EXISTS ratings   (macro_id INTEGER NOT NULL, voter TEXT NOT NULL, stars INTEGER NOT NULL, PRIMARY KEY (macro_id, voter));
CREATE TABLE IF NOT EXISTS reports   (macro_id INTEGER NOT NULL, voter TEXT NOT NULL, reason TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY (macro_id, voter));
CREATE TABLE IF NOT EXISTS downloads (macro_id INTEGER NOT NULL, voter TEXT NOT NULL, PRIMARY KEY (macro_id, voter));
CREATE TABLE IF NOT EXISTS uploads   (owner TEXT NOT NULL, ip TEXT NOT NULL, created INTEGER NOT NULL);
