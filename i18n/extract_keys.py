"""Collects the texts to translate (_T("...") and _TL("id", "...")) from a built app file into i18n/keys.json.
usage: extract_keys.py BUILT_FILE   (a plain build: tools/build.py OUT)
Keys that already exist keep their max_chars; run add_limits.py BUILT_FILE for new buttons."""
import os, sys, re, json
I18N = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, I18N)
from ahklit import *
L = open(sys.argv[1], encoding='utf-8').read().split('\n')
KP = os.path.join(I18N, 'keys.json')
old = json.load(open(KP, encoding='utf-8')) if os.path.exists(KP) else {}
sk = skip_lines(L)
keys = {}
def add(k, en, ctx):
    if k in keys: keys[k]['ctx'].append(ctx)
    else: keys[k] = {'en': en, 'ctx': [ctx]}
for i, l in enumerate(L, 1):
    if i in sk: continue
    for a, b, body, q in lits(l):
        if q != '"': continue
        pre = l[:a]
        if re.search(r'_T\(\s*$', pre) and not re.search(r'_TL\($', pre):
            en = decode(body); add(en, en, l.strip()[:230])
        m = re.search(r'_TL\("([a-z_]+)", $', pre)
        if m: add(m.group(1), decode(body), 'HELP TOPIC TEXT (shown in the Help window, read as a manual)')
for t in ["Release notes", "Getting started", "Add / edit a macro", "Move + actions", "Sequence", "Script (.ahk)", "Keys and recording",
          "Profiles", "Toggle keys", "Order, export, backup", "Updates", "Macro Hub", "Tips and problems"]:
    add(t, t, 'Help window topic title (navigation button, ~25 characters max)')
for k, v in keys.items():
    if k in old and 'max_chars' in old[k]:
        v['max_chars'] = old[k]['max_chars']
json.dump(keys, open(KP, 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
print(len(keys), 'keys,', len([k for k in keys if k not in old]), 'new:', [k[:50] for k in keys if k not in old])
