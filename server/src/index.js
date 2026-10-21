// Macro Manager library - Cloudflare Worker + D1.
// The app sends its random install id in the X-MM-Install header; only its SHA-256 is stored.
// Answers are JSON with every non-ASCII letter as \uXXXX, so the app reads them right whatever the charset.

const PAGE = 50;
const REPORTS_TO_HIDE = 3;
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
    downloads: r.downloads, created: r.created, mine: r.mine ? 1 : 0, my: r.my || 0,
  };
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const parts = url.pathname.replace(/\/+$/, '').split('/').filter(Boolean);
    // games (tags) in use, the most used first - for the game filter and the share form
    if (parts[0] === 'v1' && parts[1] === 'games' && !parts[2] && req.method === 'GET') {
      const { results } = await env.DB.prepare(
        `SELECT MIN(game) AS game, COUNT(*) AS n FROM macros WHERE hidden <= 0 AND game <> ''
         GROUP BY LOWER(game) ORDER BY n DESC, game LIMIT 100`).all();
      return json({ games: results.map(r => ({ game: r.game, count: r.n })) });
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
    // q = words: every word must be in the name or the game tag ("4story war" = warrior macros tagged 4Story)
    if (req.method === 'GET' && !id) {
      const p = url.searchParams;
      const offset = Math.max(0, Math.min(10000, parseInt(p.get('offset') || '0', 10) || 0));
      const order = { new: 'm.id DESC', dl: 'm.downloads DESC, m.id DESC' }[p.get('sort')]
        || '(m.rating_sum + 6.0) / (m.rating_cnt + 2) DESC, m.rating_cnt DESC, m.id DESC';     // top: 2 average votes of 3 to start with
      const who = p.get('who') || 'all';
      const where = [who === 'mine' ? 'm.hidden <= 1' : 'm.hidden <= 0'], args = [voter];
      if (who === 'mine') where.push('m.owner = ?1');
      else if (who === 'others') where.push('m.owner <> ?1');
      const game = (p.get('game') || '').trim().slice(0, LIMITS.game);
      if (game) { args.push(game); where.push(`LOWER(m.game) = LOWER(?${args.length})`); }
      const words = (p.get('q') || '').trim().slice(0, 80).split(/\s+/).filter(Boolean).slice(0, 6);
      for (const w of words) {
        args.push('%' + w.replace(/[\\%_]/g, c => '\\' + c) + '%');
        where.push(`(m.name LIKE ?${args.length} ESCAPE '\\' OR m.game LIKE ?${args.length} ESCAPE '\\')`);
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
      const d = b.data;
      if (!d || typeof d !== 'object') return fail('bad_macro');
      const data = {};
      for (const [k, ok] of Object.entries(FIELDS)) {
        if (!(k in d) || !ok(d[k])) return fail('bad_macro:' + k);
        data[k] = d[k];
      }
      if (data.type === 'seq' ? !data.seq.trim() : !data.actions.trim()) return fail('bad_macro:empty');
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
        db.prepare('INSERT INTO uploads (owner, ip, created) VALUES (?1, ?2, ?3)').bind(voter, ip, now()),
        db.prepare('DELETE FROM uploads WHERE created < ?1').bind(day),
      ]);
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
      return json({ name: m.name, data: JSON.parse(m.data), counted: r.meta.changes ? 1 : 0 });
    }

    // ---- rating 1-5, one per install (can be changed), not for your own macro ----
    if (req.method === 'POST' && action === 'rate') {
      let b;
      try { b = await req.json(); } catch { return fail('bad_json'); }
      if (!int(b.stars, 1, 5)) return fail('bad_stars');
      if (m.owner === voter) return fail('own_macro', 403);
      await db.batch([
        db.prepare('INSERT INTO ratings (macro_id, voter, stars) VALUES (?1, ?2, ?3) ON CONFLICT DO UPDATE SET stars = ?3').bind(id, voter, b.stars),
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
      const r = await db.prepare('INSERT OR IGNORE INTO reports (macro_id, voter, reason, created) VALUES (?1, ?2, ?3, ?4)')
        .bind(id, voter, reason, now()).run();
      if (r.meta.changes)
        await db.prepare(`UPDATE macros SET reports = reports + 1,
                          hidden = CASE WHEN hidden = 0 AND reports + 1 >= ?2 THEN 1 ELSE hidden END WHERE id = ?1`)
          .bind(id, REPORTS_TO_HIDE).run();
      return json({ ok: 1 });
    }

    // ---- the uploader deletes their macro ----
    if (req.method === 'DELETE' && !action) {
      if (m.owner !== voter) return fail('not_owner', 403);
      await db.batch(['macros WHERE id', 'ratings WHERE macro_id', 'reports WHERE macro_id', 'downloads WHERE macro_id']
        .map(t => db.prepare(`DELETE FROM ${t} = ?1`).bind(id)));
      return json({ ok: 1 });
    }
    return fail('not_found', 404);
  },
};
