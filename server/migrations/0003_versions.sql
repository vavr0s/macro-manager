-- authors can update a shared macro (Macro Manager 1.22.7): when and how many times
ALTER TABLE macros ADD COLUMN updated INTEGER NOT NULL DEFAULT 0;
ALTER TABLE macros ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
