import sys,re,json;sys.path.insert(0,'/home/claude/i18n')
from ahklit import *
L=open('/home/claude/macro-manager.ahk',encoding='utf-8').read().split('\n')
sk=skip_lines(L)
keys={}
def add(k,en,ctx):
    if k in keys: keys[k]['ctx'].append(ctx)
    else: keys[k]={'en':en,'ctx':[ctx]}
for i,l in enumerate(L,1):
    if i in sk: continue
    for a,b,body,q in lits(l):
        if q!='"': continue
        pre=l[:a]
        if re.search(r'_T\(\s*$',pre) and not re.search(r'_TL\($',pre):
            en=decode(body); add(en,en,l.strip()[:230])
        m=re.search(r'_TL\("([a-z_]+)", $',pre)
        if m: add(m.group(1),decode(body),'HELP TOPIC TEXT (shown in the Help window, read as a manual)')
for t in ["Release notes","Getting started","Add / edit a macro","Move + actions","Sequence","Script (.ahk)","Keys and recording","Profiles","Toggle keys","Order, export, backup","Updates","Tips and problems"]:
    add(t,t,'Help window topic title (navigation button, ~25 characters max)')
json.dump(keys,open('keys.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(len(keys), sum(len(v['en'].split()) for v in keys.values()))
