import re
def skip_lines(L):
    """1-based line numbers inside continuation sections ( ... ) and blobs"""
    inside=False; sk=set()
    for i,l in enumerate(L,1):
        s=l.strip()
        if not inside and (s=='(' or s.startswith('(Join') ) and not s.startswith('()'):
            inside=True; sk.add(i); continue
        if inside:
            sk.add(i)
            if s.startswith(')'): inside=False
    return sk
def lits(line):
    """yield (start,end,body,quote) for string literals in a code line; stops at comment"""
    i=0;n=len(line);out=[]
    while i<n:
        c=line[i]
        if c==';' and (i==0 or line[i-1] in ' \t'): break
        if c in '"\'':
            q=c;j=i+1;b=[]
            while j<n:
                if line[j]=='`' and j+1<n: b.append(line[j:j+2]); j+=2; continue
                if line[j]==q: break
                b.append(line[j]); j+=1
            out.append((i,j+1,''.join(b),q)); i=j+1; continue
        i+=1
    return out
def decode(b):
    return (b.replace('`n','\n').replace('`t','\t').replace('`"','"').replace("`'","'").replace('``','\x00').replace('\x00','`'))
def encode(s):
    return s.replace('`','``').replace('"','`"').replace('\n','`n').replace('\t','`t')
