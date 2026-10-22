-- reports and ratings remember the (hashed) internet address: a macro is hidden only after reports from 3 different
-- addresses, and one address can give at most 3 ratings to one macro (Macro Manager 1.22.15)
ALTER TABLE reports ADD COLUMN ip TEXT NOT NULL DEFAULT '';
ALTER TABLE ratings ADD COLUMN ip TEXT NOT NULL DEFAULT '';
