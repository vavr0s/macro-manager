# Builds the ComboCrown brand kit (SVG / PNG / ICO in every needed size) from the vector crown (crown.json).
# usage: brand.ps1 -Out C:\claude\dist\ComboCrown-brand
# The crown was traced from the original logo; the wordmark is "ComboCrown" in Segoe UI Bold, outlined to paths.
param([Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$inv = [Globalization.CultureInfo]::InvariantCulture
function F([double]$v) { $v.ToString('0.###', $inv) }

$GOLD = 'D0AE6B'; $WHITE = 'FFFFFF'; $BLACK = '000000'; $INK = '1B1B1F'; $DARK = '15161A'
$BORDER = '342D1E'; $BETA_BORDER = 'C6C6CF'

# ---------- geometry ----------
$cj = Get-Content (Join-Path $here 'crown.json') -Raw | ConvertFrom-Json
$cb = $cj.bbox; $CW = $cb[2] - $cb[0]; $CH = $cb[3] - $cb[1]
# crown path in unit space: (0,0)-(CW,CH)
function CrownPath {
  $p = New-Object Drawing.Drawing2D.GraphicsPath ([Drawing.Drawing2D.FillMode]::Alternate)
  foreach ($pl in $cj.polys) {
    $pts = foreach ($q in $pl) { New-Object Drawing.PointF ([float]($q[0] - $cb[0])), ([float]($q[1] - $cb[1])) }
    $p.AddPolygon([Drawing.PointF[]]$pts)
  }
  $p
}
# wordmark path, top-left of its ink at (0,0)
function WordPath {
  $p = New-Object Drawing.Drawing2D.GraphicsPath ([Drawing.Drawing2D.FillMode]::Winding)
  $p.AddString('ComboCrown', (New-Object Drawing.FontFamily 'Segoe UI'), 1, 100, (New-Object Drawing.PointF 0, 0), [Drawing.StringFormat]::GenericTypographic)
  $b = $p.GetBounds()
  $m = New-Object Drawing.Drawing2D.Matrix; $m.Translate(-$b.X, -$b.Y); $p.Transform($m)
  $p
}
$WP = WordPath; $WB = $WP.GetBounds(); $WW = $WB.Width; $WH = $WB.Height

function SvgD($path) {
  $pts = $path.PathPoints; $ty = $path.PathTypes; $sb = New-Object Text.StringBuilder; $i = 0
  while ($i -lt $pts.Length) {
    $t = $ty[$i] -band 7
    if ($t -eq 0) { [void]$sb.Append("M$(F $pts[$i].X),$(F $pts[$i].Y)"); $i++ }
    elseif ($t -eq 1) { [void]$sb.Append("L$(F $pts[$i].X),$(F $pts[$i].Y)"); $i++ }
    else { [void]$sb.Append("C$(F $pts[$i].X),$(F $pts[$i].Y) $(F $pts[$i+1].X),$(F $pts[$i+1].Y) $(F $pts[$i+2].X),$(F $pts[$i+2].Y)"); $i += 3 }
    if ($ty[$i - 1] -band 0x80) { [void]$sb.Append('Z') }
  }
  $sb.ToString()
}
$CROWN_D = SvgD (CrownPath); $WORD_D = SvgD $WP

# ---------- compositions: each is a list of layers in a W x H canvas ----------
# layer: @{k='crown'|'word'|'rect'; x; y; s (scale); c (hex); ...}
function Crown($x, $y, $w, $c) { @{ k = 'crown'; x = $x; y = $y; s = $w / $CW; c = $c } }
function Word($x, $y, $h, $c) { @{ k = 'word'; x = $x; y = $y; s = $h / $WH; c = $c } }
function RRect($x, $y, $w, $h, $r, $fill, $stroke, $sw) { @{ k = 'rect'; x = $x; y = $y; w = $w; h = $h; r = $r; c = $fill; st = $stroke; sw = $sw } }

function Svg($file, $W, $H, $layers) {
  $b = New-Object Text.StringBuilder
  [void]$b.Append("<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 $(F $W) $(F $H)`" width=`"$(F $W)`" height=`"$(F $H)`">`n")
  foreach ($l in $layers) {
    switch ($l.k) {
      'rect' { $st = if ($l.st) { " stroke=`"#$($l.st)`" stroke-width=`"$(F $l.sw)`"" } else { '' }
               [void]$b.Append("  <rect x=`"$(F $l.x)`" y=`"$(F $l.y)`" width=`"$(F $l.w)`" height=`"$(F $l.h)`" rx=`"$(F $l.r)`" fill=`"#$($l.c)`"$st/>`n") }
      'crown' { [void]$b.Append("  <path transform=`"translate($(F $l.x) $(F $l.y)) scale($(F $l.s))`" fill=`"#$($l.c)`" fill-rule=`"evenodd`" d=`"$CROWN_D`"/>`n") }
      'word' { [void]$b.Append("  <path transform=`"translate($(F $l.x) $(F $l.y)) scale($(F $l.s))`" fill=`"#$($l.c)`" d=`"$WORD_D`"/>`n") }
    }
  }
  [void]$b.Append("</svg>`n")
  [IO.File]::WriteAllText($file, $b.ToString(), (New-Object Text.UTF8Encoding $false))
}

function Png($file, $W, $H, $layers, [int]$pw, [int]$ph = 0) {
  if ($ph -eq 0) { $ph = [int][Math]::Round($pw * $H / $W) }
  $k = $pw / $W
  $bmp = New-Object Drawing.Bitmap $pw, $ph, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([Drawing.Color]::Transparent)
  foreach ($l in $layers) {
    $col = [Drawing.ColorTranslator]::FromHtml('#' + $l.c)
    if ($l.k -eq 'rect') {
      $x = $l.x * $k; $y = $l.y * $k; $w = $l.w * $k; $h = $l.h * $k; $d = 2 * $l.r * $k
      $p = New-Object Drawing.Drawing2D.GraphicsPath
      if ($d -le 0) { $p.AddRectangle((New-Object Drawing.RectangleF $x, $y, $w, $h)) }
      else {
        $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
        $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90); $p.CloseFigure()
      }
      $g.FillPath((New-Object Drawing.SolidBrush $col), $p)
      if ($l.st) { $g.DrawPath((New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml('#' + $l.st)), ([float]($l.sw * $k))), $p) }
    } else {
      $p = if ($l.k -eq 'crown') { CrownPath } else { $WP.Clone() }
      $m = New-Object Drawing.Drawing2D.Matrix
      $m.Translate([float]($l.x * $k), [float]($l.y * $k)); $m.Scale([float]($l.s * $k), [float]($l.s * $k)); $p.Transform($m)
      $g.FillPath((New-Object Drawing.SolidBrush $col), $p)
    }
  }
  $g.Dispose(); $bmp.Save($file, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

function Ico($file, [string[]]$pngs) {
  $blobs = $pngs | % { ,[IO.File]::ReadAllBytes($_) }
  $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $ms
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$blobs.Count)
  $off = 6 + 16 * $blobs.Count
  foreach ($b in $blobs) {
    $w = [BitConverter]::ToUInt32(@($b[19], $b[18], $b[17], $b[16]), 0); $h = [BitConverter]::ToUInt32(@($b[23], $b[22], $b[21], $b[20]), 0)
    $bw.Write([byte]($w % 256)); $bw.Write([byte]($h % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$b.Length); $bw.Write([uint32]$off); $off += $b.Length
  }
  foreach ($b in $blobs) { $bw.Write($b) }
  [IO.File]::WriteAllBytes($file, $ms.ToArray())
}

# ---------- definitions ----------
$crownOnly = @{ W = $CW; H = $CH }
function CrownComp($c) { , @(Crown 0 0 $CW $c) }
function IconComp { , @((RRect 1.5 1.5 253 253 54.5 $BLACK $BORDER 3), (Crown (128 - 84) (128 - 84 * $CH / $CW) 168 $GOLD)) }
function BetaComp { , @((RRect 9.5 9.5 237 237 60 $WHITE $BETA_BORDER 3), (Crown (128 - 84) (128 - 84 * $CH / $CW) 168 $GOLD)) }
# horizontal logo: crown height 100, gap 28, word cap height 58 centred on the crown
$LH = 100; $LCW = $LH * $CW / $CH; $LWH = 58; $LWW = $LWH * $WW / $WH; $LGAP = 28
$LW = $LCW + $LGAP + $LWW
function LogoComp($cc, $wc) { , @((Crown 0 0 $LCW $cc), (Word ($LCW + $LGAP) (($LH - $LWH) / 2) $LWH $wc)) }

$dirs = 'svg', 'png\crown', 'png\icon', 'png\logo', 'ico', 'web', 'social'
foreach ($d in $dirs) { New-Item -ItemType Directory -Force (Join-Path $Out $d) | Out-Null }

# SVG
Svg "$Out\svg\crown-gold.svg" $CW $CH (CrownComp $GOLD)
Svg "$Out\svg\crown-white.svg" $CW $CH (CrownComp $WHITE)
Svg "$Out\svg\crown-black.svg" $CW $CH (CrownComp $BLACK)
Svg "$Out\svg\icon.svg" 256 256 (IconComp)
Svg "$Out\svg\icon-beta.svg" 256 256 (BetaComp)
Svg "$Out\svg\logo-gold.svg" $LW $LH (LogoComp $GOLD $GOLD)
Svg "$Out\svg\logo-on-light.svg" $LW $LH (LogoComp $GOLD $INK)
Svg "$Out\svg\logo-white.svg" $LW $LH (LogoComp $WHITE $WHITE)
Svg "$Out\svg\logo-black.svg" $LW $LH (LogoComp $BLACK $BLACK)

# PNG: crown (transparent), sized by width
foreach ($c in @(@('gold', $GOLD), @('white', $WHITE), @('black', $BLACK))) {
  foreach ($w in 64, 128, 256, 512, 1024, 2048) { Png "$Out\png\crown\crown-$($c[0])-$w.png" $CW $CH (CrownComp $c[1]) $w }
}
# PNG: app icons (the small sizes keep the hand-made pictures of the app)
$small = Join-Path $here 'icon_small'
foreach ($n in 'icon', 'beta') {
  $comp = if ($n -eq 'icon') { IconComp } else { BetaComp }
  $name = if ($n -eq 'icon') { 'icon' } else { 'icon-beta' }
  foreach ($s in 16, 32, 48) { Copy-Item "$small\$($n)_$s.png" "$Out\png\icon\$name-$s.png" }
  foreach ($s in 24, 64, 128, 256, 512, 1024) { Png "$Out\png\icon\$name-$s.png" 256 256 $comp $s }
}
# PNG: horizontal logo, sized by width
foreach ($v in @(@('gold', $GOLD, $GOLD), @('on-light', $GOLD, $INK), @('white', $WHITE, $WHITE), @('black', $BLACK, $BLACK))) {
  foreach ($w in 400, 800, 1600, 3200) { Png "$Out\png\logo\logo-$($v[0])-$w.png" $LW $LH (LogoComp $v[1] $v[2]) $w }
}
# ICO
Ico "$Out\ico\combocrown.ico" (16, 24, 32, 48, 64, 128, 256 | % { "$Out\png\icon\icon-$_.png" })
Ico "$Out\ico\combocrown-beta.ico" (16, 24, 32, 48, 64, 128, 256 | % { "$Out\png\icon\icon-beta-$_.png" })

# web: favicon + app icons for phones + share picture
Ico "$Out\web\favicon.ico" (16, 32, 48 | % { "$Out\png\icon\icon-$_.png" })
Copy-Item "$Out\png\icon\icon-32.png" "$Out\web\favicon-32.png"
$sq = { param($fill, $crownW) , @((RRect 0 0 100 100 0 $fill $null 0), (Crown (50 - $crownW / 2) (50 - $crownW / 2 * $CH / $CW) $crownW $GOLD)) }    # (not $cw: PowerShell names ignore case, it would hide $CW)
Png "$Out\web\apple-touch-icon.png" 100 100 (& $sq $BLACK 64) 180
Png "$Out\web\android-chrome-192.png" 100 100 (& $sq $BLACK 64) 192
Png "$Out\web\android-chrome-512.png" 100 100 (& $sq $BLACK 64) 512
# share picture 1200 x 630: dark background, logo, tagline as outlined text
$tag = New-Object Drawing.Drawing2D.GraphicsPath
$tag.AddString('Game macros for any mouse and keyboard', (New-Object Drawing.FontFamily 'Segoe UI'), 0, 100, (New-Object Drawing.PointF 0, 0), [Drawing.StringFormat]::GenericTypographic)
$tb = $tag.GetBounds(); $mt = New-Object Drawing.Drawing2D.Matrix; $mt.Translate(-$tb.X, -$tb.Y); $tag.Transform($mt)
$script:TAG_D = SvgD $tag
$ogScale = 620 / $LW; $ogX = (1200 - 620) / 2; $ogY = 215
$ogLayers = @((RRect 0 0 1200 630 0 $DARK $null 0), (Crown $ogX $ogY ($LCW * $ogScale) $GOLD), (Word ($ogX + ($LCW + $LGAP) * $ogScale) ($ogY + ($LH - $LWH) / 2 * $ogScale) ($LWH * $ogScale) $GOLD))
Png "$Out\web\og-image.png" 1200 630 $ogLayers 1200
# tagline drawn on top (light grey), centred under the logo
$bmp = [Drawing.Bitmap]::FromFile("$Out\web\og-image.png"); $b2 = New-Object Drawing.Bitmap $bmp; $bmp.Dispose()
$g = [Drawing.Graphics]::FromImage($b2); $g.SmoothingMode = 'AntiAlias'
$th = 34; $ts = $th / $tb.Height; $tw = $tb.Width * $ts
$m = New-Object Drawing.Drawing2D.Matrix; $m.Translate([float]((1200 - $tw) / 2), [float]($ogY + $LH * $ogScale + 48)); $m.Scale([float]$ts, [float]$ts)
$t2 = $tag.Clone(); $t2.Transform($m); $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#A9ADB8'))), $t2); $g.Dispose()
$b2.Save("$Out\web\og-image.png", [Drawing.Imaging.ImageFormat]::Png); $b2.Dispose()

# social: Discord server icon (shown as a circle), avatar for webhooks / bot, banner 960 x 540
Png "$Out\social\discord-server-icon-512.png" 100 100 (& $sq $BLACK 58) 512
Png "$Out\social\avatar-512.png" 256 256 (IconComp) 512
$bnScale = 600 / $LW; $bnX = (960 - 600) / 2; $bnY = (540 - $LH * $bnScale) / 2
Png "$Out\social\banner-960x540.png" 960 540 @((RRect 0 0 960 540 0 $DARK $null 0), (Crown $bnX $bnY ($LCW * $bnScale) $GOLD), (Word ($bnX + ($LCW + $LGAP) * $bnScale) ($bnY + ($LH - $LWH) / 2 * $bnScale) ($LWH * $bnScale) $GOLD)) 960
Copy-Item (Join-Path $here 'README.txt') $Out
'done'
