#!/usr/bin/env python3
"""Keeps the ComboCrown Discord server up to date through the bot (Discord REST API, standard library only).

    py update_discord.py            shows what would change (nothing is sent)
    py update_discord.py --apply    does it

What it does:
  - renames the server, channels, roles and webhooks that still carry the old name (Macro Manager -> ComboCrown)
    and gives the webhooks the crown icon (icon.png next to this script)
  - rewrites the bot's own messages in the channels from texts.md, in place (reactions, ✅ verification and the
    Ticket Tool panel stay); a missing message is posted; the old installer attached in #download is removed
The bot token comes from %APPDATA%\\ComboCrownDiscord\\token.txt (save_token.py) - never from the repository."""
import base64, json, os, re, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = 'https://discord.com/api/v10'
APPLY = '--apply' in sys.argv
OLD, NEW = 'Macro Manager', 'ComboCrown'
NO_ATTACH = {'download'}          # channels whose bot message must not keep old attachments

tok_file = os.path.join(os.environ.get('APPDATA', ''), 'ComboCrownDiscord', 'token.txt')
if not os.path.exists(tok_file):
    raise SystemExit('no token - run save_token.py first')
TOKEN = open(tok_file, encoding='utf-8').read().strip()


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    while True:
        req = urllib.request.Request(API + path, data=data, method=method, headers={
            'Authorization': 'Bot ' + TOKEN, 'Content-Type': 'application/json',
            'User-Agent': 'ComboCrownDiscord (https://combocrown.pages.dev, 1.0)'})
        try:
            with urllib.request.urlopen(req) as r:
                t = r.read()
                return json.loads(t) if t else None
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(float(json.loads(e.read()).get('retry_after', 1)) + 0.2)
                continue
            raise SystemExit(f'{method} {path}: HTTP {e.code} {e.read().decode(errors="replace")[:300]}')


def change(what, method, path, body):
    print(('  DO   ' if APPLY else '  WOULD ') + what)
    if APPLY:
        return call(method, path, body)


def renamed(s):
    return s.replace(OLD, NEW).replace('macro-manager', 'combocrown').replace('Macro-Manager', 'ComboCrown') \
        .replace('MacroManager', 'ComboCrown').replace('macromanager', 'combocrown') \
        .replace('Vavr0s', 'vavr0s').replace('VAVR0S', 'vavr0s')          # the brand is always written vavr0s


def parse_texts(path):
    out, cur = {}, None
    for line in open(path, encoding='utf-8').read().split('\n'):
        if line.startswith('## '):
            cur = line[3:].strip()
            out[cur] = ['']
        elif cur is None:
            continue
        elif line.strip() == '---':
            out[cur].append('')
        else:
            out[cur][-1] += line + '\n'
    return {k: [m.strip() for m in v if m.strip()] for k, v in out.items()}


me = call('GET', '/users/@me')
guilds = call('GET', '/users/@me/guilds')
if len(guilds) != 1:
    raise SystemExit('the bot is in %d servers, expected 1: %s' % (len(guilds), [g['name'] for g in guilds]))
gid = guilds[0]['id']
guild = call('GET', f'/guilds/{gid}')
print(f'bot {me["username"]} on server "{guild["name"]}"' + ('' if APPLY else '   (preview - nothing is sent)'))

# ---- names
print('\nnames:')
if renamed(guild['name']) != guild['name']:
    change(f'server: "{guild["name"]}" -> "{renamed(guild["name"])}"', 'PATCH', f'/guilds/{gid}', {'name': renamed(guild['name'])})
desc = guild.get('description') or ''
if renamed(desc) != desc:
    change('server description: ' + renamed(desc), 'PATCH', f'/guilds/{gid}', {'description': renamed(desc)})
channels = call('GET', f'/guilds/{gid}/channels')
for c in channels:
    upd = {}
    if renamed(c['name']) != c['name']:
        upd['name'] = renamed(c['name'])
    if c.get('topic') and renamed(c['topic']) != c['topic']:
        upd['topic'] = renamed(c['topic'])
    if upd:
        change(f'channel #{c["name"]}: {upd}', 'PATCH', f'/channels/{c["id"]}', upd)
        c.update(upd)
for r in call('GET', f'/guilds/{gid}/roles'):
    if renamed(r['name']) != r['name'] and r.get('managed'):
        print(f'  --   role "{r["name"]}" belongs to a bot/integration - rename it in Server settings > Roles')
    elif renamed(r['name']) != r['name']:
        change(f'role "{r["name"]}" -> "{renamed(r["name"])}"', 'PATCH', f'/guilds/{gid}/roles/{r["id"]}', {'name': renamed(r['name'])})
icon = os.path.join(HERE, 'icon.png')
avatar = 'data:image/png;base64,' + base64.b64encode(open(icon, 'rb').read()).decode() if os.path.exists(icon) else None
for w in call('GET', f'/guilds/{gid}/webhooks'):
    if w.get('type') != 1:
        continue
    if renamed(w['name']) != w['name']:
        body = {'name': renamed(w['name'])}
        if avatar and 'Beta' not in w['name']:          # the beta webhook keeps its white icon
            body['avatar'] = avatar
        change(f'webhook "{w["name"]}" -> "{body["name"]}"' + (' + crown icon' if 'avatar' in body else ''),
               'PATCH', f'/webhooks/{w["id"]}', body)

# ---- texts
print('\ntexts:')
byname = {c['name']: c for c in channels}
texts = parse_texts(os.path.join(HERE, 'texts.md'))


def links(s):
    return re.sub(r'<#([a-z0-9-]+)>', lambda m: f'<#{byname[m.group(1)]["id"]}>' if m.group(1) in byname else m.group(0), s)


for name, msgs in texts.items():
    ch = byname.get(name) or byname.get(renamed(name))
    if not ch:
        print(f'  ?? no channel #{name}, skipped')
        continue
    if ch.get('type') == 15:                                 # forum: the text is the first message of the bot's own post
        posts = [t for t in call('GET', f'/guilds/{gid}/threads/active')['threads']
                 if t.get('parent_id') == ch['id'] and t.get('owner_id') == me['id']]
        posts += [t for t in call('GET', f'/channels/{ch["id"]}/threads/archived/public?limit=50')['threads']
                  if t.get('owner_id') == me['id']]
        if not posts:
            print(f'  ?? #{name} is a forum without a post of the bot, skipped')
            continue
        post = min(posts, key=lambda t: int(t['id']))
        first = call('GET', f'/channels/{post["id"]}/messages/{post["id"]}')
        text = links(msgs[0])
        if first['content'] != text:
            change(f'#{name} post "{post["name"]}": text', 'PATCH', f'/channels/{post["id"]}/messages/{post["id"]}', {'content': text})
        else:
            print(f'  ok   #{name} post unchanged')
        continue
    mine = [m for m in call('GET', f'/channels/{ch["id"]}/messages?limit=50') if m['author']['id'] == me['id']]
    mine.sort(key=lambda m: int(m['id']))
    for i, text in enumerate(msgs):
        text = links(text)
        assert len(text) <= 2000, f'#{name} message {i + 1}: {len(text)} characters'
        if i < len(mine):
            old = mine[i]
            body = {}
            if old['content'] != text:
                body['content'] = text
            if name in NO_ATTACH and old.get('attachments'):
                body['attachments'] = []
            if body:
                what = 'text' if 'content' in body else ''
                if 'attachments' in body:
                    what += (' + ' if what else '') + 'remove ' + ', '.join(a['filename'] for a in old['attachments'])
                change(f'#{name} message {i + 1}: {what}', 'PATCH', f'/channels/{ch["id"]}/messages/{old["id"]}', body)
            else:
                print(f'  ok   #{name} message {i + 1} unchanged')
        else:
            change(f'#{name}: new message {i + 1}', 'POST', f'/channels/{ch["id"]}/messages', {'content': text})
    if len(mine) > len(msgs):
        print(f'  !!   #{name}: {len(mine) - len(msgs)} more bot message(s) left as they are')
print('\ndone' if APPLY else '\npreview only - run with --apply to do it')
