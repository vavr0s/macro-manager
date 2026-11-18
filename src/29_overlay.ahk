; ============ in-game overlay: state of the All macros switch ============
; A small bar over the game window: crown, "All macros" and a switch like the one in the banner. It never takes the
; focus and lets the mouse through (layered + transparent window); it is shown only while the game is in front -
; a program that an enabled macro of the current profile is limited to ("Only in app"), or any other program when
; no macro is limited. Exclusive full screen games draw over every window: use windowed / borderless there.
; Position: tray menu "In-game overlay" (OverlayPos: off / tl / tc / tr / bl / br, saved as overlay=).

OverlayStart() {
    global OvGui
    OvGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x080800A8")    ; NOACTIVATE | LAYERED | TRANSPARENT | TOOLWINDOW
    OvGui.Show("NA x-3000 y-3000 w10 h10")
    WinSetExStyle("+0x20", OvGui.Hwnd)
    SetTimer(OverlayTick, 150)
}

; called by the timer and right after the switch changes
OverlayTick() {
    global OvState
    static shown := false, last := ""
    if !IsSet(OvGui) || !OvGui
        return
    rc := (OverlayPos = "off") ? 0 : OverlayTarget()
    if !rc {
        if shown {
            OvGui.Hide(), shown := false
        }
        return
    }
    s := A_ScreenDPI / 96
    key := MasterOn "|" Lang "|" s
    if (key != last || !IsSet(OvState) || !OvState) {
        OverlayPaint(s)
        last := key
    }
    m := Round(12 * s), w := OvState.w, h := OvState.h
    x := InStr(OverlayPos, "l") ? rc.x + m : InStr(OverlayPos, "r") ? rc.x + rc.w - w - m : rc.x + (rc.w - w) // 2
    y := InStr(OverlayPos, "t") ? rc.y + m : rc.y + rc.h - h - m
    OverlayBlit(x, y)
    if !shown {
        OvGui.Show("NA")
        shown := true
    }
}

; client area of the game window in front (screen coordinates), or 0 when the overlay should not be shown
OverlayTarget() {
    try {
        hwnd := WinExist("A")
        if (!hwnd || WinGetPID(hwnd) = ProcessExist())                ; our own windows
            return 0
        exe := WinGetProcessName(hwnd)
        if (WinGetClass(hwnd) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")
            return 0
    } catch
        return 0
    limited := false, any := false
    for m in Macros {
        if (!m["enabled"] || !InProfile(m) || m["type"] = "script")
            continue
        any := true
        if (m["app"] != "") {
            limited := true
            if (StrLower(m["app"]) = StrLower(exe))
                return OverlayClient(hwnd)
        }
    }
    return (any && !limited) ? OverlayClient(hwnd) : 0
}

OverlayClient(hwnd) {
    WinGetClientPos(&x, &y, &w, &h, hwnd)
    return (w < 200 || h < 100) ? 0 : {x: x, y: y, w: w, h: h}
}

; draws the bar into a 32-bit DIB (premultiplied alpha) kept in OvState
OverlayPaint(s) {
    global OvState
    if (IsSet(OvState) && OvState) {
        DllCall("SelectObject", "Ptr", OvState.dc, "Ptr", OvState.old, "Ptr")
        DllCall("DeleteObject", "Ptr", OvState.bmp), DllCall("DeleteDC", "Ptr", OvState.dc)
    }
    if !GdipOn()
        return
    txt := _T("All macros")
    fs := 13 * s
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI Semibold", "Ptr", 0, "Ptr*", &fam := 0)
    if !fam
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", fs, "Int", 0, "Int", 2, "Ptr*", &font := 0)   ; pixels
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x1000, "Int", 0, "Ptr*", &fmt := 0)               ; no wrap
    ; text width
    tdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", tdc, "Ptr*", &tg := 0)
    lay := Buffer(16, 0), box := Buffer(16, 0)
    NumPut("Float", 0, "Float", 0, "Float", 1000, "Float", 100, lay)
    DllCall("gdiplus\GdipMeasureString", "Ptr", tg, "WStr", txt, "Int", -1, "Ptr", font, "Ptr", lay, "Ptr", fmt, "Ptr", box, "Ptr", 0, "Ptr", 0)
    tw := NumGet(box, 8, "Float"), th := NumGet(box, 12, "Float")
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", tg), DllCall("DeleteDC", "Ptr", tdc)

    h := Round(32 * s), pad := Round(10 * s), ch := Round(15 * s), cw := Round(ch * 1.3478)
    swW := Round(34 * s), swH := Round(18 * s), gap := Round(8 * s)
    w := pad + cw + gap + Ceil(tw) + gap + swW + pad
    ; 32-bit top-down DIB
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, bi)
    dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    bmp := DllCall("CreateDIBSection", "Ptr", dc, "Ptr", bi, "UInt", 0, "Ptr*", 0, "Ptr", 0, "UInt", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", dc, "Ptr", bmp, "Ptr")
    gr := GrOn(dc)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", gr, "Int", 4)     ; anti-aliased (ClearType needs a solid background)
    on := MasterOn
    FillRoundA(gr, 0, 0, w, h, h, 0xD80B0B0D)                              ; dark bar, slightly see-through
    FillRoundA(gr, 0.5 * s, 0.5 * s, w - s, h - s, h - s, 0x00000000, on ? 0x90D0AE6B : 0x60595D68)   ; thin outline
    DrawCrown(gr, pad, (h - ch) / 2, ch, on ? 0xFFD0AE6B : 0xFF6E7380)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", on ? 0xFFECECEF : 0xFFA9ADB8, "Ptr*", &tb := 0)
    NumPut("Float", pad + cw + gap, "Float", (h - th) / 2, "Float", tw + 4, "Float", th, lay)
    DllCall("gdiplus\GdipDrawString", "Ptr", gr, "WStr", txt, "Int", -1, "Ptr", font, "Ptr", lay, "Ptr", fmt, "Ptr", tb)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", tb)
    ; switch: gold track with the knob right = on, grey with the knob left = off
    sx := w - pad - swW, sy := (h - swH) / 2, kn := swH - 4 * s
    FillRoundA(gr, sx, sy, swW, swH, swH, on ? 0xFFD0AE6B : 0xFF3A3E49)
    FillRoundA(gr, on ? sx + swW - 2 * s - kn : sx + 2 * s, sy + 2 * s, kn, kn, kn, on ? 0xFF141414 : 0xFFA9ADB8)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt), DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
    OvState := {dc: dc, bmp: bmp, old: old, w: w, h: h}
}

OverlayBlit(x, y) {
    pt := Buffer(8), sz := Buffer(8), src := Buffer(8, 0), bl := Buffer(4)
    NumPut("Int", x, "Int", y, pt), NumPut("Int", OvState.w, "Int", OvState.h, sz)
    NumPut("UChar", 0, "UChar", 0, "UChar", 255, "UChar", 1, bl)           ; AC_SRC_OVER, alpha 255, AC_SRC_ALPHA
    DllCall("UpdateLayeredWindow", "Ptr", OvGui.Hwnd, "Ptr", 0, "Ptr", pt, "Ptr", sz, "Ptr", OvState.dc, "Ptr", src, "UInt", 0, "Ptr", bl, "UInt", 2)
    DllCall("SetWindowPos", "Ptr", OvGui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)  ; stay on top, no move / size / activate
}

; rounded rectangle with an ARGB fill and, optionally, an ARGB outline (fill 0 = outline only)
FillRoundA(gr, x, y, w, h, d, argb, line := 0) {
    d := Min(d, w, h)
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)
    x2 := x + w - d, y2 := y + h - d
    for a in [[x, y, 180], [x2, y, 270], [x2, y2, 0], [x, y2, 90]]
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pa, "Float", a[1], "Float", a[2], "Float", d, "Float", d, "Float", a[3], "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", pa)
    if (argb >> 24) {
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &fb := 0)
        DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    }
    if line {
        DllCall("gdiplus\GdipCreatePen1", "UInt", line, "Float", A_ScreenDPI / 96, "Int", 2, "Ptr*", &pn := 0)
        DllCall("gdiplus\GdipDrawPath", "Ptr", gr, "Ptr", pn, "Ptr", pa)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pn)
    }
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; the ComboCrown crown (vector from tools/brand/crown.json, height 1), h pixels tall, top-left at x, y
DrawCrown(gr, x, y, h, argb) {
    static shape := [[0.1337, 0.0000, 0.2435, 0.0033, 0.6728, 0.7913, 0.8087, 0.5533, 0.8261, 0.4902, 0.6750, 0.2174, 0.5446, 0.4348, 0.4870, 0.3359, 0.6609, 0.0120, 0.6870, 0.0207, 0.8924, 0.3913, 1.0957, 0.0120, 1.2174, 0.0033, 0.6750, 1.0000, 0.4174, 0.5337, 0.1880, 0.4435, 0.3304, 0.7880, 0.4837, 0.7913, 0.5304, 0.8728, 0.5272, 0.8870, 0.2609, 0.8837, 0.0000, 0.2924, 0.0228, 0.2783, 0.3304, 0.3880],
        [1.3250, 0.2783, 1.3478, 0.2837, 1.0783, 0.8837, 0.8120, 0.8870, 0.8554, 0.7913, 1.0174, 0.7793, 1.1565, 0.4663, 1.1511, 0.4435, 1.0261, 0.4837, 1.0783, 0.3772, 1.0989, 0.3565]]
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)          ; alternate fill: inner holes stay open
    for sub in shape {
        pts := Buffer(sub.Length * 4)
        for i, v in sub
            NumPut("Float", (i & 1 ? x : y) + v * h, pts, (i - 1) * 4)
        DllCall("gdiplus\GdipAddPathPolygon", "Ptr", pa, "Ptr", pts, "Int", sub.Length // 2)
    }
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; ---- tray menu: In-game overlay > Off / Top left / ...
OverlayMenu() {
    sub := Menu()
    for p in OverlayPlaces()
        sub.Add(p[2], OverlaySet.Bind(p[1]))
    A_TrayMenu.Add(_T("In-game overlay"), sub)
    OverlayChecks(sub)
    return sub
}

OverlayPlaces() => [["off", _T("Off")], ["tl", _T("Top left")], ["tc", _T("Top center")], ["tr", _T("Top right")], ["bl", _T("Bottom left")], ["br", _T("Bottom right")]]

OverlayChecks(sub) {
    for p in OverlayPlaces()
        (p[1] = OverlayPos) ? sub.Check(p[2]) : sub.Uncheck(p[2])
}

OverlaySet(pos, *) {
    global OverlayPos
    OverlayPos := pos
    OverlayChecks(OvMenu)
    Save()
    OverlayTick()
}
