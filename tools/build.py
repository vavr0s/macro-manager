#!/usr/bin/env python3
"""Builds the single-file app from src/*.ahk (files in name order).
The app is distributed and self-updates as ONE file, so the parts are joined, not #Included.
usage: build.py [output]   (default: /home/claude/macro-manager.ahk)"""
import os,sys,glob
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out=sys.argv[1] if len(sys.argv)>1 else '/home/claude/macro-manager.ahk'
parts=sorted(glob.glob(os.path.join(ROOT,'src','*.ahk')))
text='; Macro Manager - built from src/*.ahk by tools/build.py (edit those files, not this one)\n'
text+='\n'.join(open(p,encoding='utf-8').read().rstrip('\n')+'\n' for p in parts)
assert '\r' not in text
open(out,'w',encoding='utf-8',newline='').write(text)
print('built',out,len(parts),'parts',text.count('\n'),'lines')
