#!/usr/bin/env python3
"""Deploys the website (site/) to Cloudflare Pages (project macromanager, https://macromanager.pages.dev)
together with the stable setup packages. (The first address, the Worker macro-manager.vavr0smacromanager.workers.dev,
only redirects here - tools/site_redirect.js.)
usage: deploy_site.py --dist C:\\claude\\dist [--dry DIR]
The version comes from version.json on the main branch; the packages in --dist must be that version
(package.py prints it). --dry only assembles the folder (for a local preview) and does not deploy.
Runs wrangler from its own temp folder, never from server/ (that would pick up the library Worker's config)."""
import json, os, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'macromanager'
args = sys.argv[1:]
dist = args[args.index('--dist') + 1]
dry = args[args.index('--dry') + 1] if '--dry' in args else None

ver = json.loads(subprocess.check_output(['git', 'show', 'main:version.json'], cwd=ROOT))['version']
exe = os.path.join(dist, 'MacroManager-Setup.exe')
zipf = os.path.join(dist, 'MacroManager-Setup.zip')
for f in (exe, zipf):
    assert os.path.exists(f), f'missing {f}'
size = f'{os.path.getsize(exe) / 1048576:.1f}'

work = tempfile.mkdtemp(prefix='mmsite-')
out = dry or os.path.join(work, 'public')
if os.path.exists(out):
    shutil.rmtree(out)
shutil.copytree(os.path.join(ROOT, 'site'), out)
os.makedirs(os.path.join(out, 'download'))
shutil.copy2(exe, os.path.join(out, 'download'))
shutil.copy2(zipf, os.path.join(out, 'download'))
page = os.path.join(out, 'index.html')
s = open(page, encoding='utf-8').read().replace('{{VERSION}}', ver).replace('{{SIZE}}', size)
open(page, 'w', encoding='utf-8', newline='\n').write(s)
print(f'site {ver} ({size} MB) -> {out}')
try:
    if not dry:
        subprocess.check_call(f'npx wrangler pages deploy public --project-name {NAME} --branch main --commit-dirty=true',
                              shell=True, cwd=work)
finally:
    shutil.rmtree(work, ignore_errors=True)
