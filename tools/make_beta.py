#!/usr/bin/env python3
"""Turns a plain (main) build into the beta build: own registry keys / folder / shortcuts, "(beta)" labels,
update channel "beta", white app icon (tools/beta_icon.b64). Version and release notes are not touched -
run tools/set_notes.py VERSION --beta --file OUT afterwards.
usage: make_beta.py IN OUT   (IN = file built by tools/build.py)"""
import os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src, out = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
assert '\r' not in s
assert 'UpdBranch := "main"' in s, 'input is not a main build (already beta?)'

def sub(old, new, count=1, regex=False):
    """replace exactly `count` occurrences, fail loudly when the source no longer matches"""
    global s
    pat = old if regex else re.escape(old)
    s, n = re.subn(pat, new if regex else new.replace('\\', '\\\\'), s, flags=re.M)
    assert n == count, f'{old!r}: {n} matches, expected {count}'

# update channel and asset cache (beta has its own icon, so its assets are versioned apart)
sub('UpdBranch := "main" ', 'UpdBranch := "beta" ')
sub(r'^AssetVersion := "(\d+)" ', r'AssetVersion := "b\1" ', regex=True)

# window title, "(beta)" under the logo, tray tip, version label
sub('Main := Gui(, "Macro Manager")', 'Main := Gui(, "Macro Manager (beta)")')
sub(r'(^Main := Gui\(, "Macro Manager \(beta\)"\)\n(?:.*\n)*?    Roles\[ttl\.Hwnd\] := "skip"\n)',
    r'\1    Main.SetFont("s10 bold cD0AE6B", "Segoe UI")\n'
    r'    btl := Main.AddText("x102 y56 w200 BackgroundTrans", "(beta)")\n'
    r'    Roles[btl.Hwnd] := "skip"\n', regex=True)
sub('A_IconTip := "Macro Manager v" AppVersion', 'A_IconTip := "Macro Manager BETA v" AppVersion')
sub('verTxt := AddHint(Main, "x740 y+4 w90 Center", "v" AppVersion)',
    'verTxt := AddHint(Main, "x726 y+4 w104 Center", "beta v" AppVersion)')

# own install: registry keys, folder, shortcuts, Apps & features entry (installs next to the stable app)
sub('"HKCU\\Software\\MacroManager"', '"HKCU\\Software\\MacroManagerBeta"', 5)
sub('Uninstall\\MacroManager"', 'Uninstall\\MacroManagerBeta"', 2)
sub('"\\MacroManager"', '"\\MacroManagerBeta"')
sub('\\Macro Manager.lnk"', '\\Macro Manager Beta.lnk"', 4)
sub('RegWrite("Macro Manager", "REG_SZ", k, "DisplayName")', 'RegWrite("Macro Manager (beta)", "REG_SZ", k, "DisplayName")')

# white icon
icon = open(os.path.join(ROOT, 'tools', 'beta_icon.b64'), encoding='utf-8').read().rstrip('\n')
s, n = re.subn(r'(^IconB64\(\) \{\n    return "\n\(Join\n)[^)]*?(\n\)")', lambda m: m.group(1) + icon + m.group(2), s, flags=re.M)
assert n == 1, f'IconB64: {n} matches'

open(out, 'w', encoding='utf-8', newline='').write(s)
print('beta build written:', out)
