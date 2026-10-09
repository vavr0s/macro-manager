from PIL import Image, ImageDraw
import base64,io,math
W,H=48,32
def base(): return Image.new('RGB',(W,H))
def finish(im):
    d=ImageDraw.Draw(im)
    d.rectangle([0,0,W-1,H-1],outline=(70,70,78))     # thin dark edge (the picture control has no alpha)
    return im
def cz():
    S=6; im=Image.new('RGB',(W*S,H*S)); d=ImageDraw.Draw(im)
    d.rectangle([0,0,W*S,H*S//2],fill=(255,255,255)); d.rectangle([0,H*S//2,W*S,H*S],fill=(215,20,26))
    d.polygon([(0,0),(W*S//2,H*S//2),(0,H*S)],fill=(17,69,126)); im=im.resize((W,H),Image.LANCZOS); return finish(im)
def pl():
    im=base();d=ImageDraw.Draw(im)
    d.rectangle([0,0,W,H//2],fill=(255,255,255)); d.rectangle([0,H//2,W,H],fill=(220,20,60)); return finish(im)
def de():
    im=base();d=ImageDraw.Draw(im)
    d.rectangle([0,0,W,H//3],fill=(0,0,0)); d.rectangle([0,H//3,W,2*H//3],fill=(221,0,0)); d.rectangle([0,2*H//3,W,H],fill=(255,206,0)); return finish(im)
def en():
    S=4; w,h=W*S,H*S
    im=Image.new('RGB',(w,h),(1,33,105)); d=ImageDraw.Draw(im)
    def diag(width,col,x0,y0,x1,y1):
        dx,dy=x1-x0,y1-y0; L=math.hypot(dx,dy); nx,ny=-dy/L*width/2,dx/L*width/2
        d.polygon([(x0+nx,y0+ny),(x1+nx,y1+ny),(x1-nx,y1-ny),(x0-nx,y0-ny)],fill=col)
    wd=h*0.2; rd=h*0.1
    for a in [(0,0,w,h),(0,h,w,0)]: diag(wd,(255,255,255),*a)
    # red diagonals (thinner, offset like the real flag: kept centred for a 48x32 miniature)
    for a in [(0,0,w,h),(0,h,w,0)]: diag(rd*0.8,(200,16,46),*a)
    d.rectangle([w/2-h*0.17,0,w/2+h*0.17,h],fill=(255,255,255)); d.rectangle([0,h/2-h*0.17,w,h/2+h*0.17],fill=(255,255,255))
    d.rectangle([w/2-h*0.1,0,w/2+h*0.1,h],fill=(200,16,46)); d.rectangle([0,h/2-h*0.1,w,h/2+h*0.1],fill=(200,16,46))
    im=im.resize((W,H),Image.LANCZOS); return finish(im)
out={}
for c,f in (('en',en),('cs',cz),('pl',pl),('de',de)):
    im=f(); im.save(f'/home/claude/i18n/flag_{c}.png'); b=io.BytesIO(); im.save(b,'PNG',optimize=True); out[c]=base64.b64encode(b.getvalue()).decode()
import json; json.dump(out,open('/home/claude/i18n/flags_b64.json','w'))
print({k:len(v) for k,v in out.items()})
