#!/usr/bin/env python3
"""Builds the setup packages from a built app file: <Name>.zip (folder with the script, runtime, .bat, README)
and, with --ahk2exe, also <Name>.exe (one-file installer, 64-bit only, compiled by Ahk2Exe on Windows).
usage: package.py APPFILE --runtime DIR --out DIR [--ahk2exe PATH\\Ahk2Exe.exe]
  APPFILE   built "Macro Manager.ahk" (main or beta - the beta build is detected by UpdBranch "beta")
  --runtime folder with runtime64\\ and runtime32\\ (renamed AutoHotkey64/32 "Macro Manager Setup.exe" + licence);
            not in the repo - take them from the last setup zip
  --out     where MacroManager[-Beta]-Setup.zip / .exe are written"""
import base64, os, re, shutil, subprocess, sys, tempfile, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETUP = os.path.join(ROOT, 'tools', 'setup')
args = sys.argv[1:]
def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default
app, runtime, out, ahk2exe = args[0], opt('--runtime'), opt('--out'), opt('--ahk2exe')
assert runtime and out, __doc__

src = open(app, encoding='utf-8').read()
beta = 'UpdBranch := "beta"' in src
assert beta or 'UpdBranch := "main"' in src, 'not a Macro Manager build'
ver = re.search(r'^AppVersion := "([^"]+)"', src, re.M).group(1)
name = 'MacroManager-Beta-Setup' if beta else 'MacroManager-Setup'
bat = 'Install Macro Manager Beta.bat' if beta else 'Install Macro Manager.bat'
for rt in ('runtime64', 'runtime32'):
    for f in ('Macro Manager Setup.exe', 'AutoHotkey-license.txt'):
        assert os.path.isfile(os.path.join(runtime, rt, f)), f'missing {rt}\\{f} in {runtime}'

readme = open(os.path.join(SETUP, 'README.txt'), encoding='utf-8', newline='').read()
if beta:
    readme = readme.replace('"Install Macro Manager.bat"', f'"{bat}"')
    readme += ('\r\nBETA build: installs separately from the normal Macro Manager (own folder, own shortcuts)'
               ' and updates itself from the test channel.\r\n')

os.makedirs(out, exist_ok=True)
work = tempfile.mkdtemp(prefix='mm-package-')
try:
    pkg = os.path.join(work, name)
    os.makedirs(pkg)
    shutil.copyfile(app, os.path.join(pkg, 'Macro Manager.ahk'))
    shutil.copyfile(os.path.join(SETUP, 'Install.bat'), os.path.join(pkg, bat))
    open(os.path.join(pkg, 'README.txt'), 'w', encoding='utf-8', newline='').write(readme)
    for rt in ('runtime64', 'runtime32'):
        shutil.copytree(os.path.join(runtime, rt), os.path.join(pkg, rt))

    zpath = os.path.join(out, name + '.zip')
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for dp, _, files in os.walk(pkg):
            for f in sorted(files):
                full = os.path.join(dp, f)
                z.write(full, os.path.relpath(full, work).replace(os.sep, '/'))
    print('zip:', zpath, ver)

    if ahk2exe:
        # the stub FileInstalls from .\pkg, so it is compiled next to a copy of the package
        stage = os.path.join(work, 'exe')
        shutil.copytree(pkg, os.path.join(stage, 'pkg'))
        icon = re.search(r'^IconB64\(\) \{\n    return "\n\(Join\n([^)]*?)\n\)"', src, re.M).group(1)
        open(os.path.join(stage, 'app.ico'), 'wb').write(base64.b64decode(icon.replace('\n', '')))
        title = 'Macro Manager Beta Setup' if beta else 'Macro Manager Setup'
        nver = '.'.join((re.findall(r'\d+', ver) + ['0'] * 4)[:4])
        stub = open(os.path.join(SETUP, 'installer_stub.ahk'), encoding='utf-8').read()
        stub = stub.replace('{NAME}', title).replace('{VERSION}', nver).replace('{EXE}', name + '.exe')
        open(os.path.join(stage, 'setup.ahk'), 'w', encoding='utf-8-sig').write(stub)
        epath = os.path.abspath(os.path.join(out, name + '.exe'))
        if os.path.exists(epath):
            os.remove(epath)
        base = os.path.join(stage, 'pkg', 'runtime64', 'Macro Manager Setup.exe')
        subprocess.run([ahk2exe, '/in', os.path.join(stage, 'setup.ahk'), '/out', epath, '/base', base, '/silent', 'verbose'],
                       check=True)
        assert os.path.isfile(epath), 'Ahk2Exe made no .exe'
        print('exe:', epath, ver)
finally:
    shutil.rmtree(work, ignore_errors=True)
