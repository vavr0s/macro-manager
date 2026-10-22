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
LibCall(method, path, body := "", url := "") {
    hdr := Map("X-MM-Install", LibInstall(), "Accept", "application/json")
    if IsObject(body)
        hdr["Content-Type"] := "application/json"
    r := HttpSend(url != "" ? url : LibApi path, hdr, 10000, false, method, IsObject(body) ? JsonStr(body) : "")
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
        case "network": return _T("Can't reach Macro Hub. Check your internet connection and try again.")
        case "too_many": return _T("You have shared a lot of macros today. Please try again tomorrow.")
        case "own_macro": return _T("You can't rate your own macro.")
        case "not_found": return _T("This macro is no longer in Macro Hub.")
        case "not_owner": return _T("Only the author can delete this macro.")
        case "bad_text": return _T("Please check the name, game, description and nickname.")
    }
    return _T("Macro Hub could not do this ({1}).", code)
}

; game tags used in the library, the most used first (for the game filter and the share form)
LibGamesLoad(j := 0) {
    global LibGames
    if !j
        j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "games"))
    if (!j.Has("error") && j.Has("games")) {
        LibGames := []
        for g in j["games"]
            LibGames.Push(g)
    }
    return LibGames
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
    SetTimer(() => LibCheckUpdates(), -1000)
    if !LibItems.Length {
        LibLoad()
        if (LibWho != "mine") {             ; once: which macros of the list are shared (share icons)
            j := LibCall("GET", "?who=mine&sort=new")
            if !j.Has("error")
                LibSyncShared(j["items"], !j["more"])
        }
    }
}

; marks the macros of the list that are in the library (gold share icon) by comparing what is shared;
; complete = these are all my shared macros: a macro whose library entry is gone loses the mark
LibSyncShared(items, complete) {
    ids := Map(), byData := Map()
    for it in items {
        ids[String(it["id"])] := it
        if it.Has("data")
            byData[JsonStr(it["data"])] := it["id"]
    }
    changed := false
    for m in Macros {
        if (m["type"] = "script")
            continue
        if (m["libshare"] = "") {
            k := JsonStr(LibData(m))
            if byData.Has(k)
                m["libshare"] := byData[k], m["libsharehash"] := LibHash(m), changed := true
        } else if (complete && !ids.Has(String(m["libshare"])))
            m["libshare"] := "", m["libsharehash"] := "", changed := true
        else if (m["libsharehash"] = "" && ids.Has(String(m["libshare"])) && ids[String(m["libshare"])].Has("data"))
            m["libsharehash"] := LibHashData(ids[String(m["libshare"])]["data"]), changed := true    ; shared before 1.22.7
    }
    if changed {
        Save()
        RedrawList()
    }
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
    LibFit(B - T)
}

; the main window has another height (for example after the language changed): the list of the panel too, the parts below it move
LibFit(h) {
    global LibH
    d := h - LibH
    LibH := h
    if !d
        return
    ControlGetPos(, &ly, , &lh, LibLV)
    for hwnd, c in LibGui {
        ControlGetPos(&cx, &cy, , , c)
        if (cy > ly + 4 && cy > -500 && !LibOff.Has(hwnd))  ; (hidden font controls and the "no connection" parts stay)
            ControlMove(, cy + d, , , c)
    }
    ControlMove(, , , lh + d, LibLV)
    DllCall("RedrawWindow", "Ptr", LibGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)     ; no copies of moved buttons left behind
    if LibIsOff
        LibOffline(true)                                    ; centred again in the new list area
}

; ---- no internet: instead of the list, a "No connection" sign in the middle; tried again every 15 seconds ----
LibOffline(on) {
    global LibIsOff
    if !LibGui
        return
    LibIsOff := on
    LibLV.Visible := !on
    if on {
        ControlGetPos(&lx, &ly, &lw, &lh, LibLV)
        s := A_ScreenDPI / 96
        top := ly + Max(0, (lh - Round(190 * s)) // 2)
        for hwnd, c in LibOff {
            k := c.Name
            ControlGetPos(, , &cw, &ch, c)
            y := top + Round((k = "pic" ? 0 : k = "ttl" ? 86 : k = "sub" ? 120 : 158) * s)
            ControlMove(lx + (lw - cw) // 2, y, , , c)
        }
        SetTimer(LibRetry, 15000)
    } else
        SetTimer(LibRetry, 0)
    for hwnd, c in LibOff
        c.Visible := on
    if on
        LibInfo.Text := ""
}

LibRetry(*) {
    if (!LibGui || !DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        return SetTimer(LibRetry, 0)
    LibLoad()
}

; an action failed: no internet = the panel shows it too
LibFail(j) {
    if (j["error"] = "network")
        LibOffline(true)
    ThemedNote(LibErr(j["error"]), , true)
}

; the "!" in a circle (gold, transparent) for the "No connection" sign - drawn once into the assets folder
LibOfflinePng() {
    f := AssetsDir "\offline.png"
    if (FileExist(f) || !GdipOn())
        return f
    sz := 96
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", sz, "Int", sz, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &gr := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)
    DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFD0AE6B, "Float", 7, "Int", 2, "Ptr*", &pen := 0)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", gr, "Ptr", pen, "Float", 5, "Float", 5, "Float", sz - 10, "Float", sz - 10)
    FillRound(gr, sz / 2 - 5, 22, 10, 36, 10, "D0AE6B")         ; the bar of the "!"
    FillRound(gr, sz / 2 - 6, 64, 12, 12, 12, "D0AE6B")         ; its dot
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)    ; PNG encoder
    DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "WStr", f, "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    return f
}

; Macro Hub can be reached (also loads the games for the share form)
LibOnline() {
    j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "games"))
    if (j.Has("error") && j["error"] = "network")
        return false
    LibGamesLoad(j)
    return true
}

BuildLibrary() {
    global LibGui, LibLV, LibSearch, LibDesc, LibInfo, LibBtn, LibH
    MainFrame(&L, &T, &R, &B)
    LibH := B - T                                           ; the height the layout is made for (LibFit)
    W := LibW, H := Round((B - T - 2) * 96 / A_ScreenDPI)
    g := Gui("-Caption +Border +Owner" Main.Hwnd, _T("Macro Hub"))
    LibGui := g
    ; title strip: drawn like a button (DrawBtn) but without click events, so clicks reach the close button on it
    g.SetFont("s14 bold", "Segoe UI")
    hd := g.AddText("x8 y8 w" (W - 16) " h48 +0xD", "   " _T("Macro Hub"))
    Roles[hd.Hwnd] := "libhead"
    BtnLook[hd.Hwnd] := {left: true, round: true, hover: false, badge: false, pad: [0, 0, 0, 0]}
    g.SetFont("s15 norm", "Segoe UI")
    AddBtn(g, "x" (W - 48) " y16 w32 h32", Chr(0xD7), CloseLibrary, "btnbanner")
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn := Map()
    tw := (W - 24) // 2                                         ; tabs: macros of other players / my shared macros
    LibBtn["others"] := AddBtn(g, "x8 y64 w" tw " h30", _T("Players' macros"), (*) => LibSetWho("others"))
    LibBtn["mine"] := AddBtn(g, "x" (16 + tw) " y64 w" tw " h30", _T("My macros"), (*) => LibSetWho("mine"))
    LibSearch := g.AddEdit("x8 y102 w" (W - 62) " h26")
    SendMessage(0x1501, 1, StrPtr(_T("Search: name, game or author")), LibSearch)
    LibSearch.OnEvent("Change", (*) => SetTimer(LibLoad, -600))
    g.SetFont("s10 norm", "Segoe MDL2 Assets")
    AddBtn(g, "x" (W - 46) " y102 w38 h26", Chr(0xE72C), (*) => LibLoad())         ; refresh
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn["game"] := AddBtn(g, "x8 y134 w" (W - 180) " h26", LibGameText(), LibGameMenu)
    LibBtn["sort"] := AddBtn(g, "x" (W - 164) " y134 w156 h26", LibSortText(), LibSortMenu)
    yBtn := H - 40, yInfo := yBtn - 26, yDesc := yInfo - 128
    LibLV := g.AddListView("x8 y168 w" (W - 16) " h" (yDesc - 176) " -Hdr -E0x200 -Multi", [""])
    LibLV.SetFont("s10")
    LibLV.Opt("+LV0x10020")                                     ; double buffer, full-row select
    LibLV.ModifyCol(1, (W - 16) * A_ScreenDPI / 96 - 24)
    il := DllCall("comctl32\ImageList_Create", "Int", 1, "Int", Round(52 * A_ScreenDPI / 96), "UInt", 0x20, "Int", 1, "Int", 0, "Ptr")
    SendMessage(0x1003, 1, il, LibLV.Hwnd)                       ; LVM_SETIMAGELIST, LVSIL_SMALL: sets the row height
    LibLV.OnNotify(-12, LibDraw)
    LibLV.OnEvent("ItemSelect", (*) => LibShowSel())
    LibLV.OnEvent("DoubleClick", (*) => LibDownload())
    SendMessage(0x127, 0x10001, 0, LibLV.Hwnd)
    ; "No connection" sign, shown instead of the list (LibOffline places it in the middle)
    p := g.AddPicture("vpic x0 y0 w64 h64 Hidden BackgroundTrans", LibOfflinePng())
    g.SetFont("s14 bold", "Segoe UI")
    t1 := g.AddText("vttl x0 y0 w" (W - 40) " Center Hidden", _T("No connection"))
    g.SetFont("s9 norm", "Segoe UI")
    t2 := AddHint(g, "vsub x0 y0 w" (W - 40) " h34 Center Hidden", _T("Macro Hub needs the internet. It tries again by itself every few seconds."))
    b := AddBtn(g, "vbtn x0 y0 w130 h30 Hidden", _T("Try again"), (*) => LibLoad(), "btnprimary")
    for c in [p, t1, t2, b]
        LibOff[c.Hwnd] := c
    LibDesc := g.AddEdit("x8 y" yDesc " w" (W - 16) " h122 Multi ReadOnly", "")     ; description + what the macro does
    LibInfo := AddHint(g, "x8 y" yInfo " w" (W - 126) " h20", "")
    LibBtn["more"] := AddBtn(g, "x" (W - 112) " y" (yInfo - 3) " w104 h24", _T("Load more"), (*) => LibLoad(true), "btnghost")
    LibBtn["dl"] := AddBtn(g, "x8 y" yBtn " w130 h32", _T("Download"), (*) => LibDownload(), "btnprimary")
    LibBtn["rate"] := AddBtn(g, "x+8 yp w110 h32", _T("Rate") "  ▾", LibRateMenu)
    LibBtn["report"] := AddBtn(g, "x+8 yp w90 h32", _T("Report"), (*) => LibReport())
    LibBtn["del"] := AddBtn(g, "x+8 yp w" (W - 370) " h32", _T("Delete"), (*) => LibDelete(), "btndanger")
    ; hidden: fonts for the rows (asked for at every paint - re-theming makes new ones)
    g.SetFont("s10 bold", "Segoe UI")
    LibBtn["fontB"] := g.AddText("x-900 y-900 w10 h10", "")
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn["fontS"] := g.AddText("x-900 y-900 w10 h10", "")
    g.OnEvent("Escape", CloseLibrary)
    g.OnEvent("Close", CloseLibrary)
    ApplyTheme(g)
    LibTabs()
    LibShowSel()
}

; ---- tabs, game filter, sort ----
LibTabs() {
    for k in ["others", "mine"] {
        Roles[LibBtn[k].Hwnd] := (k = LibWho) ? "btnprimary" : "btn"
        PaintBtn(LibBtn[k].Hwnd, false)
    }
}

LibSetWho(who) {
    global LibWho
    if (who = LibWho)
        return
    LibWho := who
    LibTabs()
    LibLoad()
}

LibGameText() => (LibGameF = "" ? _T("All games") : _T("Game: {1}", LibGameF)) "  ▾"

LibGameMenu(ctrl, *) {
    m := Menu()
    m.Add(_T("All games"), LibSetGame.Bind(""))
    if (LibGameF = "")
        m.Check(_T("All games"))
    games := LibGamesLoad()
    if games.Length
        m.Add()
    for g in games {
        label := g["game"] "   (" g["count"] ")"
        m.Add(label, LibSetGame.Bind(g["game"]))
        if (g["game"] = LibGameF)
            m.Check(label)
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibSetGame(game, *) {
    global LibGameF
    LibGameF := game
    LibBtn["game"].Text := LibGameText()
    PaintBtn(LibBtn["game"].Hwnd, false)
    LibLoad()
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
    if !LibIsOff                                            ; (while "No connection" shows, it just tries again quietly)
        LibInfo.Text := _T("Loading...")
    off := append ? LibItems.Length : 0
    j := LibCall("GET", "?who=" LibWho "&sort=" LibSort "&offset=" off "&game=" UriEnc(LibGameF) "&q=" UriEnc(Trim(LibSearch.Value)))
    LibBusy := false
    if j.Has("error") {
        if (j["error"] = "network")
            return LibOffline(true)
        LibInfo.Text := LibErr(j["error"])
        return
    }
    if LibIsOff
        LibOffline(false)                                   ; back online
    if !append
        LibItems := []
    for it in j["items"]
        LibItems.Push(it)
    LibMore := j["more"]
    if (LibWho = "mine" && !append && Trim(LibSearch.Value) = "" && LibGameF = "")
        LibSyncShared(LibItems, !LibMore)
    LibLV.Opt("-Redraw")
    LibLV.Delete()
    for it in LibItems
        LibLV.Add(, it["name"])
    LibLV.Opt("+Redraw")
    LibShowSel()
    if !LibItems.Length
        LibInfo.Text := LibWho = "mine" ? _T("You have not shared any macro yet - use the share icon in your list.")
            : (Trim(LibSearch.Value) = "" && LibGameF = "") ? _T("Macro Hub is empty so far - share the first macro!") : _T("No macros found.")
}

LibSel() {
    r := LibLV.GetNext(0)
    return (r && r <= LibItems.Length) ? LibItems[r] : 0
}

; description, details and buttons of the selected macro
LibShowSel() {
    it := LibSel()
    LibBtn["more"].Visible := LibMore
    mineTab := (LibWho = "mine")
    LibBtn["dl"].Enabled := !!it
    LibBtn["rate"].Visible := LibBtn["report"].Visible := !mineTab        ; own macros: download back or delete
    LibBtn["rate"].Enabled := it && !it["mine"]
    LibBtn["report"].Enabled := !!it
    LibBtn["del"].Visible := it && it["mine"]
    for k in ["dl", "rate", "report", "del"]
        PaintBtn(LibBtn[k].Hwnd, false)
    if !it {
        LibDesc.Value := ""
        LibInfo.Text := LibItems.Length ? _T("Pick a macro to see its description.") : ""
        return
    }
    ; the description, then what the macro does (asked for once per macro and version)
    d := LibDetail(it)
    LibDesc.Value := StrReplace((it["descr"] = "" ? _T("(no description)") : it["descr"])
        . (d ? "`n`n" _T("What it does:") "`n" LibDescribe(d) : ""), "`n", "`r`n")
    t := it["mine"] ? _T("your macro") : _T("by {1}", it["author"])         ; (type and key are in the preview)
    t := (it["game"] = "" ? "" : it["game"] "  ·  ") t
    if (it.Has("updated") && it["updated"])
        t .= "  ·  " _T("updated {1}", LibDate(it["updated"]))
    if (it.Has("verified") && it["verified"])
        t := Chr(0x2714) " " _T("verified") "  ·  " t
    if it["hidden"]
        t .= "  ·  " _T("hidden after reports")
    else if (!it["mine"] && it["my"])
        t .= "  ·  " _T("your rating: {1}", it["my"]) Chr(0x2605)
    LibInfo.Text := t
}

; the shared data of a hub macro (for the preview); remembered per id and version
LibDetail(it) {
    static cache := Map()
    k := it["id"] "/" (it.Has("version") ? it["version"] : 1)
    if cache.Has(k)
        return cache[k]
    if it.Has("data")                                           ; (my own macros come with it)
        return cache[k] := it["data"]
    j := LibCall("GET", "/" it["id"])
    if (j.Has("error") || !j.Has("data"))
        return 0
    return cache[k] := j["data"]
}

; what a macro does, in plain lines (the preview before a download)
LibDescribe(d) {
    pr := d["press"] = "tap" ? _T("Short tap") : d["press"] = "double" ? _T("Double tap") : d["press"] = "hold" ? _T("Long press") : _T("Normal")
    t := TypeLabel(d["type"]) "`n" _T("Trigger key") ": " (d["hotkey"] = "" ? Chr(0x2014) : d["hotkey"]) "  ·  " _T("Press") ": " pr
        . "`n" _T("Run") ": " (d["repeat"] ? _T("Repeat while key is held") : _T("Once per key press"))
    if (d["app"] != "")
        t .= "`n" _T("Only in app (exe)") ": " d["app"]
    if (d["type"] = "seq") {
        t .= "`n" _T("Sequence") ":"
        for l in StrSplit(d["seq"], "|")
            t .= "`n    " l
    } else
        t .= "`n" _T("Directions (optional)") ": " (d["dirs"] = "" ? Chr(0x2014) : d["dirs"])
            . "`n" _T("Actions in order") ": " d["actions"]
            . "`n" _T("Delays (ms)") ": " d["g1"] " / " d["g2"] " / " d["g3"] " / " d["ge"]
    return t
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
    nx := Round(10 * s)
    if (it.Has("verified") && it["verified"]) {                 ; verified by the moderator: a gold tick before the name
        DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr("D0AE6B"))
        NumPut("Int", nx, "Int", top + Round(5 * s), "Int", cw - rw, "Int", top + Round(27 * s), r)
        DllCall("DrawTextW", "Ptr", hdc, "WStr", Chr(0x2714), "Int", 1, "Ptr", r, "UInt", 0x824)
        tw := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "Ptr", hdc, "WStr", Chr(0x2714) "  ", "Int", 3, "Ptr", tw)
        nx += NumGet(tw, 0, "Int")
    }
    DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr(fg))
    NumPut("Int", nx, "Int", top + Round(5 * s), "Int", cw - rw - Round(8 * s), "Int", top + Round(27 * s), r)
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
    who := it["mine"] ? (it["hidden"] ? _T("hidden after reports") : _T("your macro")) : _T("by {1}", it["author"])
    DllCall("DrawTextW", "Ptr", hdc, "WStr", "(" it["count"] ")   " who (it["game"] = "" ? "" : "  ·  " it["game"]), "Int", -1, "Ptr", r, "UInt", 0x8824)
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
        return LibFail(j)
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
    if it["mine"]                                               ; my own macro back from the library: shared (gold icon)
        m["libshare"] := it["id"], m["libsharehash"] := LibHash(m)
    else                                                        ; someone else's: not shared again unchanged
        m["libsrc"] := it["id"], m["libsrcby"] := it["author"], m["libsrchash"] := LibHash(m)
            , m["libsrcver"] := j.Has("version") ? j["version"] : 1
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
        return LibFail(j)
    it["rating"] := j["rating"], it["count"] := j["count"], it["my"] := j["my"]
    LibLV.Modify(LibLV.GetNext(0), , it["name"])                ; repaint the row
    LibShowSel()
    Toast(_T("Thank you for rating!"))
}

LibReport() {
    it := LibSel()
    if !it
        return
    why := ThemedInput(_T("Report macro"), _T("Why should `"{1}`" be removed from Macro Hub? For example: a farm / AFK macro (not allowed), it does not work, or spam.", it["name"]))
    if (why = false || Trim(why) = "")
        return
    j := LibCall("POST", "/" it["id"] "/report", Map("reason", SubStr(Trim(why), 1, 200)))
    if j.Has("error")
        return LibFail(j)
    ThemedNote(_T("Thank you. The macro will be checked."))
}

LibDelete() {
    it := LibSel()
    if (!it || !it["mine"])
        return
    if (ThemedAsk(_T("Macro Hub"), _T("Delete from Macro Hub?"), _T("`"{1}`" will be removed from Macro Hub for everyone, with its ratings. Your own copy in the list stays.", it["name"]), [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
        return
    j := LibCall("DELETE", "/" it["id"])
    if j.Has("error")
        return LibFail(j)
    for m in Macros                                             ; the share icon of the own copy turns grey again
        if (m["libshare"] = it["id"])
            m["libshare"] := ""
    Save()
    RedrawList()
    LibLoad()
}

; fingerprint of what a macro shares (CRC32 of its library data)
LibHash(m) => LibHashData(LibData(m))
LibHashData(d) {
    s := JsonStr(d)
    buf := Buffer(StrPut(s, "UTF-8"))
    n := StrPut(s, buf, "UTF-8") - 1
    return Format("{:08x}", DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", buf, "UInt", n, "UInt"))
}

; downloaded from the library and not changed since: it can't be shared (it is someone else's macro)
LibFromLib(m) => (m["libsrc"] != "" && m["libsrchash"] = LibHash(m))

; shared by me and changed since (Macro Hub still has the old version)
LibSharedChanged(m) => (m["libshare"] != "" && m["libsharehash"] != "" && m["type"] != "script" && m["libsharehash"] != LibHash(m))

; ---- sharing: the share icon at the end of a row in the main list ----
LibShareMacro(m) {
    global LibAuthor, LibGame, LibSort, LibWho
    if !IndexOf(m)
        return
    if (m["type"] = "script")
        return ThemedNote(_T("Script macros can't be shared - only Move + actions and Sequence macros."), , true)
    if LibNew.Has(m)                                            ; downloaded, and its author has a newer version
        return LibShowUpdate(m)
    if LibFromLib(m)
        return ThemedNote(_T("`"{1}`" comes from Macro Hub (author: {2}), so it can't be shared again as it is. Change it first - for example a delay or a key - and then share your own version.", m["name"], m["libsrcby"]), _T("Share macro"))
    if LibSharedChanged(m)
        return LibOfferUpdate(m)
    if (m["libshare"] != "")
        return ThemedNote(_T("`"{1}`" is in Macro Hub and up to date. When you change it, you can update it there.", m["name"]), _T("Share macro"))
    if !LibOnline()                                             ; know it before the form is filled in
        return ThemedNote(_T("No connection to Macro Hub. Sharing needs the internet - try again when you are online."), _T("Share macro"), true)
    f := LibShareForm(m)
    if !f
        return
    j := LibCall("POST", "", Map("name", f["name"], "descr", f["descr"], "author", f["author"], "game", f["game"], "data", LibData(m)))
    if (j.Has("error") && j["error"] = "duplicate") {          ; exactly this macro is in the library already
        if j["mine"] {
            m["libshare"] := j["id"], m["libsharehash"] := LibHash(m)
            Save()
            RedrawList()
            return ThemedNote(_T("You have already shared this macro as `"{1}`". Change it to share a new version.", j["name"]), _T("Share macro"))
        }
        return ThemedNote(_T("This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version.", j["name"], j["author"]), _T("Share macro"), true)
    }
    if j.Has("error")
        return LibFail(j)
    m["libshare"] := j["id"], m["libsharehash"] := LibHash(m)
    LibAuthor := f["author"], LibGame := f["game"]
    Save()
    RedrawList()
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd)) {      ; the panel is open: show it among my macros
        LibWho := "mine", LibSort := "new"
        LibTabs()
        LibBtn["sort"].Text := LibSortText()
        PaintBtn(LibBtn["sort"].Hwnd, false)
        LibSearch.Value := ""
        LibLoad()
    }
    ThemedNote(_T("Thank you for sharing! `"{1}`" is now in Macro Hub.", f["name"]))
}

; ---- my shared macro was changed: update it in Macro Hub (ratings and downloads stay) ----
LibOfferUpdate(m) {
    if !(IndexOf(m) && LibSharedChanged(m))
        return
    if (ThemedAsk(_T("Macro Hub"), _T("Update in Macro Hub?"), _T("`"{1}`" is shared in Macro Hub. Update it there with your changes? Its ratings and downloads stay, and Macro Hub shows it as updated. Players who downloaded it get a notice.", m["name"]), [[_T("Not now"), "", "btn"], [_T("Update"), "yes", "btnprimary"]], false) = "yes")
        LibUpdateShared(m)
    else
        RedrawList()                                            ; the share icon keeps its dot: it can be updated later
}

; quiet = sent by itself later (it was asked for while offline): no messages, only a short notice when done
LibUpdateShared(m, quiet := false) {
    j := LibCall("PUT", "/" m["libshare"], Map("data", LibData(m)))
    if (j.Has("error") && j["error"] = "network") {             ; no internet: kept, sent when online again
        m["libpend"] := 1
        Save()
        if !quiet
            ThemedNote(_T("No connection to Macro Hub. Your change is kept - the app sends the update by itself as soon as you are online again."), _T("Macro Hub"), true)
        return
    }
    m["libpend"] := ""
    if (quiet && j.Has("error"))                                ; refused meanwhile: the dot stays, the user decides
        return Save()
    if (j.Has("error") && j["error"] = "duplicate")
        return ThemedNote(_T("This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version.", j["name"], j["author"]), _T("Macro Hub"), true)
    if (j.Has("error") && (j["error"] = "not_found" || j["error"] = "not_owner")) {     ; deleted from Macro Hub meanwhile
        m["libshare"] := "", m["libsharehash"] := ""
        Save()
        RedrawList()
        return ThemedNote(_T("`"{1}`" is no longer in Macro Hub. Share it again with the share icon.", m["name"]), _T("Macro Hub"), true)
    }
    if j.Has("error")
        return LibFail(j)
    m["libsharehash"] := LibHash(m)
    Save()
    RedrawList()
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd) && LibWho = "mine")
        LibLoad()
    Toast(_T("`"{1}`" is updated in Macro Hub.", m["name"]), 2500)
}

; ---- macros downloaded from Macro Hub: did their authors update them? ----
LibCheckUpdates(force := false) {
    static told := Map()                                        ; versions already announced in this session
    static last := -1000000
    if (!force && A_TickCount - last < 60000)                   ; (window shown again and again: once a minute is enough)
        return
    last := A_TickCount
    for m in Macros                                             ; updates of my shared macros asked for while offline
        if (m["libpend"] != "")
            LibSharedChanged(m) ? LibUpdateShared(m, true) : (m["libpend"] := "")
    LibLinkOld()
    ids := ""
    for m in Macros
        if (m["libsrc"] != "" && m["type"] != "script")
            ids .= (ids = "" ? "" : ",") m["libsrc"]
    if (ids = "")
        return
    j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "versions") "?ids=" ids)
    if (j.Has("error") || !j.Has("items"))
        return
    byId := Map()
    for it in j["items"]
        byId[String(it["id"])] := it
    LibNew.Clear()
    fresh := []
    for m in Macros {
        if (m["libsrc"] = "" || !byId.Has(String(m["libsrc"])))
            continue
        it := byId[String(m["libsrc"])]
        if (it["version"] > Num(m["libsrcver"] = "" ? 1 : m["libsrcver"]) && it["data"]["type"] != "script") {
            LibNew[m] := it
            if !told.Has(it["id"] "/" it["version"])
                fresh.Push(m), told[it["id"] "/" it["version"]] := true
        }
    }
    RedrawList()
    if fresh.Length
        TrayTip(fresh.Length = 1 ? _T("`"{1}`" has a new version in Macro Hub. Click its green arrow in the list to see the changes.", fresh[1]["name"])
            : _T("{1} downloaded macros have a new version in Macro Hub. Click their green arrows in the list to see the changes.", fresh.Length), "Macro Manager", 0x24)
}

; macros downloaded before the app remembered where they came from (or shared from another install): asked once,
; Macro Hub finds them by what they do - also an older version - so they get update notices / the gold icon
LibLinkOld() {
    ask := [], body := []
    for m in Macros
        if (m["type"] != "script" && m["libsrc"] = "" && m["libshare"] = "" && m["libchk"] = "" && body.Length < 100)
            ask.Push(m), body.Push(LibData(m))
    if !ask.Length
        return
    j := LibCall("POST", "", Map("items", body), RegExReplace(LibApi, "macros$", "match"))
    if (j.Has("error") || !j.Has("items"))
        return                                                  ; offline: asked again next time
    for it in j["items"] {
        m := ask[it["index"] + 1]
        if it["mine"] {
            if (it["version"] = it["latest"])
                m["libshare"] := it["id"], m["libsharehash"] := LibHash(m)
        } else
            m["libsrc"] := it["id"], m["libsrcby"] := it["author"], m["libsrcver"] := it["version"], m["libsrchash"] := LibHash(m)
    }
    for m in ask
        m["libchk"] := 1
    Save()
}

; the new version of a downloaded macro: what changed, take it or keep mine
LibShowUpdate(m) {
    if !LibNew.Has(m)
        return
    it := LibNew[m]
    mine := m["libsrchash"] != LibHash(m)                       ; the user changed the downloaded macro himself
    done := false, res := ""
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Macro Hub"))
    g.SetFont("s10 bold", "Segoe UI")
    hc := DlgText(g, "x16 y14 w528", _T("New version of `"{1}`" by {2}", m["name"], it["author"]) (it["updated"] ? " (" LibDate(it["updated"]) ")" : ""))
    hc.GetPos(, &hy, , &hh)
    y := hy + hh + 6
    g.SetFont("s9 norm", "Segoe UI")
    if mine {
        wc := DlgText(g, "x16 y" y " w528", _T("You changed this macro yourself - updating replaces your changes with the new version."))
        wc.GetPos(, &wy, , &wh)
        y := wy + wh + 6
    }
    g.AddText("x16 y" y " w528", _T("Changes (yours → new):"))
    g.SetFont("s10 norm", "Consolas")
    ed := g.AddEdit("x16 y" (y + 20) " w528 h220 Multi ReadOnly", StrReplace(LibDiff(LibData(m), it["data"]), "`n", "`r`n"))
    Roles[ed.Hwnd] := "code"
    g.SetFont("s9 norm", "Segoe UI")
    btnY := y + 20 + 220 + 16
    Pick(v, *) {
        res := v
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
    AddBtn(g, "x184 y" btnY " w110 h32", _T("Later"), Close)
    AddBtn(g, "x304 y" btnY " w110 h32", _T("Keep mine"), Pick.Bind("keep"))
    AddBtn(g, "x424 y" btnY " w120 h32", _T("Update"), Pick.Bind("update"), "btnprimary")
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w560 h" (btnY + 46), oh)
    SendMessage(0xB1, 0, 0, ed)                                 ; EM_SETSEL: nothing selected
    while !done
        Sleep 50
    if (res = "")
        return
    if (res = "update") {
        d := it["data"]
        for k in ["type", "hotkey", "app", "dirs", "actions", "seq", "press", "g1", "g2", "g3", "ge", "repeat", "exact"]
            if d.Has(k)
                m[k] := (k ~= "^(g\d|ge|repeat|exact)$") ? Integer(Num(d[k])) : String(d[k])
        if (Trim(m["hotkey"]) = "")
            m["hotkey"] := "undefined"
        m["libsrchash"] := LibHash(m)
    }
    m["libsrcver"] := it["version"]                             ; this version is dealt with (also "keep mine")
    LibNew.Delete(m)
    Save()
    Apply()
    Refresh()
    if (res = "update")
        Toast(_T("`"{1}`" is updated to the new version.", m["name"]), 2500)
}

; what differs between two versions of a macro, one line per change; a sequence line by line (- removed, + added)
LibDiff(a, b) {
    out := ""
    lab := Map("type", _T("Type"), "hotkey", _T("Trigger key"), "press", _T("Press"), "repeat", _T("Run"), "app", _T("Only in app (exe)")
        , "dirs", _T("Directions (optional)"), "actions", _T("Actions in order"), "exact", _T("Exact delays"))
    Val(k, v) {
        switch k {
            case "type": return TypeLabel(v)
            case "press": return v = "tap" ? _T("Short tap") : v = "double" ? _T("Double tap") : v = "hold" ? _T("Long press") : _T("Normal")
            case "repeat": return v ? _T("Repeat while key is held") : _T("Once per key press")
            case "exact": return v ? _T("ON") : _T("OFF")
        }
        return v = "" ? Chr(0x2014) : v
    }
    for k in ["type", "hotkey", "press", "repeat", "app", "dirs", "actions"]
        if (a[k] != b[k])
            out .= lab[k] ":`n    " Val(k, a[k]) "  →  " Val(k, b[k]) "`n"
    for i, k in ["g1", "g2", "g3", "ge"]
        if (a[k] != b[k])
            out .= _T("Delays (ms)") " " i ":  " a[k] "  →  " b[k] "`n"
    if (a["exact"] != b["exact"])
        out .= lab["exact"] ":  " Val("exact", a["exact"]) "  →  " Val("exact", b["exact"]) "`n"
    if (a["seq"] != b["seq"]) {
        out .= _T("Sequence") ":`n"
        x := StrSplit(a["seq"], "|"), y := StrSplit(b["seq"], "|")
        ; longest common subsequence: unchanged lines stay, the others are marked
        n := x.Length, mm := y.Length
        L := []
        loop n + 1 {
            row := []
            loop mm + 1
                row.Push(0)
            L.Push(row)
        }
        i := n
        while (i >= 1) {
            j := mm
            while (j >= 1) {
                L[i][j] := (x[i] = y[j]) ? L[i + 1][j + 1] + 1 : Max(L[i + 1][j], L[i][j + 1])
                j--
            }
            i--
        }
        i := 1, j := 1
        while (i <= n || j <= mm) {
            if (i <= n && j <= mm && x[i] = y[j])
                out .= "    " x[i] "`n", i++, j++
            else if (i <= n && (j > mm || L[i + 1][j] >= L[i][j + 1]))
                out .= "  - " x[i] "`n", i++                       ; removed lines first, then the added ones
            else
                out .= "  + " y[j] "`n", j++
        }
    }
    return out = "" ? _T("(no difference)") : RTrim(out, "`n")
}

LibDate(unix) => FormatTime(DateAdd("19700101000000", unix, "Seconds"), "ShortDate")

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

; name, game, description and nickname for sharing; returns a Map or false
LibShareForm(m) {
    res := false, done := false
    games := []                                                 ; games already in the library (+ the last one used)
    for x in LibGames                                           ; (loaded by LibOnline just before)
        games.Push(x["game"])
    if (LibGame != "") {
        known := false
        for x in games
            known := known || (x = LibGame)
        if !known
            games.InsertAt(1, LibGame)
    }
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Share macro"))
    g.SetFont("s10 bold", "Segoe UI")
    DlgText(g, "x16 y14 w388", _T("Share `"{1}`" in Macro Hub", m["name"]))
    g.SetFont("s9 norm", "Segoe UI")
    g.AddText("x16 y48 w388", _T("Name"))
    eN := g.AddEdit("x16 y66 w388 h26 Limit40", m["name"])
    g.AddText("x16 y100 w388", _T("Game (people filter and search by it, for example 4Story)"))
    eG := g.AddComboBox("x16 y118 w388", games)
    eG.Text := LibGame
    SendMessage(0x141, 30, 0, eG)                               ; CB_LIMITTEXT
    g.AddText("x16 y152 w388", _T("Description (optional): what it does, for which class"))
    eD := g.AddEdit("x16 y170 w388 h70 Multi Limit300", "")
    g.AddText("x16 y248 w388", _T("Your nickname"))
    eA := g.AddEdit("x16 y266 w388 h26 Limit24", LibAuthor)
    hc := DlgText(g, "x16 y302 w388", _T("Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."))
    Roles[hc.Hwnd] := "hint"
    hc.GetPos(, &hy, , &hh)
    btnY := hy + hh + 16
    Ok(*) {
        nm := Trim(eN.Value), au := Trim(eA.Value), gm := Trim(eG.Text)
        if (nm = "" || au = "" || gm = "") {
            ThemedNote(_T("Please fill in the name, the game and your nickname."), , true)
            return
        }
        res := Map("name", nm, "game", gm, "descr", Trim(StrReplace(eD.Value, "`r", "")), "author", au)
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
    if (LibGame = "")
        eG.Focus()
    else if (LibAuthor = "")
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
