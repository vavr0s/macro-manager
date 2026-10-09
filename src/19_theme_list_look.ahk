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
    ApplyTheme(Main)
}

SetTheme(hwnd, name := "", sub := "") {
    if (name = "")
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Ptr", 0, "Ptr", 0)      ; back to the default theme
    else
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", name, "Ptr", sub = "" ? 0 : StrPtr(sub))
}

RoleColors(role, hover := false) {
    d := DarkOn
    switch role {
        case "btnprimary":
            return hover ? ["E3C486", "141414"] : ["D0AE6B", "141414"]
        case "btndanger":
            if d
                return hover ? ["55292F", "FFB4B4"] : ["3B2226", "FF9C9C"]
            return hover ? ["F1CBCB", "B3261E"] : ["F8E1E1", "B3261E"]
        case "btnghost":
            if d
                return hover ? ["1F2127", "ECECEF"] : ["15161A", "A9ADB8"]
            return hover ? ["E9E9EE", "1B1B1F"] : ["F5F5F7", "6A6A74"]
        case "btnbanner":
            return hover ? ["3A3E49", "E3C486"] : ["22242B", "D0AE6B"]
        case "btnupd0":
            return hover ? ["3A3E49", "B8BCC8"] : ["22242B", "6E7380"]
        case "btnupd1":
            return hover ? ["2E8A4F", "FFFFFF"] : ["1F5C34", "7DF0A0"]
        case "hdr":
            return d ? ["1F2127", "A9ADB8"] : ["E9E9EE", "5A5A66"]
        default:    ; plain button
            if d
                return hover ? ["3A3E49", "FFFFFF"] : ["2A2D35", "ECECEF"]
            return hover ? ["D6D6DE", "1B1B1F"] : ["E4E4EA", "1B1B1F"]
    }
}

; flat "button" = a clickable text control with its own colours (no system border)
AddBtn(g, opts, text, handler, role := "btn") {
    c := g.AddText(opts " +0x200" (InStr(opts, "Left") ? "" : " Center"), text)
    c.OnEvent("Click", handler)
    Roles[c.Hwnd] := role
    return c
}

PaintBtn(hwnd, hover) {
    try {
        c := GuiCtrlFromHwnd(hwnd)
        if !c
            return
        col := RoleColors(Roles[hwnd], hover)
        c.Opt("Background" col[1])
        c.SetFont("c" col[2])
        c.Redraw()
    }
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
                        col := RoleColors(role)
                        c.Opt("Background" col[1])
                        c.SetFont("s9 c" col[2])
                    } else
                        c.SetFont("c" (role = "hint" ? hint : txt))
                case "Edit":
                    c.Opt("Background" box)
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
    static gdip := 0
    try {
        if !gdip {
            si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", 1, si)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
            gdip := tok
        }
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
