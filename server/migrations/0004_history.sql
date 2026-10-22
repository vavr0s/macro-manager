-- every version of every macro (Macro Manager 1.22.8): apps link macros downloaded before they remembered where
-- from by matching their data with any version
CREATE TABLE IF NOT EXISTS macro_versions (macro_id INTEGER NOT NULL, version INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (macro_id, version));
CREATE INDEX IF NOT EXISTS macro_versions_data ON macro_versions(data);
INSERT OR IGNORE INTO macro_versions (macro_id, version, data) SELECT id, version, data FROM macros;
-- Dodge (id 2) was updated before the history existed: its version 1, taken from a copy downloaded then
INSERT OR IGNORE INTO macro_versions (macro_id, version, data) SELECT 2, 1, '{"type":"seq","hotkey":"x","app":"TClient.exe","dirs":"D","actions":"X","g1":25,"g2":20,"g3":20,"ge":21,"seq":"down d 5|tap x 10|up d 55","repeat":1,"press":"","exact":1}' WHERE EXISTS (SELECT 1 FROM macros WHERE id = 2 AND version = 2);
