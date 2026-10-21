# Macro library server

Cloudflare Worker (`src/index.js`) + D1 database `macro-manager-library` (`schema.sql`).
Live at `https://macro-manager-library.vavr0smacromanager.workers.dev/v1/macros` (the app: `LibApi` in `src/00_startup.ahk`).

The app sends a random install id (`X-MM-Install`); only its SHA-256 is stored. Nobody can see who rated or reported.

## Deploy

Run in this folder (Node.js + `npx wrangler login` once):

```
npx wrangler deploy
npx wrangler d1 execute macro-manager-library --remote --file schema.sql     # only for a new database
```

Changes of an existing database are in `migrations/` (run each once with `--file`).

## Moderation

A macro is hidden automatically after 3 reports (`hidden = 1`). Check reported macros:

```
npx wrangler d1 execute macro-manager-library --remote --command "SELECT id, name, author, reports, hidden FROM macros WHERE reports > 0 OR hidden <> 0"
npx wrangler d1 execute macro-manager-library --remote --command "SELECT macro_id, reason, datetime(created, 'unixepoch') FROM reports ORDER BY created DESC LIMIT 50"
npx wrangler d1 execute macro-manager-library --remote --command "SELECT data FROM macros WHERE id = 12"
```

Decide (replace 12 with the id):

```
npx wrangler d1 execute macro-manager-library --remote --command "UPDATE macros SET hidden = -1 WHERE id = 12"   # OK: shown again, never hidden by reports
npx wrangler d1 execute macro-manager-library --remote --command "UPDATE macros SET hidden = 2 WHERE id = 12"    # removed (kept in the database)
```

## API (v1)

| Request | |
|---|---|
| `GET /v1/macros?who=others\|mine\|all&game=&sort=top\|new\|dl&q=&offset=` | list, 50 per page (`more` = another page exists); every word of `q` must be in the name or the game |
| `GET /v1/games` | game tags in use with their counts |
| `GET /v1/macros/:id` | one macro with its `data` |
| `POST /v1/macros` `{name, game, descr, author, data}` | share (Move + actions / Sequence only; 10 a day per install, 30 per address); the game is written like the one already in the library |
| `POST /v1/macros/:id/download` | the macro data; counted once per install |
| `POST /v1/macros/:id/rate` `{stars: 1-5}` | one rating per install (can be changed), not for your own macro |
| `POST /v1/macros/:id/report` `{reason}` | one report per install |
| `DELETE /v1/macros/:id` | only by the install that shared it |
