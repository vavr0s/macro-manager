; ============ macro library: macros shared by other users - browse, rate, report, download, share ============
; The library is a small web service (server/ in the repository, Cloudflare). This install is known there only by
; a random id (LibId, its hash is stored): it lets you rate a macro once and delete the macros you shared.
; The panel sticks to the right side of the main window (to the left side when the screen has no room there).

LibInstall() {
    global LibId
    if !RegExMatch(LibId, "^[0-9a-f]{32}$") {
        buf := Buffer(16)
        DllCall("advapi32\SystemFunction036", "Ptr", buf, "UInt", 16)       ; RtlGenRandom
        LibId := ""
        loop 16
            LibId .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
        Save()
    }
    return LibId
}

; one request to the library: returns the answer (Map), with "error" when something went wrong
LibCall(method, path, body := "") {
    hdr := Map("X-MM-Install", LibInstall(), "Accept", "application/json")
    if IsObject(body)
        hdr["Content-Type"] := "application/json"
    r := HttpSend(LibApi path, hdr, 15000, false, method, IsObject(body) ? JsonStr(body) : "")
    if !r
        return Map("error", "network")
    j := 0
    try j := JsonParse(r["text"])
    if !(j is Map)
        j := Map("error", "status " r["status"])
    else if (r["status"] != 200 && !j.Has("error"))
        j["error"] := "status " r["status"]
    return j
}

LibErr(code) {
    switch code {
        case "network": return _T("Can't reach the macro library. Check your internet connection and try again.")
        case "too_many": return _T("You have shared a lot of macros today. Please try again tomorrow.")
        case "own_macro": return _T("You can't rate your own macro.")
        case "not_found": return _T("This macro is no longer in the library.")
        case "not_owner": return _T("Only the author can delete this macro.")
        case "bad_text": return _T("Please check the name, description and nickname.")
    }
    return _T("The library could not do this ({1}).", code)
}

; ---- the panel ----
ToggleLibrary(*) {
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        return CloseLibrary()
    OpenLibrary()
}

OpenLibrary() {
    global LibOpen
    if !LibGui
        BuildLibrary()
    LibOpen := true
    LibGui.Show("NA")                       ; (the first Show centres the window on the screen - placed right after)
    LibPlace()
    if !LibItems.Length
        LibLoad()
}

CloseLibrary(*) {
    global LibOpen
    LibOpen := false
    try LibGui.Hide()
}

; the panel follows the main window (WM_MOVE of the main window)
LibFollow(wp, lp, msg, hwnd) {
    if (LibGui && hwnd = Main.Hwnd && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        LibPlace()
}

; visible frame of the main window (without the invisible resize border of Windows 10 / 11)
MainFrame(&L, &T, &R, &B) {
    rc := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", Main.Hwnd, "UInt", 9, "Ptr", rc, "UInt", 16) {     ; DWMWA_EXTENDED_FRAME_BOUNDS
        WinGetPos(&x, &y, &w, &h, Main.Hwnd)
        NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rc)
    }
    L := NumGet(rc, 0, "Int"), T := NumGet(rc, 4, "Int"), R := NumGet(rc, 8, "Int"), B := NumGet(rc, 12, "Int")
}

LibPlace() {
    MainFrame(&L, &T, &R, &B)
    w := Round(LibW * A_ScreenDPI / 96) + 2
    ml := 0, mr := A_ScreenWidth
    loop MonitorGetCount() {                     ; (names differ from L T R B - AutoHotkey ignores the case of names)
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        if ((L + R) // 2 >= wl && (L + R) // 2 < wr && (T + B) // 2 >= wt && (T + B) // 2 < wb)
            ml := wl, mr := wr
    }
    x := (R + w <= mr || L - w < ml) ? R : L - w
    DllCall("SetWindowPos", "Ptr", LibGui.Hwnd, "Ptr", 0, "Int", x, "Int", T, "Int", w, "Int", B - T, "UInt", 0x14)   ; NOZORDER | NOACTIVATE
}

BuildLibrary() {
    global LibGui, LibLV, LibSearch, LibDesc, LibInfo, LibBtn
    MainFrame(&L, &T, &R, &B)
    W := LibW, H := Round((B - T - 2) * 96 / A_ScreenDPI)
    g := Gui("-Caption +Border +Owner" Main.Hwnd, _T("Macro library"))
    LibGui := g
    g.SetFont("s14 bold", "Segoe UI")
    AddBtn(g, "x8 y8 w" (W - 16) " h48 Left", "   " _T("Macro library"), (*) => 0, "libhead")
    g.SetFont("s15 norm", "Segoe UI")
    AddBtn(g, "x" (W - 48) " y16 w32 h32", Chr(0xD7), CloseLibrary, "btnbanner")
    g.SetFont("s9 norm", "Segoe UI")
    LibSearch := g.AddEdit("x8 y66 w" (W - 222) " h26")
    SendMessage(0x1501, 1, StrPtr(_T("Search macros")), LibSearch)
    LibSearch.OnEvent("Change", (*) => SetTimer(LibLoad, -600))
    LibBtn := Map()
    LibBtn["sort"] := AddBtn(g, "x" (W - 208) " y66 w156 h26", LibSortText(), LibSortMenu)
    g.SetFont("s10 norm", "Segoe MDL2 Assets")
    AddBtn(g, "x" (W - 46) " y66 w38 h26", Chr(0xE72C), (*) => LibLoad())          ; refresh
    g.SetFont("s9 norm", "Segoe UI")
    yBot := H - 40, yBtn := yBot - 40, yInfo := yBtn - 24, yDesc := yInfo - 70
    LibLV := g.AddListView("x8 y100 w" (W - 16) " h" (yDesc - 108) " -Hdr -E0x200 -Multi", [""])
    LibLV.SetFont("s10")
    LibLV.Opt("+LV0x10020")                                     ; double buffer, full-row select
    LibLV.ModifyCol(1, (W - 16) * A_ScreenDPI / 96 - 24)
    il := DllCall("comctl32\ImageList_Create", "Int", 1, "Int", Round(52 * A_ScreenDPI / 96), "UInt", 0x20, "Int", 1, "Int", 0, "Ptr")
    SendMessage(0x1003, 1, il, LibLV.Hwnd)                       ; LVM_SETIMAGELIST, LVSIL_SMALL: sets the row height
    LibLV.OnNotify(-12, LibDraw)
    LibLV.OnEvent("ItemSelect", (*) => LibShowSel())
    LibLV.OnEvent("DoubleClick", (*) => LibDownload())
    SendMessage(0x127, 0x10001, 0, LibLV.Hwnd)
    LibDesc := g.AddEdit("x8 y" yDesc " w" (W - 16) " h64 Multi ReadOnly", "")
    LibInfo := AddHint(g, "x8 y" yInfo " w" (W - 16) " h20", "")
    LibBtn["dl"] := AddBtn(g, "x8 y" yBtn " w130 h32", _T("Download"), (*) => LibDownload(), "btnprimary")
    LibBtn["rate"] := AddBtn(g, "x+8 yp w110 h32", _T("Rate") "  ▾", LibRateMenu)
    LibBtn["report"] := AddBtn(g, "x+8 yp w90 h32", _T("Report"), (*) => LibReport())
    LibBtn["del"] := AddBtn(g, "x+8 yp w" (W - 370) " h32", _T("Delete"), (*) => LibDelete(), "btndanger")
    LibBtn["share"] := AddBtn(g, "x8 y" yBot " w250 h32", _T("Share selected macro..."), (*) => LibShare())
    LibBtn["more"] := AddBtn(g, "x" (W - 138) " y" yBot " w130 h32", _T("Load more"), (*) => LibLoad(true), "btnghost")
    ; hidden: fonts for the rows (asked for at every paint - re-theming makes new ones)
    g.SetFont("s10 bold", "Segoe UI")
    LibBtn["fontB"] := g.AddText("x-900 y-900 w10 h10", "")
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn["fontS"] := g.AddText("x-900 y-900 w10 h10", "")
    g.OnEvent("Escape", CloseLibrary)
    g.OnEvent("Close", CloseLibrary)
    ApplyTheme(g)
    LibShowSel()
}

LibSortText() => (LibSort = "new" ? _T("Newest") : LibSort = "dl" ? _T("Most downloaded") : _T("Top rated")) "  ▾"

LibSortMenu(ctrl, *) {
    m := Menu()
    for o in [["top", _T("Top rated")], ["new", _T("Newest")], ["dl", _T("Most downloaded")]] {
        m.Add(o[2], LibSetSort.Bind(o[1]))
        if (o[1] = LibSort)
            m.Check(o[2])
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibSetSort(k, *) {
    global LibSort
    LibSort := k
    LibBtn["sort"].Text := LibSortText()
    PaintBtn(LibBtn["sort"].Hwnd, false)
    LibLoad()
}

; (re)loads the list from the library; append = the next page ("Load more")
LibLoad(append := false) {
    global LibItems, LibMore, LibBusy
    if (!LibGui || LibBusy)
        return
    LibBusy := true
    LibInfo.Text := _T("Loading...")
    off := append ? LibItems.Length : 0
    j := LibCall("GET", "?sort=" LibSort "&offset=" off "&q=" UriEnc(Trim(LibSearch.Value)))
    LibBusy := false
    if j.Has("error") {
        LibInfo.Text := LibErr(j["error"])
        return
    }
    if !append
        LibItems := []
    for it in j["items"]
        LibItems.Push(it)
    LibMore := j["more"]
    LibLV.Opt("-Redraw")
    LibLV.Delete()
    for it in LibItems
        LibLV.Add(, it["name"])
    LibLV.Opt("+Redraw")
    LibShowSel()
    if !LibItems.Length
        LibInfo.Text := Trim(LibSearch.Value) = "" ? _T("The library is empty so far - share the first macro!") : _T("No macros found.")
}

LibSel() {
    r := LibLV.GetNext(0)
    return (r && r <= LibItems.Length) ? LibItems[r] : 0
}

; description, details and buttons of the selected macro
LibShowSel() {
    it := LibSel()
    LibBtn["more"].Visible := LibMore
    for k in ["dl", "rate", "report"]
        LibBtn[k].Enabled := !!it
    LibBtn["del"].Visible := it && it["mine"]
    LibBtn["rate"].Enabled := it && !it["mine"]
    for k in ["dl", "rate", "report", "del"]
        PaintBtn(LibBtn[k].Hwnd, false)
    if !it {
        LibDesc.Value := ""
        LibInfo.Text := LibItems.Length ? _T("Pick a macro to see its description.") : ""
        return
    }
    LibDesc.Value := it["descr"] = "" ? _T("(no description)") : StrReplace(it["descr"], "`n", "`r`n")
    t := TypeLabel(it["type"]) "  ·  " _T("Key") ": " (it["hotkey"] = "" ? Chr(0x2014) : it["hotkey"])
    t .= "  ·  " _T("by {1}", it["author"])
    if it["mine"]
        t .= "  ·  " _T("your macro")
    else if it["my"]
        t .= "  ·  " _T("your rating: {1}", it["my"]) Chr(0x2605)
    LibInfo.Text := t
}

; ---- one row: name (bold), stars + (number of ratings) + author below; key and downloads on the right ----
LibDraw(ctrl, lp) {
    static ps := A_PtrSize
    stage := NumGet(lp, 24 - (ps = 8 ? 0 : 12), "UInt")
    hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
    h := ctrl.Hwnd
    if (stage = 1)
        return 0x30                                             ; items + post-paint
    if (stage = 2) {                                            ; below the last row: the list colour
        cl := Buffer(16)
        DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
        n := SendMessage(0x1004, 0, 0, h)
        if n {
            ir := Buffer(16, 0)
            SendMessage(0x100E, n - 1, ir, h)
            NumPut("Int", NumGet(ir, 12, "Int"), cl, 4)
        }
        FillHex(hdc, 0, NumGet(cl, 4, "Int"), NumGet(cl, 8, "Int"), NumGet(cl, 12, "Int") - NumGet(cl, 4, "Int"), DarkOn ? "1F2127" : "FFFFFF")
        return 0
    }
    if (stage != 0x10001)
        return 0
    row := NumGet(lp, ps = 8 ? 56 : 36, "UPtr")
    if (row >= LibItems.Length)
        return 4
    it := LibItems[row + 1]
    s := A_ScreenDPI / 96
    rc := Buffer(16, 0)
    SendMessage(0x100E, row, rc, h)                             ; LVM_GETITEMRECT
    top := NumGet(rc, 4, "Int"), bot := NumGet(rc, 12, "Int")
    cl := Buffer(16)
    DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
    cw := NumGet(cl, 8, "Int")
    sel := (SendMessage(0x102C, row, 2, h) & 2) != 0
    bg := sel ? (DarkOn ? "3A3626" : "F3E7C9") : (DarkOn ? "1F2127" : "FFFFFF")
    fg := DarkOn ? "ECECEF" : "1B1B1F"
    hint := DarkOn ? "A9ADB8" : "6A6A74"
    FillHex(hdc, 0, top, cw, bot - top, bg)
    FillHex(hdc, Round(8 * s), bot - 1, cw - Round(16 * s), 1, DarkOn ? "2A2D35" : "ECECF0")     ; separator
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    r := Buffer(16)
    rw := Round(96 * s)                                         ; right column
    ; name
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, LibBtn["fontB"]), "Ptr")
    DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr(fg))
    NumPut("Int", Round(10 * s), "Int", top + Round(5 * s), "Int", cw - rw - Round(8 * s), "Int", top + Round(27 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", it["name"], "Int", -1, "Ptr", r, "UInt", 0x8824)
    ; key (right, top)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, LibBtn["fontS"]), "Ptr")
    DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr(hint))
    NumPut("Int", cw - rw, "Int", top + Round(5 * s), "Int", cw - Round(10 * s), "Int", top + Round(27 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", it["hotkey"] = "" ? Chr(0x2014) : it["hotkey"], "Int", -1, "Ptr", r, "UInt", 0x8826)
    ; downloads (right, bottom)
    NumPut("Int", cw - rw, "Int", top + Round(27 * s), "Int", cw - Round(10 * s), "Int", top + Round(48 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", Chr(0x2193) " " it["downloads"], "Int", -1, "Ptr", r, "UInt", 0x8826)
    ; stars: the average rounded to quarters of a star
    sz := 14 * s, x := 10 * s, cy := top + 37.5 * s
    q := Round(it["rating"] * 4) / 4
    if GdipOn() {
        gr := GrOn(hdc)
        loop 5 {
            cx := x + sz / 2 + (A_Index - 1) * (sz + 2 * s)
            LibStar(gr, cx, cy, sz / 2, DarkOn ? "3A3E49" : "D3D3DB")
            f := Min(1, Max(0, q - (A_Index - 1)))
            if (f > 0) {
                DllCall("gdiplus\GdipSetClipRect", "Ptr", gr, "Float", cx - sz / 2, "Float", cy - sz / 2, "Float", sz * f, "Float", sz, "Int", 0)
                LibStar(gr, cx, cy, sz / 2, "D0AE6B")
                DllCall("gdiplus\GdipResetClip", "Ptr", gr)
            }
        }
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    }
    ; (number of ratings) and the author
    tx := Round(x + 5 * (sz + 2 * s) + 4 * s)
    NumPut("Int", tx, "Int", top + Round(27 * s), "Int", cw - rw - Round(8 * s), "Int", top + Round(48 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", "(" it["count"] ")   " _T("by {1}", it["author"]), "Int", -1, "Ptr", r, "UInt", 0x8824)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    return 4                                                    ; CDRF_SKIPDEFAULT
}

; five-pointed star around (cx, cy)
LibStar(gr, cx, cy, ro, hex) {
    pts := Buffer(80)
    loop 10 {
        a := (-90 + (A_Index - 1) * 36) * 0.017453292519943
        rr := Mod(A_Index, 2) ? ro : ro * 0.45
        NumPut("Float", cx + rr * Cos(a), "Float", cy + rr * Sin(a), pts, (A_Index - 1) * 8)
    }
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)
    DllCall("gdiplus\GdipAddPathPolygon", "Ptr", pa, "Ptr", pts, "Int", 10)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" hex), "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; ---- actions ----
; the selected macro goes into the current profile, switched off (the user checks the key and turns it on)
LibDownload() {
    global LibBusy
    it := LibSel()
    if (!it || LibBusy)
        return
    LibBusy := true
    j := LibCall("POST", "/" it["id"] "/download", Map())
    LibBusy := false
    if j.Has("error")
        return ThemedNote(LibErr(j["error"]), , true)
    d := j.Has("data") ? j["data"] : 0
    if !(d is Map && d.Has("type") && (d["type"] = "move" || d["type"] = "seq"))      ; never a script from the library
        return ThemedNote(LibErr("bad_macro"), , true)
    m := Defaults()
    for k in ["type", "hotkey", "app", "dirs", "actions", "seq", "press", "g1", "g2", "g3", "ge", "repeat", "exact"]
        if d.Has(k)
            m[k] := (k ~= "^(g\d|ge|repeat|exact)$") ? Integer(Num(d[k])) : String(d[k])
    if (Trim(m["hotkey"]) = "")
        m["hotkey"] := "undefined"
    m["name"] := LibFreeName(j["name"])
    m["profiles"] := CurProfile
    m["enabled"] := 0
    m["tkey"] := "", m["file"] := "", m["trusted"] := 1
    Macros.Push(m)
    Save()
    Refresh()
    for i, v in View
        if (v == m)
            LV.Modify(i, "Select Focus Vis")
    if (j.Has("counted") && j["counted"]) {                     ; first download from this install
        it["downloads"] += 1
        LibLV.Modify(LibLV.GetNext(0), , it["name"])
    }
    Toast(_T("`"{1}`" added to profile {2} - switched off, tick it to turn it on.", m["name"], CurProfile), 3000)
}

LibFreeName(base) {
    base := CleanName(base) = "" ? _T("Downloaded macro") : CleanName(base)
    nm := base, n := 1
    loop {
        taken := false
        for m in Macros
            if (m["name"] = nm)
                taken := true
        if !taken
            return nm
        nm := base " (" n++ ")"
    }
}

LibRateMenu(ctrl, *) {
    it := LibSel()
    if (!it || it["mine"])
        return
    m := Menu()
    loop 5 {
        n := 6 - A_Index
        label := StrReplace(Format("{:" n "}", ""), " ", Chr(0x2605)) StrReplace(Format("{:" (5 - n) "}", ""), " ", Chr(0x2606)) "   " n
        m.Add(label, LibRate.Bind(n))
        if (it["my"] = n)
            m.Check(label)
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibRate(n, *) {
    it := LibSel()
    if !it
        return
    j := LibCall("POST", "/" it["id"] "/rate", Map("stars", n))
    if j.Has("error")
        return ThemedNote(LibErr(j["error"]), , true)
    it["rating"] := j["rating"], it["count"] := j["count"], it["my"] := j["my"]
    LibLV.Modify(LibLV.GetNext(0), , it["name"])                ; repaint the row
    LibShowSel()
    Toast(_T("Thank you for rating!"))
}

LibReport() {
    it := LibSel()
    if !it
        return
    why := ThemedInput(_T("Report macro"), _T("Why should `"{1}`" be removed from the library? For example: a farm / AFK macro (not allowed), it does not work, or spam.", it["name"]))
    if (why = false || Trim(why) = "")
        return
    j := LibCall("POST", "/" it["id"] "/report", Map("reason", SubStr(Trim(why), 1, 200)))
    if j.Has("error")
        return ThemedNote(LibErr(j["error"]), , true)
    ThemedNote(_T("Thank you. The macro will be checked."))
}

LibDelete() {
    it := LibSel()
    if (!it || !it["mine"])
        return
    if (ThemedAsk(_T("Macro library"), _T("Delete from the library?"), _T("`"{1}`" will be removed from the library for everyone, with its ratings. Your own copy in the list stays.", it["name"]), [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
        return
    j := LibCall("DELETE", "/" it["id"])
    if j.Has("error")
        return ThemedNote(LibErr(j["error"]), , true)
    LibLoad()
}

; ---- sharing the macro selected in the main list ----
LibShare() {
    global LibAuthor, LibSort
    sel := SelMacros()
    if (sel.Length != 1)
        return ThemedNote(_T("Select one macro in the list of the main window first, then press Share."))
    m := sel[1]
    if (m["type"] = "script")
        return ThemedNote(_T("Script macros can't be shared - only Move + actions and Sequence macros."), , true)
    f := LibShareForm(m)
    if !f
        return
    j := LibCall("POST", "", Map("name", f["name"], "descr", f["descr"], "author", f["author"], "data", LibData(m)))
    if j.Has("error")
        return ThemedNote(LibErr(j["error"]), , true)
    LibAuthor := f["author"]
    Save()
    LibSort := "new"
    LibBtn["sort"].Text := LibSortText()
    PaintBtn(LibBtn["sort"].Hwnd, false)
    LibSearch.Value := ""
    LibLoad()
    ThemedNote(_T("Thank you for sharing! `"{1}`" is now in the library.", f["name"]))
}

; what is shared of a macro (not its toggle key, profiles or on / off state)
LibData(m) {
    d := Map()
    for k in ["type", "hotkey", "app", "dirs", "actions", "seq"]
        d[k] := String(m[k])
    for k in ["g1", "g2", "g3", "ge", "repeat", "exact"]
        d[k] := Integer(Num(m[k]))
    d["press"] := PressOf(m)
    if (Trim(d["hotkey"]) = "undefined")
        d["hotkey"] := ""
    return d
}

; name, description and nickname for sharing; returns a Map or false
LibShareForm(m) {
    res := false, done := false
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Share macro"))
    g.SetFont("s10 bold", "Segoe UI")
    DlgText(g, "x16 y14 w388", _T("Share `"{1}`" in the macro library", m["name"]))
    g.SetFont("s9 norm", "Segoe UI")
    g.AddText("x16 y48 w388", _T("Name"))
    eN := g.AddEdit("x16 y66 w388 h26 Limit40", m["name"])
    g.AddText("x16 y100 w388", _T("Description (optional): what it does, for which game / class"))
    eD := g.AddEdit("x16 y118 w388 h70 Multi Limit300", "")
    g.AddText("x16 y196 w388", _T("Your nickname"))
    eA := g.AddEdit("x16 y214 w388 h26 Limit24", LibAuthor)
    hc := DlgText(g, "x16 y250 w388", _T("Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."))
    Roles[hc.Hwnd] := "hint"
    hc.GetPos(, &hy, , &hh)
    btnY := hy + hh + 16
    Ok(*) {
        nm := Trim(eN.Value), au := Trim(eA.Value)
        if (nm = "" || au = "") {
            ThemedNote(_T("Please fill in the name and your nickname."), , true)
            return
        }
        res := Map("name", nm, "descr", Trim(StrReplace(eD.Value, "`r", "")), "author", au)
        Close()
    }
    Close(*) {
        if done
            return
        done := true
        if oh
            DllCall("EnableWindow", "Ptr", oh, "Int", 1)
        g.Destroy()
    }
    AddBtn(g, "x194 y" btnY " w100 h32", _T("Share"), Ok, "btnprimary")
    AddBtn(g, "x304 y" btnY " w100 h32", _T("Cancel"), Close)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w420 h" (btnY + 46), oh)
    if (LibAuthor = "")
        eA.Focus()
    else
        eD.Focus()
    while !done
        Sleep 50
    return res
}

; ---- JSON (answers of the library) ----
JsonParse(s) {
    i := 1
    return JsonVal(s, &i)
}

JsonVal(s, &i) {
    JsonWs(s, &i)
    c := SubStr(s, i, 1)
    if (c = "{" || c = "[") {
        obj := c = "{" ? Map() : []
        end := c = "{" ? "}" : "]"
        i++
        JsonWs(s, &i)
        if (SubStr(s, i, 1) = end) {
            i++
            return obj
        }
        loop {
            if (end = "}") {
                k := JsonVal(s, &i)
                JsonWs(s, &i)
                if (SubStr(s, i++, 1) != ":")
                    throw Error("json")
                obj[k] := JsonVal(s, &i)
            } else
                obj.Push(JsonVal(s, &i))
            JsonWs(s, &i)
            c := SubStr(s, i++, 1)
            if (c = end)
                return obj
            if (c != ",")
                throw Error("json")
        }
    }
    if (c = '"') {
        if !RegExMatch(s, '\G"((?:[^"\\]|\\.)*)"', &mm, i)
            throw Error("json")
        i += mm.Len
        return JsonUnesc(mm[1])
    }
    if RegExMatch(s, "\G-?\d+(\.\d+)?([eE][-+]?\d+)?", &mm, i) {
        i += mm.Len
        return (mm[1] = "" && mm[2] = "") ? Integer(mm[0]) : Float(mm[0])
    }
    for w, v in Map("true", 1, "false", 0, "null", "") {
        if (SubStr(s, i, StrLen(w)) == w) {
            i += StrLen(w)
            return v
        }
    }
    throw Error("json")
}

JsonWs(s, &i) {
    while (i <= StrLen(s) && InStr(" `t`r`n", SubStr(s, i, 1)))
        i++
}

; JSON text of a Map / Array / number / string; every letter outside plain ASCII as \uXXXX
JsonStr(v) {
    if (v is Map) {
        t := ""
        for k, x in v
            t .= (t = "" ? "" : ",") JsonStr(String(k)) ":" JsonStr(x)
        return "{" t "}"
    }
    if (v is Array) {
        t := ""
        for x in v
            t .= (A_Index = 1 ? "" : ",") JsonStr(x)
        return "[" t "]"
    }
    if (v is Number)
        return String(v)
    out := '"', p := StrPtr(v)
    loop StrLen(v) {
        o := NumGet(p, (A_Index - 1) * 2, "UShort")
        out .= o = 34 ? '\"' : o = 92 ? "\\" : o = 10 ? "\n" : o = 13 ? "\r" : o = 9 ? "\t"
            : (o < 32 || o > 126) ? Format("\u{:04x}", o) : Chr(o)
    }
    return out '"'
}

; text for a URL query (UTF-8, %XX)
UriEnc(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    n := StrPut(s, buf, "UTF-8") - 1
    out := ""
    loop n {
        b := NumGet(buf, A_Index - 1, "UChar")
        out .= (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b = 45 || b = 46 || b = 95 || b = 126 ? Chr(b) : Format("%{:02X}", b)
    }
    return out
}
