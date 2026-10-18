; ============ dark mode ============
AddHint(g, opts, text) {
    c := g.AddText(opts, text)
    Roles[c.Hwnd] := "hint"
    return c
}

OnDarkToggle(*) {
    global DarkOn
    DarkOn := !DarkOn
    swPic.Value := DarkOn ? SwOnFile : SwOffFile
    Save()
    DarkMenus(DarkOn)
    ApplyTheme(Main)
}

; tray menu in the app's look: dark or light, whatever Windows uses
; (SetPreferredAppMode / FlushMenuThemes, uxtheme ordinals 135 / 136 - as in nperovic/GuiEnhancerKit, MIT)
DarkMenus(on) {
    try {
        ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
        setMode := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr")
        flush := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr")
        if (setMode && flush && VerCompare(A_OSVersion, "10.0.18362") >= 0) {
            DllCall(setMode, "Int", on ? 2 : 3)         ; 2 = always dark, 3 = always light
            DllCall(flush)
        }
    }
}

SetTheme(hwnd, name := "", sub := "") {
    if (name = "")
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Ptr", 0, "Ptr", 0)      ; back to the default theme
    else
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", name, "Ptr", sub = "" ? 0 : StrPtr(sub))
}

; [fill, text] or [fill, text, border] - light mode buttons get a thin border so they stand out from the window
RoleColors(role, hover := false) {
    d := DarkOn
    switch role {
        case "btnprimary":
            if d
                return hover ? ["E3C486", "141414"] : ["D0AE6B", "141414"]
            return hover ? ["DDBB78", "141414", "B08D4E"] : ["D0AE6B", "141414", "B08D4E"]
        case "btndanger":
            if d
                return hover ? ["55292F", "FFB4B4"] : ["3B2226", "FF9C9C"]
            return hover ? ["F0C4C4", "9E1F18", "D69494"] : ["F6D9D9", "9E1F18", "E2AEAE"]
        case "btnghost":
            if d
                return hover ? ["1F2127", "ECECEF"] : ["15161A", "A9ADB8"]
            return hover ? ["DCDDE4", "1B1B1F", "BDBEC8"] : ["EBEBF0", "3E3E48", "D3D3DB"]
        case "btnbanner":
            return hover ? ["3A3E49", "E3C486"] : ["22242B", "D0AE6B"]
        case "btnupd0":
            return hover ? ["3A3E49", "B8BCC8"] : ["22242B", "6E7380"]
        case "btnupd1":
            return hover ? ["3FE07F", "FFFFFF"] : ["1FB95A", "FFFFFF"]      ; + radar halo (UpdPulseTick)
        case "hdr":
            return d ? ["1F2127", "A9ADB8"] : ["E9E9EE", "5A5A66"]
        default:    ; plain button
            if d
                return hover ? ["3A3E49", "FFFFFF"] : ["2A2D35", "ECECEF"]
            return hover ? ["CBCCD6", "111114", "AEB0BC"] : ["DCDDE4", "111114", "BDBEC8"]
    }
}

; flat "button" = a clickable text control with its own colours (no system border)
; the button is drawn by the app itself (owner-drawn text control, see DrawBtn): rounded, smooth corners.
; round = false: square (rows of the drop-down lists)
AddBtn(g, opts, text, handler, role := "btn", round := true) {
    c := g.AddText(RegExReplace(opts, "i)\bLeft\b") " +0xD", text)      ; SS_OWNERDRAW ("Left" would clear it; DrawBtn aligns)
    c.OnEvent("Click", handler)
    Roles[c.Hwnd] := role
    BtnLook[c.Hwnd] := {left: InStr(opts, "Left") > 0, round: round, hover: false, badge: false, pad: [0, 0, 0, 0]}
    return c
}

PaintBtn(hwnd, hover) {
    try {
        if BtnLook.Has(hwnd)
            BtnLook[hwnd].hover := hover
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)     ; repaint without erasing first: no flicker
        for pic, btn in BtnAlias                                       ; a picture lying on the button (a flag):
            if (btn = hwnd) {                                          ; button first, then the picture on top again
                DllCall("UpdateWindow", "Ptr", hwnd)
                DllCall("RedrawWindow", "Ptr", pic, "Ptr", 0, "Ptr", 0, "UInt", 0x105)   ; invalidate + erase + now
            }
    }
}

; WM_DRAWITEM of a flat button: background of the window in the corners, rounded fill (GDI+, anti-aliased),
; text in the middle. Drawn into a memory bitmap first, so hovering does not flicker.
; (rounded colour buttons: idea of nperovic/ColorButton.ahk, MIT)
DrawBtn(wParam, lParam, *) {
    static ps := A_PtrSize
    if (NumGet(lParam, 0, "UInt") != 5)                       ; ODT_STATIC only
        return
    h := NumGet(lParam, ps = 8 ? 24 : 20, "Ptr")
    if !(Roles.Has(h) && BtnLook.Has(h))
        return
    dc := NumGet(lParam, ps = 8 ? 32 : 24, "Ptr")
    rcOff := ps = 8 ? 40 : 28
    w := NumGet(lParam, rcOff + 8, "Int") - NumGet(lParam, rcOff, "Int")
    hh := NumGet(lParam, rcOff + 12, "Int") - NumGet(lParam, rcOff + 4, "Int")
    if (w < 1 || hh < 1)
        return true
    lk := BtnLook[h]
    role := Roles[h]
    s := A_ScreenDPI / 96
    winBg := DarkOn ? "15161A" : "F5F5F7"
    mdc := DllCall("CreateCompatibleDC", "Ptr", dc, "Ptr")
    bmp := DllCall("CreateCompatibleBitmap", "Ptr", dc, "Int", w, "Int", hh, "Ptr")
    obmp := DllCall("SelectObject", "Ptr", mdc, "Ptr", bmp, "Ptr")
    r := Buffer(16, 0)
    if (role = "badge") {                                      ; the yellow "!" on its own (help window, dialogs)
        FillHex(mdc, 0, 0, w, hh, winBg)
        if GdipOn() {
            gr := GrOn(mdc)
            DrawBadge(gr, w / 2, hh / 2, Min(w, hh) / 2, "")
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        }
    } else {
        col := RoleColors(role, lk.hover)
        disabled := !DllCall("IsWindowEnabled", "Ptr", h)      ; (itemState of a static says "disabled" on Windows even when it is not)
        under := (role = "btnbanner" || SubStr(role, 1, 6) = "btnupd") ? "000000" : winBg
        ; the button itself may be smaller than the control (room for the "!" badge of the help button)
        fx := Round(lk.pad[1] * s), fy := Round(lk.pad[2] * s)
        fw := w - fx - Round(lk.pad[3] * s), fh := hh - fy - Round(lk.pad[4] * s)
        FillHex(mdc, 0, 0, w, hh, lk.round ? under : col[1])
        if (lk.round && GdipOn()) {
            d := Min(fh, Round(12 * s)) + 0.0
            gr := GrOn(mdc)
            b := Round(s)                                       ; border width
            if (col.Length >= 3) {
                FillRound(gr, fx, fy, fw, fh, d, col[3])        ; border = outer shape, fill = shape inside it
                FillRound(gr, fx + b, fy + b, fw - 2 * b, fh - 2 * b, Max(2, d - 2 * b), col[1])
            } else
                FillRound(gr, fx, fy, fw, fh, d, col[1])
            if (lk.badge && HelpBadgeOn)
                DrawBadge(gr, fx + fw, fy + 6 * s, 8 * s, under)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        } else if lk.round
            FillHex(mdc, fx, fy, fw, fh, col[1])
        txt := ""
        try txt := GuiCtrlFromHwnd(h).Text
        font := SendMessage(0x31, 0, 0, h)                      ; WM_GETFONT
        of := DllCall("SelectObject", "Ptr", mdc, "Ptr", font, "Ptr")
        DllCall("SetBkMode", "Ptr", mdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", mdc, "UInt", Bgr(disabled ? (DarkOn ? "6E7380" : "A0A0AA") : col[2]))
        NumPut("Int", fx, "Int", fy, "Int", fx + fw, "Int", fy + fh, r)
        if (StrLen(txt) = 1 && !lk.left && GlyphCenter(mdc, txt, fw, fh, &gx, &gy))
            DllCall("TextOutW", "Ptr", mdc, "Int", fx + gx, "Int", fy + gy, "WStr", txt, "Int", 1)   ; icon (?, arrow, ×): the drawn shape itself centred
        else
            DllCall("DrawTextW", "Ptr", mdc, "WStr", txt, "Int", -1, "Ptr", r, "UInt", 0x824 | (lk.left ? 0 : 1))   ; SINGLELINE VCENTER NOPREFIX (+CENTER)
        DllCall("SelectObject", "Ptr", mdc, "Ptr", of, "Ptr")
    }
    DllCall("BitBlt", "Ptr", dc, "Int", NumGet(lParam, rcOff, "Int"), "Int", NumGet(lParam, rcOff + 4, "Int"), "Int", w, "Int", hh, "Ptr", mdc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", obmp, "Ptr")
    DllCall("DeleteObject", "Ptr", bmp)
    DllCall("DeleteDC", "Ptr", mdc)
    return true
}

FillHex(dc, x, y, w, h, hex) {
    r := Buffer(16, 0)
    NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, r)
    br := DllCall("CreateSolidBrush", "UInt", Bgr(hex), "Ptr")
    DllCall("FillRect", "Ptr", dc, "Ptr", r, "Ptr", br)
    DllCall("DeleteObject", "Ptr", br)
}

GrOn(dc) {
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &gr := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)        ; anti-alias
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)      ; half-pixel: crisp straight edges
    return gr
}

; "new release notes" badge: gold circle with a dark "!", all drawn as shapes (sharp at any size / display scale).
; ring = colour of a thin outline that separates it from what it overlaps ("" = none)
DrawBadge(gr, cx, cy, ro, ring) {
    ri := ro
    if (ring != "") {
        FillRound(gr, cx - ro, cy - ro, 2 * ro, 2 * ro, 2 * ro, ring)
        ri := ro - 1.5 * A_ScreenDPI / 96
    }
    FillRound(gr, cx - ri, cy - ri, 2 * ri, 2 * ri, 2 * ri, "F2C94C")
    bw := Max(1.6, ri * 0.34)                                   ; the bar of the "!"
    FillRound(gr, cx - bw / 2, cy - ri * 0.62, bw, ri * 0.82, bw, "1B1B1F")
    dr := Max(0.9, ri * 0.19)                                   ; its dot
    FillRound(gr, cx - dr, cy + ri * 0.50 - dr, 2 * dr, 2 * dr, 2 * dr, "1B1B1F")
}

; the badge as its own control (help window, release notes dialog)
AddBadge(g, opts) {
    c := g.AddText(opts " +0xD")
    Roles[c.Hwnd] := "badge"
    BtnLook[c.Hwnd] := {left: false, round: false, hover: false, badge: false, pad: [0, 0, 0, 0]}
    return c
}

; shows / hides the badge on the help button in the banner
SetHelpBadge(on) {
    global HelpBadgeOn
    HelpBadgeOn := on
    try DllCall("InvalidateRect", "Ptr", bHelp.Hwnd, "Ptr", 0, "Int", 0)
}

FillRound(gr, x, y, w, h, d, hex) {
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)
    x2 := x + w - d, y2 := y + h - d
    for a in [[x, y, 180], [x2, y, 270], [x2, y2, 0], [x, y2, 90]]
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pa, "Float", a[1], "Float", a[2], "Float", d, "Float", d, "Float", a[3], "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", pa)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" hex), "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; top-left text position that puts the visible shape of one character exactly in the middle of a w x h box
; (DrawText centres the character cell, whose empty space above / beside the shape differs per font)
GlyphCenter(dc, ch, w, h, &x, &y) {
    gm := Buffer(20, 0), mat := Buffer(16, 0)
    NumPut("Short", 0, "Short", 1, "Short", 0, "Short", 0, "Short", 0, "Short", 0, "Short", 0, "Short", 1, mat)   ; identity MAT2
    if (DllCall("GetGlyphOutlineW", "Ptr", dc, "UInt", Ord(ch), "UInt", 0, "Ptr", gm, "UInt", 0, "Ptr", 0, "Ptr", mat, "UInt") = 0xFFFFFFFF)
        return false
    bw := NumGet(gm, 0, "UInt"), bh := NumGet(gm, 4, "UInt")
    ox := NumGet(gm, 8, "Int"), oy := NumGet(gm, 12, "Int")       ; black box corner from the origin (y up)
    tm := Buffer(60, 0)
    DllCall("GetTextMetricsW", "Ptr", dc, "Ptr", tm)
    asc := NumGet(tm, 4, "Int")                                     ; baseline below the top of the cell
    x := Round((w - bw) / 2 - ox)
    y := Round((h - bh) / 2 + oy - asc)
    return bw > 0 && bh > 0
}

Bgr(hex) {
    v := Integer("0x" hex)
    return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
}

; GDI+ started once (also used for the list check boxes)
GdipOn() {
    static tok := 0
    if !tok {
        try {
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", 1, si)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
        }
    }
    return tok != 0
}

; hover effect for the flat buttons
HoverTick() {
    global HoverHwnd
    if (!HoverHwnd && !DllCall("IsWindowVisible", "Ptr", Main.Hwnd))
        return                                      ; window hidden in the tray: nothing to hover
    h := 0
    try MouseGetPos(, , , &h, 2)
    if (h && BtnAlias.Has(h))
        h := BtnAlias[h]
    nh := (h && Roles.Has(h) && SubStr(Roles[h], 1, 3) = "btn") ? h : 0
    if (nh = HoverHwnd)
        return
    old := HoverHwnd
    HoverHwnd := nh
    if old
        PaintBtn(old, false)
    if nh
        PaintBtn(nh, true)
    try {
        if (nh && nh = bUpd.Hwnd)
            ToolTip(UpdAvail ? _T("New version {1} available - click to update", UpdInfo["ver"]) : _T("Up to date (v{1}) - click to check again", AppVersion))
        else if (old && old = bUpd.Hwnd)
            ToolTip()
    }
}

ApplyTheme(g) {
    dark := DarkOn
    win := dark ? "15161A" : "F5F5F7"
    box := dark ? "1F2127" : "FFFFFF"
    txt := dark ? "ECECEF" : "1B1B1F"
    hint := dark ? "A9ADB8" : "6A6A74"
    g.BackColor := win
    flag := Buffer(4)
    NumPut("Int", dark ? 1 : 0, flag)
    for attr in [20, 19]                       ; dark title bar (Win10 1809+ / Win11)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", attr, "Ptr", flag, "Int", 4)
    ; Windows 11: title bar and border in the app's own colours (DWMWA_BORDER / CAPTION / TEXT_COLOR)
    if (VerCompare(A_OSVersion, "10.0.22000") >= 0) {
        for attr, col in Map(34, dark ? "2A2D35" : "D6D6DE", 35, win, 36, txt) {
            rgb := Integer("0x" col)
            NumPut("UInt", ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16), flag)     ; COLORREF = 0x00BBGGRR
            try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", attr, "Ptr", flag, "Int", 4)
        }
    }
    for hwnd, c in g {
        role := Roles.Has(hwnd) ? Roles[hwnd] : ""
        if (role = "skip")
            continue
        try {
            switch c.Type {
                case "Text":
                    if (role = "hdr") {
                        col := RoleColors(role)
                        c.Opt("Background" col[1])
                        c.SetFont("s9 bold c" col[2])
                    } else if (SubStr(role, 1, 3) = "btn") {
                        c.SetFont("s9")                     ; colours: DrawBtn
                    } else
                        c.SetFont("c" (role = "hint" ? hint : txt))
                case "Edit":
                    c.Opt("Background" box)
                    if (ControlGetStyle(hwnd) & 0x4)               ; multi-line (help text, script, sequence): dark scroll bars too
                        SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                    else
                        SetTheme(hwnd, dark ? "DarkMode_CFD" : "", dark ? "Edit" : "")
                    if (role = "code")
                        c.SetFont("c" txt, "Consolas")
                    else
                        c.SetFont("c" txt)
                case "Button":
                    SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                case "CheckBox", "Radio":
                    if dark
                        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "", "Str", "")   ; classic look so the text colour is honoured
                    else
                        SetTheme(hwnd, "")
                    c.SetFont("c" txt)
                case "DDL":
                    SetTheme(hwnd, dark ? "DarkMode_CFD" : "", dark ? "Combobox" : "")
                case "ListView":
                    c.Opt("Background" box " c" txt)
                    SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                    SetCheckImages(c)
            }
            c.Redraw()
        }
    }
}

; ============ window placement / list look ============
; show a window centred over `anchor` (default: the main window), on the same monitor
ShowOver(g, opts, anchor := 0) {
    try {
        if !anchor
            anchor := Main
        ah := IsObject(anchor) ? anchor.Hwnd : anchor
        if (!ah || !DllCall("IsWindowVisible", "Ptr", ah) || DllCall("IsIconic", "Ptr", ah)) {
            g.Show(opts)
            return
        }
        g.Show(opts " Hide")
        WinGetPos(&ax, &ay, &aw, &ah2, ah)
        WinGetPos(, , &gw, &gh, g.Hwnd)
        x := ax + (aw - gw) // 2
        y := ay + (ah2 - gh) // 2
        cx := ax + aw // 2
        cy := ay + ah2 // 2
        L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                L := ml, T := mt, R := mr, B := mb
                break
            }
        }
        x := Max(L, Min(x, R - gw))
        y := Max(T, Min(y, B - gh))
        g.Show("x" x " y" y)
    } catch
        g.Show(opts)
}

; themed check boxes for the list (state image list: 1 = off, 2 = on)
SetCheckImages(c) {
    try {
        GdipOn()
        file := DarkOn ? CbDarkFile : CbLightFile
        sz := Round(28 * A_ScreenDPI / 96)
        DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", file, "Ptr*", &src := 0)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", sz * 3, "Int", sz, "Int", 0, "Int", 0xE200B, "Ptr", 0, "Ptr*", &dst := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &gr := 0)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 2)
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", src, "Int", 0, "Int", 0, "Int", sz * 3, "Int", sz)
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm := 0, "UInt", 0)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
        il := DllCall("comctl32\ImageList_Create", "Int", sz, "Int", sz, "UInt", 0x20, "Int", 3, "Int", 0, "Ptr")
        DllCall("comctl32\ImageList_Add", "Ptr", il, "Ptr", hbm, "Ptr", 0)
        global CbIL, CbSz, CbDC, CbBmp
        if !CbDC
            CbDC := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        DllCall("SelectObject", "Ptr", CbDC, "Ptr", hbm, "Ptr")   ; kept for AlphaBlend (the image list can't blend it cleanly)
        if CbBmp
            DllCall("DeleteObject", "Ptr", CbBmp)                  ; the previous theme's bitmap is not used any more
        CbBmp := hbm
        CbIL := il, CbSz := sz
        old := SendMessage(0x1003, 2, il, c.Hwnd)          ; LVM_SETIMAGELIST, LVSIL_STATE
        if old
            DllCall("comctl32\ImageList_Destroy", "Ptr", old)
    }
}

; NM_CUSTOMDRAW of the list: every cell is painted here (own selection colours, check boxes, no focus rectangle)
OnLvDraw(ctrl, lp) {
    static ps := A_PtrSize
    stage := NumGet(lp, 24 - (ps = 8 ? 0 : 12), "UInt")
    if (stage = 1)
        return 0x30                                           ; CDRF_NOTIFYITEMDRAW | CDRF_NOTIFYPOSTPAINT
    if (stage = 2) {                                          ; post-paint: wipe whatever the theme drew below the last row
        hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
        cl := Buffer(16)
        DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", cl)
        n := SendMessage(0x1004, 0, 0, ctrl.Hwnd)             ; LVM_GETITEMCOUNT
        y0 := 0
        if n {
            ir := Buffer(16, 0)
            SendMessage(0x100E, n - 1, ir, ctrl.Hwnd)
            y0 := NumGet(ir, 12, "Int")
        }
        NumPut("Int", 0, "Int", y0, cl)
        br := DllCall("CreateSolidBrush", "UInt", DarkOn ? 0x27211F : 0xFFFFFF, "Ptr")
        DllCall("FillRect", "Ptr", hdc, "Ptr", cl, "Ptr", br)
        DllCall("DeleteObject", "Ptr", br)
        return 0
    }
    if (stage = 0x10001)
        return 0x20                                           ; CDRF_NOTIFYSUBITEMDRAW
    if (stage != 0x30001)
        return 0
    hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
    row := NumGet(lp, ps = 8 ? 56 : 36, "UPtr")               ; 0-based
    sub := NumGet(lp, ps = 8 ? 88 : 56, "Int")
    h := ctrl.Hwnd
    rc := Buffer(16, 0)
    SendMessage(0x100E, row, rc, h)                           ; LVM_GETITEMRECT (bounds of the row)
    top := NumGet(rc, 4, "Int"), bot := NumGet(rc, 12, "Int")
    cl := Buffer(16)
    DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
    cw := NumGet(cl, 8, "Int")
    x0 := 0
    loop sub
        x0 += SendMessage(0x101D, A_Index - 1, 0, h)          ; LVM_GETCOLUMNWIDTH
    w := SendMessage(0x101D, sub, 0, h)
    x1 := (sub = 3) ? Max(x0 + w, cw) : x0 + w
    st := SendMessage(0x102C, row, 0xF002, h)                 ; LVM_GETITEMSTATE
    sel := (st & 2) != 0
    if sel {
        bg := DarkOn ? 0x3A3626 : 0xF3E7C9
        fg := DarkOn ? 0xFFFFFF : 0x1B1B1F
    } else {
        bg := DarkOn ? 0x1F2127 : 0xFFFFFF
        fg := DarkOn ? 0xECECEF : 0x1B1B1F
    }
    bgr := ((bg & 0xFF) << 16) | (bg & 0xFF00) | (bg >> 16)
    fgr := ((fg & 0xFF) << 16) | (fg & 0xFF00) | (fg >> 16)
    r := Buffer(16)
    NumPut("Int", x0, "Int", top, "Int", x1, "Int", bot, r)
    br := DllCall("CreateSolidBrush", "UInt", bgr, "Ptr")
    DllCall("FillRect", "Ptr", hdc, "Ptr", r, "Ptr", br)
    DllCall("DeleteObject", "Ptr", br)
    tx := x0 + 8
    if (sub = 0) {
        if CbIL {
            idx := ((st >> 12) = 2) ? 2 : 1
            DllCall("msimg32\AlphaBlend", "Ptr", hdc, "Int", x0 + 2, "Int", top + (bot - top - CbSz) // 2, "Int", CbSz, "Int", CbSz
                , "Ptr", CbDC, "Int", idx * CbSz, "Int", 0, "Int", CbSz, "Int", CbSz, "UInt", 0x01FF0000)
        }
        tx := x0 + CbSz + 8
    }
    txt := ctrl.GetText(row + 1, sub + 1)
    font := SendMessage(0x31, 0, 0, h)
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    DllCall("SetTextColor", "Ptr", hdc, "UInt", fgr)
    NumPut("Int", tx, "Int", top, "Int", x1 - 6, "Int", bot, r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", txt, "Int", -1, "Ptr", r, "UInt", 0x8824)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    return 4                                                  ; CDRF_SKIPDEFAULT
}
