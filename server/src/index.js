// Macro Manager library - Cloudflare Worker + D1.
// The app sends its random install id in the X-MM-Install header; only its SHA-256 is stored.
// Answers are JSON with every non-ASCII letter as \uXXXX, so the app reads them right whatever the charset.

const PAGE = 50;
const REPORTS_TO_HIDE = 3;           // reports from this many different internet addresses hide a macro
const RATINGS_PER_IP = 3;            // ratings of one macro from one internet address (several players on one network)
const UPLOADS_PER_DAY = 10;          // per install
const UPLOADS_PER_DAY_IP = 30;       // per internet address
const LIMITS = { name: 40, descr: 300, author: 24, reason: 200, game: 30 };

// macro fields that can be shared (no scripts, no personal toggle key) and how each is checked
const FIELDS = {
  type: v => v === 'move' || v === 'seq',
  hotkey: v => text(v, 40),
  app: v => text(v, 80) && !/[\\/:*?"<>|]/.test(v),
  dirs: v => text(v, 200),
  actions: v => text(v, 400),
  g1: v => int(v, 0, 60000), g2: v => int(v, 0, 60000), g3: v => int(v, 0, 60000), ge: v => int(v, 0, 60000),
  seq: v => text(v, 4000),
  repeat: v => int(v, 0, 1),
  press: v => ['', 'tap', 'double', 'hold'].includes(v),
  exact: v => int(v, 0, 1),
};
function text(v, max) { return typeof v === 'string' && v.length <= max && !/[\x00-\x1f\x7f]/.test(v); }
function int(v, lo, hi) { return Number.isInteger(v) && v >= lo && v <= hi; }

function json(obj, status = 200) {
  const body = JSON.stringify(obj).replace(/[\u007f-￿]/g, c => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
  return new Response(body, { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });
}
const fail = (error, status = 400) => json({ error }, status);

async function sha(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}
const now = () => Math.floor(Date.now() / 1000);

// ---- Discord: moderation (#mod-log, secret MOD_WEBHOOK) and new macros for players (secret HUB_WEBHOOK) ----
// Moderation messages carry signed links (secret ADMIN_KEY): Verify = shown with a badge, never hidden by reports;
// Remove = gone from the hub. A link opens a page that asks first (a link preview can't do anything).

// what a macro does, in plain lines (for the messages)
function describe(d) {
  const press = { tap: 'short tap', double: 'double tap', hold: 'long press' }[d.press] || 'normal';
  const lines = [`${d.type === 'seq' ? 'Sequence' : 'Move + actions'} | key ${d.hotkey || '-'} (${press}) | ${d.repeat ? 'repeat while held' : 'once per press'}`];
  if (d.app) lines.push(`only in ${d.app}`);
  if (d.type === 'seq') lines.push(...d.seq.split('|').map(s => '  ' + s));
  else lines.push(`directions: ${d.dirs || '-'}`, `actions: ${d.actions}`, `delays: ${d.g1} / ${d.g2} / ${d.g3} / ${d.ge} ms`);
  const t = lines.join('\n');
  return t.length > 900 ? t.slice(0, 900) + '\n...' : t;
}

async function sign(env, action, id) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.ADMIN_KEY.trim()), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const s = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(action + ':' + id));
  return [...new Uint8Array(s)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function hook(url, body) {
  if (!url) return;
  try {
    await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'Macro Hub', allowed_mentions: { parse: [] }, ...body }) });
  } catch {}
}

// one message to #mod-log about a macro (m = row of macros, data = its data)
async function modLog(env, origin, m, data, title, color, extra = []) {
  if (!env.MOD_WEBHOOK) return;
  let links = '';
  if (env.ADMIN_KEY) {
    const a = async act => `${origin}/v1/admin?a=${act}&id=${m.id}&s=${await sign(env, act, m.id)}`;
    links = `\n[✅ Verify](${await a('verify')})   ·   [🗑️ Remove](${await a('remove')})`;
  }
  await hook(env.MOD_WEBHOOK, { embeds: [{ title: `${title}: ${m.name}`, color,
    description: '```\n' + describe(data).replace(/`/g, "'") + '\n```' + links,
    fields: [{ name: 'Author', value: m.author, inline: true }, { name: 'Game', value: m.game || '-', inline: true },
             { name: 'ID', value: String(m.id), inline: true }, ...extra] }] });
}

// ---- app updates through this server (GitHub's API allows 60 questions an hour per internet address) ----
// The newest commit of a branch comes from the git protocol (no API limit), kept 60 s; files are read at that
// commit, so they are never an old cached copy. The app checks the SHA-256 from version.json anyway.
const REPO = 'vavr0s/macro-manager';
async function branchHead(branch) {
  const key = new Request(`https://macro-hub.cache/head/${branch}`);
  const hit = await caches.default.match(key);
  if (hit) return hit.text();
  const r = await fetch(`https://github.com/${REPO}.git/info/refs?service=git-upload-pack`, { headers: { 'User-Agent': 'MacroManagerHub' } });
  if (!r.ok) return '';
  const m = (await r.text()).match(new RegExp(`([0-9a-f]{40}) refs/heads/${branch}\\b`));
  if (!m) return '';
  await caches.default.put(key, new Response(m[1], { headers: { 'Cache-Control': 'max-age=60' } }));
  return m[1];
}
async function repoFile(branch, file) {
  const sha = await branchHead(branch);
  if (!sha) return null;
  const r = await fetch(`https://raw.githubusercontent.com/${REPO}/${sha}/${encodeURIComponent(file)}`, { cf: { cacheTtl: 86400, cacheEverything: true } });
  return r.ok ? r : null;
}

// text of a player for the public channel: no Discord formatting, no clickable links
function plain(s) {
  return String(s).replace(/https?:\/\/\S+|www\.\S+|discord\.gg\/\S+/gi, '[link]').replace(/[\\*_~`|>\[\]()#@<:-]/g, c => '\\' + c);
}

function page(text) {
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Macro Hub</title><body style="font:16px system-ui;background:#15161a;color:#ececef;padding:24px">${text(esc)}</body>`,
    { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
}
// one-line, trimmed text; descr may keep line breaks
function clean(v, max, lines = false) {
  if (typeof v !== 'string') return '';
  v = v.replace(/\r/g, '').replace(lines ? /[\x00-\x09\x0b-\x1f\x7f]/g : /[\x00-\x1f\x7f]/g, ' ').trim();
  if (lines) v = v.replace(/\n{3,}/g, '\n\n');
  return v.length > max ? null : v;
}

function listItem(r) {
  return {
    id: r.id, name: r.name, descr: r.descr, author: r.author, game: r.game, type: r.type, hotkey: r.hotkey, hidden: r.hidden > 0 ? 1 : 0,
    rating: r.rating_cnt ? Math.round(r.rating_sum / r.rating_cnt * 100) / 100 : 0, count: r.rating_cnt,
    downloads: r.downloads, created: r.created, updated: r.updated, version: r.version, mine: r.mine ? 1 : 0, my: r.my || 0,
    verified: r.hidden === -1 ? 1 : 0,
  };
}

// the shared fields of a macro, checked: [data] or [null, error]
function macroData(d) {
  if (!d || typeof d !== 'object') return [null, 'bad_macro'];
  const data = {};
  for (const [k, ok] of Object.entries(FIELDS)) {
    if (!(k in d) || !ok(d[k])) return [null, 'bad_macro:' + k];
    data[k] = d[k];
  }
  if (data.type === 'seq' ? !data.seq.trim() : !data.actions.trim()) return [null, 'bad_macro:empty'];
  return [data];
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    const parts = url.pathname.replace(/\/+$/, '').split('/').filter(Boolean);
    const later = p => ctx.waitUntil(p);                          // Discord messages: after the answer

    // ---- app updates: /v1/app/version?branch=main|beta (version.json), /v1/app/file?branch= (Macro Manager.ahk) ----
    if (parts[0] === 'v1' && parts[1] === 'app' && req.method === 'GET' && (parts[2] === 'version' || parts[2] === 'file')) {
      const branch = url.searchParams.get('branch') === 'beta' ? 'beta' : 'main';
      const r = await repoFile(branch, parts[2] === 'version' ? 'version.json' : 'Macro Manager.ahk');
      if (!r) return fail('unavailable', 502);
      return new Response(r.body, { headers: { 'Content-Type': parts[2] === 'version' ? 'application/json; charset=utf-8' : 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store' } });
    }

    // ---- moderation links from #mod-log: GET = the question, POST (its button) = done ----
    if (parts[0] === 'v1' && parts[1] === 'admin' && !parts[2]) {
      const p = req.method === 'POST' ? new URLSearchParams(await req.text()) : url.searchParams;
      const act = p.get('a'), mid = Number(p.get('id')), sig = p.get('s') || '';
      if (!env.ADMIN_KEY || !['verify', 'remove'].includes(act) || !(mid > 0) || sig !== await sign(env, act, mid))
        return page(() => 'This link is not valid.');
      const m = await env.DB.prepare('SELECT * FROM macros WHERE id = ?1').bind(mid).first();
      if (!m) return page(() => 'This macro is no longer in Macro Hub.');
      const what = act === 'verify' ? 'Verify' : 'Remove';
      if (req.method !== 'POST')
        return page(e => `<h2>${what}: ${e(m.name)}</h2><p>by ${e(m.author)} · ${e(m.game)} · ${m.reports} report(s)</p>
<pre style="background:#1f2127;padding:12px;border-radius:8px">${e(describe(JSON.parse(m.data)))}</pre>
<form method="post"><input type="hidden" name="a" value="${act}"><input type="hidden" name="id" value="${mid}">
<input type="hidden" name="s" value="${sig}"><button style="font:16px system-ui;padding:10px 22px;border:0;border-radius:8px;
background:${act === 'verify' ? '#d0ae6b' : '#c0392b'};color:#111">${what}</button></form>`);
      await env.DB.prepare('UPDATE macros SET hidden = ?1 WHERE id = ?2').bind(act === 'verify' ? -1 : 2, mid).run();
      return page(e => `<h2>${act === 'verify' ? '✅ Verified' : '🗑️ Removed'}: ${e(m.name)}</h2>
<p>${act === 'verify' ? 'It is shown with the verified badge and is no longer hidden by reports.' : 'It is gone from Macro Hub.'}</p>`);
    }
    // games (tags) in use, the most used first - for the game filter and the share form
    if (parts[0] === 'v1' && parts[1] === 'games' && !parts[2] && req.method === 'GET') {
      const { results } = await env.DB.prepare(
        `SELECT MIN(game) AS game, COUNT(*) AS n FROM macros WHERE hidden <= 0 AND game <> ''
         GROUP BY LOWER(game) ORDER BY n DESC, game LIMIT 100`).all();
      return json({ games: results.map(r => ({ game: r.game, count: r.n })) });
    }
    // current versions of macros (the app asks for the ones it downloaded: an author may have updated them)
    if (parts[0] === 'v1' && parts[1] === 'versions' && !parts[2] && req.method === 'GET') {
      const ids = [...new Set((url.searchParams.get('ids') || '').split(',').map(Number).filter(n => Number.isInteger(n) && n > 0))].slice(0, 200);
      if (!ids.length) return json({ items: [] });
      const { results } = await env.DB.prepare(
        `SELECT id, name, author, version, updated, data FROM macros WHERE hidden <= 0 AND id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all();
      return json({ items: results.map(r => ({ id: r.id, name: r.name, author: r.author, version: r.version, updated: r.updated, data: JSON.parse(r.data) })) });
    }
    // which hub macro (and which of its versions) a macro of the app is - for copies downloaded before the app
    // remembered where they came from. Nothing of what is sent is stored.
    if (parts[0] === 'v1' && parts[1] === 'match' && !parts[2] && req.method === 'POST') {
      const inst2 = req.headers.get('X-MM-Install') || '';
      const me = /^[0-9a-f]{32}$/.test(inst2) ? await sha(inst2) : '';
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      const list = Array.isArray(b.items) ? b.items.slice(0, 100) : [];
      const found = [];
      for (let i = 0; i < list.length; i++) {
        const [data] = macroData(list[i]);
        if (!data) continue;
        const r = await env.DB.prepare(
          `SELECT v.macro_id AS id, v.version AS version, m.version AS latest, m.author AS author, m.owner = ?2 AS mine
           FROM macro_versions v JOIN macros m ON m.id = v.macro_id WHERE v.data = ?1 AND m.hidden <= 0
           ORDER BY v.version DESC, m.id LIMIT 1`).bind(JSON.stringify(data), me).first();
        if (r) found.push({ index: i, id: r.id, version: r.version, latest: r.latest, author: r.author, mine: r.mine ? 1 : 0 });
      }
      return json({ items: found });
    }
    if (parts[0] !== 'v1' || parts[1] !== 'macros')
      return fail('not_found', 404);
    const id = parts[2] ? Number(parts[2]) : 0;
    if (parts[2] && !(Number.isInteger(id) && id > 0)) return fail('not_found', 404);
    const action = parts[3] || '';

    const inst = req.headers.get('X-MM-Install') || '';
    const voter = /^[0-9a-f]{32}$/.test(inst) ? await sha(inst) : '';
    if (req.method !== 'GET' && !voter) return fail('no_install_id', 403);
    const db = env.DB;

    // ---- list ----
    // list. who = others (not mine) | mine (also those hidden after reports) | all;  game = one game tag;
    // q = words: every word must be in the name, the game tag or the author ("4story war" = warrior macros tagged 4Story)
    if (req.method === 'GET' && !id) {
      const p = url.searchParams;
      const offset = Math.max(0, Math.min(10000, parseInt(p.get('offset') || '0', 10) || 0));
      const order = { new: 'm.id DESC', dl: 'm.downloads DESC, m.id DESC' }[p.get('sort')]
        || '(m.hidden = -1) DESC, (m.rating_sum + 6.0) / (m.rating_cnt + 2) DESC, m.rating_cnt DESC, m.id DESC';     // top: verified first, then 2 average votes of 3 to start with
      const who = p.get('who') || 'all';
      const where = [who === 'mine' ? 'm.hidden <= 1' : 'm.hidden <= 0'], args = [voter];
      if (who === 'mine') where.push('m.owner = ?1');
      else if (who === 'others') where.push('m.owner <> ?1');
      const game = (p.get('game') || '').trim().slice(0, LIMITS.game);
      if (game) { args.push(game); where.push(`LOWER(m.game) = LOWER(?${args.length})`); }
      const words = (p.get('q') || '').trim().slice(0, 80).split(/\s+/).filter(Boolean).slice(0, 6);
      for (const w of words) {
        args.push('%' + w.replace(/[\\%_]/g, c => '\\' + c) + '%');
        where.push(`(m.name LIKE ?${args.length} ESCAPE '\\' OR m.game LIKE ?${args.length} ESCAPE '\\' OR m.author LIKE ?${args.length} ESCAPE '\\')`);
      }
      args.push(PAGE + 1, offset);
      const { results } = await db.prepare(
        `SELECT m.*, m.owner = ?1 AS mine, r.stars AS my FROM macros m
         LEFT JOIN ratings r ON r.macro_id = m.id AND r.voter = ?1
         WHERE ${where.join(' AND ')} ORDER BY ${order} LIMIT ?${args.length - 1} OFFSET ?${args.length}`).bind(...args).all();
      // own macros come with their data: the app matches them with its list (gold share icon)
      return json({ items: results.slice(0, PAGE).map(r => who === 'mine' ? { ...listItem(r), data: JSON.parse(r.data) } : listItem(r)),
                    more: results.length > PAGE });
    }

    // ---- upload ----
    if (req.method === 'POST' && !id) {
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      const name = clean(b.name, LIMITS.name), descr = clean(b.descr, LIMITS.descr, true), author = clean(b.author, LIMITS.author);
      let game = clean(b.game, LIMITS.game);
      if (!name || !author || !game || descr === null) return fail('bad_text');
      // the same game written the same way as in the library already ("4story" -> "4Story")
      const known = await db.prepare("SELECT game FROM macros WHERE LOWER(game) = LOWER(?1) AND hidden <= 0 GROUP BY game ORDER BY COUNT(*) DESC LIMIT 1").bind(game).first();
      if (known) game = known.game;
      const [data, bad] = macroData(b.data);
      if (bad) return fail(bad);
      // the same macro (same keys, delays and settings - the name does not count) is in the library already:
      // downloaded macros are not shared again unchanged, and nobody shares the same macro twice
      const dup = await db.prepare('SELECT id, name, author, owner FROM macros WHERE data = ?1 LIMIT 1').bind(JSON.stringify(data)).first();
      if (dup) return json({ error: 'duplicate', id: dup.id, name: dup.name, author: dup.author, mine: dup.owner === voter ? 1 : 0 }, 409);
      const ip = await sha('ip:' + (req.headers.get('CF-Connecting-IP') || ''));
      const day = now() - 86400;
      const c = await db.prepare('SELECT SUM(owner = ?1) AS o, SUM(ip = ?2) AS i FROM uploads WHERE created > ?3')
        .bind(voter, ip, day).first();
      if ((c.o || 0) >= UPLOADS_PER_DAY || (c.i || 0) >= UPLOADS_PER_DAY_IP) return fail('too_many', 429);
      const r = await db.prepare(
        'INSERT INTO macros (name, descr, author, owner, type, hotkey, data, created, game) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9) RETURNING id')
        .bind(name, descr, author, voter, data.type, data.hotkey, JSON.stringify(data), now(), game).first();
      await db.batch([
        db.prepare('INSERT INTO macro_versions (macro_id, version, data) VALUES (?1, 1, ?2)').bind(r.id, JSON.stringify(data)),
        db.prepare('INSERT INTO uploads (owner, ip, created) VALUES (?1, ?2, ?3)').bind(voter, ip, now()),
        db.prepare('DELETE FROM uploads WHERE created < ?1').bind(day),
      ]);
      const row = { id: r.id, name, author, game };
      later(modLog(env, url.origin, row, data, '🆕 New macro', 0x2FD26D, descr ? [{ name: 'Description', value: descr.slice(0, 300) }] : []));
      later(hook(env.HUB_WEBHOOK, { embeds: [{ title: `🆕 ${name.replace(/https?:\/\/\S+/gi, '[link]')}`, color: 0xD0AE6B,
        description: (descr ? plain(descr.slice(0, 300)) + '\n\n' : '') + `by **${plain(author)}** · ${plain(game)} · key ${plain(data.hotkey || '-')}`,
        footer: { text: 'Get it in Macro Manager → Macro Hub' } }] }));
      return json({ id: r.id });
    }

    // (a macro hidden after reports is still there for its author - to see it and delete it)
    const m = await db.prepare('SELECT * FROM macros WHERE id = ?1 AND (hidden <= 0 OR (hidden = 1 AND owner = ?2))').bind(id, voter).first();
    if (!m) return fail('not_found', 404);

    // ---- one macro (with its data) ----
    if (req.method === 'GET' && !action) {
      const my = voter ? await db.prepare('SELECT stars FROM ratings WHERE macro_id = ?1 AND voter = ?2').bind(id, voter).first() : null;
      return json({ ...listItem({ ...m, mine: m.owner === voter, my: my && my.stars }), data: JSON.parse(m.data) });
    }

    // ---- download: the macro data, counted once per install ----
    if (req.method === 'POST' && action === 'download') {
      const r = await db.prepare('INSERT OR IGNORE INTO downloads (macro_id, voter) VALUES (?1, ?2)').bind(id, voter).run();
      if (r.meta.changes) await db.prepare('UPDATE macros SET downloads = downloads + 1 WHERE id = ?1').bind(id).run();
      return json({ name: m.name, data: JSON.parse(m.data), version: m.version, counted: r.meta.changes ? 1 : 0 });
    }

    // ---- the author updates the macro (only what it does - name, description, game, ratings and downloads stay) ----
    if (req.method === 'PUT' && !action) {
      if (m.owner !== voter) return fail('not_owner', 403);
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      const [data, bad] = macroData(b.data);
      if (bad) return fail(bad);
      const s = JSON.stringify(data);
      if (s === m.data) return json({ id, version: m.version, updated: m.updated, unchanged: 1 });
      if (now() - m.updated < 30) return fail('too_many', 429);       // (each update is a message in #mod-log)
      const dup = await db.prepare('SELECT id, name, author, owner FROM macros WHERE data = ?1 AND id <> ?2 LIMIT 1').bind(s, id).first();
      if (dup) return json({ error: 'duplicate', id: dup.id, name: dup.name, author: dup.author, mine: dup.owner === voter ? 1 : 0 }, 409);
      const t = now();
      // a verified macro that changes is not verified any more (until checked again)
      await db.batch([
        db.prepare('UPDATE macros SET data = ?1, type = ?2, hotkey = ?3, updated = ?4, version = version + 1, hidden = CASE WHEN hidden = -1 THEN 0 ELSE hidden END WHERE id = ?5')
          .bind(s, data.type, data.hotkey, t, id),
        db.prepare('INSERT OR REPLACE INTO macro_versions (macro_id, version, data) VALUES (?1, ?2, ?3)').bind(id, m.version + 1, s),
      ]);
      later(modLog(env, url.origin, m, data, m.hidden === -1 ? '✏️ Updated (no longer verified)' : '✏️ Updated', 0x5B8DEF,
        [{ name: 'Version', value: String(m.version + 1), inline: true }]));
      return json({ id, version: m.version + 1, updated: t });
    }

    // ---- rating 1-5, one per install (can be changed), not for your own macro ----
    if (req.method === 'POST' && action === 'rate') {
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      if (!int(b.stars, 1, 5)) return fail('bad_stars');
      if (m.owner === voter) return fail('own_macro', 403);
      const ip = await sha('ip:' + (req.headers.get('CF-Connecting-IP') || ''));
      const mine = await db.prepare('SELECT 1 FROM ratings WHERE macro_id = ?1 AND voter = ?2').bind(id, voter).first();
      if (!mine) {                                                 // a new rating (changing one's own is always fine)
        const c = await db.prepare('SELECT COUNT(*) AS n FROM ratings WHERE macro_id = ?1 AND ip = ?2').bind(id, ip).first();
        if (c.n >= RATINGS_PER_IP) return fail('too_many', 429);
      }
      await db.batch([
        db.prepare('INSERT INTO ratings (macro_id, voter, stars, ip) VALUES (?1, ?2, ?3, ?4) ON CONFLICT DO UPDATE SET stars = ?3').bind(id, voter, b.stars, ip),
        db.prepare(`UPDATE macros SET rating_sum = (SELECT SUM(stars) FROM ratings WHERE macro_id = ?1),
                    rating_cnt = (SELECT COUNT(*) FROM ratings WHERE macro_id = ?1) WHERE id = ?1`).bind(id),
      ]);
      const n = await db.prepare('SELECT rating_sum, rating_cnt FROM macros WHERE id = ?1').bind(id).first();
      return json({ rating: Math.round(n.rating_sum / n.rating_cnt * 100) / 100, count: n.rating_cnt, my: b.stars });
    }

    // ---- report: hidden after REPORTS_TO_HIDE installs reported it (until the admin decides) ----
    if (req.method === 'POST' && action === 'report') {
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      const reason = clean(b.reason, LIMITS.reason);
      if (reason === null) return fail('bad_text');
      const ip = await sha('ip:' + (req.headers.get('CF-Connecting-IP') || ''));
      const r = await db.prepare('INSERT OR IGNORE INTO reports (macro_id, voter, reason, created, ip) VALUES (?1, ?2, ?3, ?4, ?5)')
        .bind(id, voter, reason, now(), ip).run();
      if (r.meta.changes) {
        // hidden only after reports from REPORTS_TO_HIDE different addresses (made-up installs on one PC don't count)
        await db.prepare(`UPDATE macros SET reports = reports + 1,
                          hidden = CASE WHEN hidden = 0 AND (SELECT COUNT(DISTINCT ip) FROM reports WHERE macro_id = ?1) >= ?2
                                   THEN 1 ELSE hidden END WHERE id = ?1`)
          .bind(id, REPORTS_TO_HIDE).run();
        const n = await db.prepare('SELECT * FROM macros WHERE id = ?1').bind(id).first();
        later(modLog(env, url.origin, n, JSON.parse(n.data), n.hidden === 1 && m.hidden !== 1 ? '🚫 Hidden after reports' : '⚠️ Reported',
          n.hidden === 1 ? 0xC0392B : 0xF2C94C, [{ name: 'Reports', value: String(n.reports), inline: true }, { name: 'Reason', value: reason || '-' }]));
      }
      return json({ ok: 1 });
    }

    // ---- the uploader deletes their macro ----
    if (req.method === 'DELETE' && !action) {
      if (m.owner !== voter) return fail('not_owner', 403);
      await db.batch(['macros WHERE id', 'ratings WHERE macro_id', 'reports WHERE macro_id', 'downloads WHERE macro_id', 'macro_versions WHERE macro_id']
        .map(t => db.prepare(`DELETE FROM ${t} = ?1`).bind(id)));
      return json({ ok: 1 });
    }
    return fail('not_found', 404);
  },
};
