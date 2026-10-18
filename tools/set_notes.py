#!/usr/bin/env python3
"""Writes the release notes from tools/notes.json and the version into a built app file and version.json.
usage: set_notes.py VERSION [--beta] [--file "Macro Manager.ahk"] [--src]
  --beta  adds the BETA line on top (all languages)
  --src   also writes them into src/00_startup.ahk (do this for releases on main)
version.json gets "notes" (English) plus notes_cs / notes_pl / notes_de; accented letters are stored as \\uXXXX
so the app reads them right whatever character set the download is decoded with."""
import json, re, sys, os, hashlib
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
ver = args[0]
beta = '--beta' in args
f = os.path.join(ROOT, args[args.index('--file') + 1]) if '--file' in args else os.path.join(ROOT, 'Macro Manager.ahk')
notes = json.load(open(os.path.join(ROOT, 'tools', 'notes.json'), encoding='utf-8'))
LANGS = ['en', 'cs', 'pl', 'de']
BETA = {'en': 'BETA build - for testing.', 'cs': 'BETA verze – k testování.', 'pl': 'Wersja BETA – do testów.',
        'de': 'BETA-Version – zum Testen.'}
text = {}
for l in LANGS:
    lines = notes[l]
    assert len(lines) == len(notes['en']), f'{l}: {len(lines)} lines, English has {len(notes["en"])}'
    for ln in lines:
        assert '"' not in ln and '`' not in ln, f'{l}: no double quotes / backticks: {ln}'
    text[l] = ([BETA[l]] if beta else []) + ['- ' + ln for ln in lines]

def ahk(l): return '`n'.join(text[l])
def patch(path):
    s = open(path, encoding='utf-8').read()
    s, a = re.subn(r'^AppVersion := "[^"]*"', f'AppVersion := "{ver}"', s, count=1, flags=re.M)
    s, b = re.subn(r'^ReleaseNotes := "[^"\n]*"', lambda m: f'ReleaseNotes := "{ahk("en")}"', s, count=1, flags=re.M)
    others = ', '.join(f'"{l}", "{ahk(l)}"' for l in LANGS[1:])
    s, c = re.subn(r'^ReleaseNotesL := [^\n]*', lambda m: f'ReleaseNotesL := Map({others})', s, count=1, flags=re.M)
    assert a == b == c == 1, (path, a, b, c)
    open(path, 'w', encoding='utf-8', newline='').write(s)
patch(f)
if '--src' in args:
    patch(os.path.join(ROOT, 'src', '00_startup.ahk'))
vj = os.path.join(ROOT, 'version.json')
j = json.load(open(vj, encoding='utf-8'))
j['version'] = ver
j['sha256'] = hashlib.sha256(open(f, 'rb').read()).hexdigest()
j['notes'] = '\n'.join(text['en'])
for l in LANGS[1:]:
    j['notes_' + l] = '\n'.join(text[l])
open(vj, 'w', encoding='utf-8', newline='').write(json.dumps(j, indent=2, ensure_ascii=True) + '\n')
print('notes written for', ver, 'beta' if beta else 'release', '->', os.path.basename(f), j['sha256'][:12])
