import json,re,sys
lang=sys.argv[1]
k=json.load(open('/home/claude/i18n/keys.json',encoding='utf-8'))
try: t=json.load(open(f'/home/claude/i18n/{lang}.json',encoding='utf-8'))
except Exception as e: print('JSON ERROR',e); sys.exit(1)
bad=0
for key,v in k.items():
    if key not in t: print('MISSING',key[:60]); bad+=1; continue
    en=v['en']; tr=t[key]
    if sorted(re.findall(r'\{\d\}',en))!=sorted(re.findall(r'\{\d\}',tr)): print('PLACEHOLDERS',key[:60],'|',tr[:80]); bad+=1
    if en.count('\n')!=tr.count('\n'): print('NEWLINES',key[:60],en.count('\n'),tr.count('\n')); bad+=1
    if (len(en)-len(en.lstrip()))!=(len(tr)-len(tr.lstrip())) or (len(en)-len(en.rstrip()))!=(len(tr)-len(tr.rstrip())): print('SPACES',repr(en[:30]),repr(tr[:30])); bad+=1
    if '`' in tr: print('BACKTICK',key[:50]); bad+=1
    mc=v.get('max_chars')
    if mc and len(tr)>mc: print('TOO LONG',key,'->',tr,len(tr),'>',mc); bad+=1
for key in t:
    if key not in k: print('EXTRA',key[:60]); bad+=1
print('problems:',bad,'keys:',len(t))
