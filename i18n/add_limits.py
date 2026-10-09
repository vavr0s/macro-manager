import json,re
k=json.load(open('/home/claude/i18n/keys.json',encoding='utf-8'))
src=open('/home/claude/macro-manager.ahk',encoding='utf-8').read()
for key,v in k.items():
    en=v['en']; e=re.escape(key[:20])
    mc=None
    m=re.search(r'AddBtn\([^"]*"[^"]*?\bw(\d+)\b[^"]*",\s*[^,]*_T\("'+e,src)
    if m: mc=(int(m.group(1))-16)//7
    m=re.search(r'AddText\("x\d+ y\d+ w(\d+) \+0x200 h26", _T\("'+re.escape(en[:25]),src)
    if m: mc=(int(m.group(1))-6)//6
    if re.search(r'AddText\("x600 y\d+ w105 Right BackgroundTrans", _T\("'+re.escape(en),src): mc=15
    if v['ctx'][0].startswith('Help window topic'): mc=24
    if mc: v['max_chars']=mc
for a,n in {'Uninstall':12,'Select':8,'Record':9,'Save':13,'Cancel':13,'Browse...':13}.items(): k[a]['max_chars']=n
json.dump(k,open('/home/claude/i18n/keys.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(sum('max_chars' in v for v in k.values()))
