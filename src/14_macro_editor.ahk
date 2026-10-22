; ============ macro editor ============
EditMacro(idx) {
    static open := 0                                  ; one editor at a time (two editors of one macro would overwrite each other)
    if (open && WinExist("ahk_id " open)) {
        WinActivate("ahk_id " open)
        return
    }
    isNew := !idx
    if (!isNew && idx > View.Length)
        return                                        ; the list changed in the meantime
    m := isNew ? Defaults() : View[idx]
    if isNew
        m["profiles"] := CurProfile
    pv := Map("v", m["profiles"])
    origProfs := m["profiles"]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", isNew ? _T("New macro") : _T("Edit macro"))
    open := g.Hwnd
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)             ; same banner as the main window
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", isNew ? _T("New macro") : _T("Edit macro"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }

    g.AddText("x10 y100 w136 +0x200 h26", _T("Name"))
    eName := g.AddEdit("x150 y100 w250 h26", isNew ? "" : m["name"])
    if isNew                                          ; new macro: the default name is only a grey hint, typing replaces it
        DllCall("SendMessageW", "Ptr", eName.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", m["name"])   ; EM_SETCUEBANNER
    g.AddText("x405 y100 w85 +0x200 h26", _T("Profiles"))
    bProfs := AddBtn(g, "x495 y100 w155 h26", ProfLabel(pv["v"]), (*) => (pv["v"] := PickProfiles(g, pv["v"]), bProfs.Text := ProfLabel(pv["v"])))
    g.AddText("x10 y136 w136 +0x200 h26", _T("Trigger key"))
    st := Map("key", Trim(m["hotkey"]) = "undefined" ? "" : m["hotkey"], "tkey", m["tkey"])   ; (a script without a key: "undefined")
    bKey := AddBtn(g, "x150 y136 w250 h26", KeyLabel("", st["key"]), (*) => CaptureKey(bKey, st, "key", false))
    g.AddText("x405 y136 w85 +0x200 h26", _T("Toggle"))
    bTog := AddBtn(g, "x495 y136 w155 h26", KeyLabel("", st["tkey"]), (*) => CaptureKey(bTog, st, "tkey", true))
    g.AddText("x10 y172 w136 +0x200 h26", _T("Only in app (exe)"))
    eApp := g.AddEdit("x150 y172 w420 h26", m["app"])
    bApp := AddBtn(g, "x580 y172 w70 h26", _T("Select"), (*) => (eApp.Value := PickApp(g, eApp.Value)))

    ; type + run mode: flat segmented buttons instead of native controls
    tsel := m["type"] = "move" ? 1 : (m["type"] = "seq" ? 2 : 3)
    rsel := m["repeat"] ? 2 : 1
    g.AddText("x10 y208 w136 +0x200 h26", _T("Type"))
    tb := []
    for i, nm in [_T("Move + actions"), _T("Sequence"), _T("Script (.ahk)")]
        tb.Push(AddBtn(g, "x" (150 + (i - 1) * 170) " y208 w160 h26", nm, SetType.Bind(i), i = tsel ? "btnprimary" : "btn"))
    ; press mode: how the trigger key has to be pressed (different modes can share one key)
    psel := 1
    for i, p in ["", "tap", "double", "hold"]
        if (PressOf(m) = p)
            psel := i
    pl := g.AddText("x10 y244 w136 +0x200 h26", _T("Press"))
    pb := []
    for i, nm in [_T("Normal"), _T("Short tap"), _T("Double tap"), _T("Long press")]
        pb.Push(AddBtn(g, "x" (150 + (i - 1) * 126) " y244 w122 h26", nm, SetPress.Bind(i), i = psel ? "btnprimary" : "btn"))
    rl := g.AddText("x10 y280 w136 +0x200 h26", _T("Run"))
    rb := []
    for i, nm in [_T("Once per key press"), _T("Repeat while key is held")]
        rb.Push(AddBtn(g, "x" (150 + (i - 1) * 255) " y280 w245 h26", nm, SetRun.Bind(i), i = rsel ? "btnprimary" : "btn"))

    ; --- group: move + actions ---
    mv := []
    mv.Push(g.AddText("x10 y328 w136 +0x200 h26", _T("Directions (optional)")))
    eDirs := g.AddEdit("x150 y328 w420 h26", m["dirs"])
    rb1 := AddBtn(g, "x580 y328 w70 h26", _T("Record"), (*) => StartListRec(eDirs, rb1))
    mv.Push(eDirs, rb1)
    mv.Push(g.AddText("x10 y364 w136 +0x200 h26", _T("Actions in order")))
    eActs := g.AddEdit("x150 y364 w420 h26", m["actions"])
    rb2 := AddBtn(g, "x580 y364 w70 h26", _T("Record"), (*) => StartListRec(eActs, rb2))
    mv.Push(eActs, rb2)
    mv.Push(g.AddText("x10 y400 w136 +0x200 h26", _T("Delays (ms)")))
    e1 := g.AddEdit("x150 y400 w110 h26 Number", m["g1"])
    e2 := g.AddEdit("x275 y400 w110 h26 Number", m["g2"])
    e3 := g.AddEdit("x400 y400 w110 h26 Number", m["g3"])
    e4 := g.AddEdit("x525 y400 w110 h26 Number", m["ge"])
    mv.Push(e1, e2, e3, e4)
    mv.Push(AddHint(g, "x150 y430 w120 h32", _T("dir↓ → action↓")))
    mv.Push(AddHint(g, "x275 y430 w120 h32", _T("action↓ → dir↑")))
    mv.Push(AddHint(g, "x400 y430 w120 h32", _T("dir↑ → action↑")))
    mv.Push(AddHint(g, "x525 y430 w120 h32", _T("between cycles")))
    mv.Push(AddHint(g, "x10 y470 w640", _T("Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4).")))

    ; --- group: sequence ---
    eSeq := g.AddEdit("x10 y328 w640 h120 Multi WantReturn", StrReplace(m["seq"], "|", "`n"))
    eSeq.OnEvent("Change", FixLineEnds)
    sq := [eSeq, AddHint(g, "x10 y454 w640", _T("One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"))]

    ; --- group: script ---
    code := ""
    if (m["type"] = "script" && m["file"] != "" && FileExist(ScriptPath(m)))
        code := FileRead(ScriptPath(m), "UTF-8")
    eCode := g.AddEdit("x10 y328 w640 h150 Multi WantReturn -Wrap HScroll", code)
    eCode.SetFont("s9", "Consolas")
    eCode.OnEvent("Change", FixLineEnds)
    Roles[eCode.Hwnd] := "code"
    sc := [eCode, AddHint(g, "x10 y484 w640", _T("Runs as its own process while this macro is checked (AutoHotkey v2)."))]

    SetSeg(arr, n) {
        for i, c in arr {
            Roles[c.Hwnd] := (i = n) ? "btnprimary" : "btn"
            PaintBtn(c.Hwnd, false)
        }
    }
    SetType(n, *) {
        tsel := n
        SetSeg(tb, n)
        Toggle()
    }
    SetRun(n, *) {
        rsel := n
        SetSeg(rb, n)
    }
    SetPress(n, *) {
        psel := n
        SetSeg(pb, n)
        Toggle()
    }
    Toggle(*) {
        t := tsel
        for c in mv
            c.Visible := (t = 1)
        for c in sq
            c.Visible := (t = 2)
        for c in sc
            c.Visible := (t = 3)
        try bExact.Visible := (t != 3)
        bKey.Enabled := (t != 3)
        eApp.Enabled := (t != 3)
        bApp.Enabled := (t != 3)
        pl.Visible := (t != 3)
        for c in pb
            c.Visible := (t != 3)
        rv := (t != 3 && psel != 2)                 ; a short tap has already been released: it always plays once
        rl.Visible := rv
        for c in rb
            c.Visible := rv
    }

    ; a macro that belongs to several profiles: apply the change everywhere, or only in the current profile
    Detach() {
        if (isNew || !HasProf(pv["v"], CurProfile) || StrSplit(pv["v"], "|").Length < 2)
            return true
        r := ThemedAsk("ComboCrown", _T("This macro is in several profiles ({1}).", ProfLabel(pv["v"]))
            , _T("Apply the change to all of them, or only to the current profile ({1})? The other profiles then keep the old, unchanged version.", CurProfile)
            , [[_T("Cancel"), "", "btn"], [_T("Only in `"{1}`"", CurProfile), "one", "btn"], [_T("All profiles"), "all", "btnprimary"]], false)
        if (r = "")
            return false
        if (r = "all")
            return true
        old := m
        StopScript(old)
        rest := []
        for p in StrSplit(pv["v"], "|")
            if (p != CurProfile)
                rest.Push(p)
        old["profiles"] := JoinProfs(rest)
        m := old.Clone()
        m["file"] := ""
        pv["v"] := CurProfile
        isNew := true
        return true
    }

    Commit(*) {
        FinishRec()
        t := tsel
        nm := Trim(eName.Value)
        if (nm = "" && isNew)
            nm := m["name"]                             ; nothing typed: the default name (the grey hint)
        if (st["tkey"] != "" && (who := KeyTaken(KeyId(st["tkey"]), m, pv["v"], true))) {   ; toggle = another key in use
            ThemedNote(_T("The toggle key {1} is already used as {2}.", st["tkey"], who), , true)
            return
        }
        if (t = 3) {
            txt := eCode.Value
            if (Trim(txt) = "") {
                ThemedNote(_T("Paste or write a script first."), , true)
                return
            }
            if !Detach()
                return
            StopScript(m)
            if (m["file"] = "" || !FileExist(ScriptPath(m)))
                m["file"] := NewScriptFile()
            WriteText(ScriptPath(m), txt)
            m["hotkey"] := DetectKey(txt)
            m["type"] := "script"
            m["trusted"] := 1                       ; written / pasted here, the code was in front of the user
        } else {
            key := Trim(st["key"])
            if (key = "") {
                ThemedNote(_T("Enter a trigger key."), , true)
                return
            }
            if (st["tkey"] != "" && StrLower(TrigHot(st["tkey"])) = StrLower(TrigHot(key))) {
                ThemedNote(_T("The toggle key can't be the same as the trigger key."), , true)
                return
            }
            if (who := KeyTaken(KeyId(key), m, pv["v"], false)) {        ; trigger = a toggle key in the same profile
                ThemedNote(_T("The trigger key {1} is already used as {2}.", key, who), , true)
                return
            }
            if !Detach()
                return
            StopScript(m)
            m["hotkey"] := key
            m["app"] := Trim(eApp.Value)
            m["type"] := t = 1 ? "move" : "seq"
            m["dirs"] := Trim(eDirs.Value)
            m["actions"] := Trim(eActs.Value)
            m["g1"] := Num(e1.Value)
            m["g2"] := Num(e2.Value)
            m["g3"] := Num(e3.Value)
            m["ge"] := Num(e4.Value)
            lines := ""
            for l in StrSplit(eSeq.Value, "`n", "`r")
                if (Trim(l) != "")
                    lines .= (lines = "" ? "" : "|") Trim(l)
            m["seq"] := lines
            m["repeat"] := rsel = 2 ? 1 : 0
            m["press"] := ["", "tap", "double", "hold"][psel]
            m["exact"] := ex["v"]
        }
        m["name"] := nm = "" ? "Macro" : nm
        m["profiles"] := pv["v"] = "" ? CurProfile : pv["v"]
        m["tkey"] := st["tkey"]
        if isNew {
            Macros.Push(m)
            if (eSearch.Value != "")
                eSearch.Value := ""               ; the new macro must be visible
        }
        if (!isNew && !IndexOf(m))
            Macros.Push(m)                          ; deleted from the list while the editor was open: keep the edit
        g.Destroy()
        Save()
        Apply()
        Refresh()
        if (m["enabled"] && (other := KeyClash(m)))
            Toast(_T("Same trigger key as `"{1}`" - only one of them works", other["name"]))
        if LibSharedChanged(m)                          ; shared in Macro Hub and changed now: update it there?
            SetTimer(LibOfferUpdate.Bind(m), -150)
    }

    ; exact delays: on for new macros; older macros keep their timing until this is switched on
    ex := Map("v", m["exact"] ? 1 : 0)
    ExLabel() => ex["v"] ? Chr(0x2713) "  " _T("Exact delays") : _T("Exact delays") ": " _T("OFF")
    bExact := AddBtn(g, "x10 y518 w220 h34", ExLabel(), FlipExact, ex["v"] ? "btnprimary" : "btn")
    FlipExact(*) {
        ex["v"] := !ex["v"]
        bExact.Text := ExLabel()
        Roles[bExact.Hwnd] := ex["v"] ? "btnprimary" : "btn"
        PaintBtn(bExact.Hwnd, true)
    }
    AddBtn(g, "x450 y518 w95 h34", _T("Save"), Commit, "btnprimary")
    AddBtn(g, "x555 y518 w95 h34", _T("Cancel"), (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Close", (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Escape", (*) => (Rec.ih ? 0 : (FinishRec(), g.Destroy())))     ; Esc while recording belongs to the recorder
    Toggle()
    ApplyTheme(g)
    ShowOver(g, "w660 h568", Main)
}

Num(v) => IsInteger(v) ? Integer(v) : 0

; text pasted with Unix line ends (only LF - e.g. code copied from a web page) shows as one long line in a Windows
; edit box: turn every lone LF into CR LF and keep the caret where it was
FixLineEnds(ed, *) {
    h := ed.Hwnd
    n := DllCall("GetWindowTextLengthW", "Ptr", h)
    buf := Buffer((n + 1) * 2, 0)
    DllCall("GetWindowTextW", "Ptr", h, "Ptr", buf, "Int", n + 1)
    raw := StrGet(buf, n, "UTF-16")
    if !RegExMatch(raw, "(?<!`r)`n")
        return
    s := 0, e := 0
    DllCall("SendMessageW", "Ptr", h, "UInt", 0xB0, "UInt*", &s, "UInt*", &e)      ; EM_GETSEL
    RegExReplace(SubStr(raw, 1, e), "(?<!`r)`n", "", &add)
    DllCall("SetWindowTextW", "Ptr", h, "Str", RegExReplace(raw, "(?<!`r)`n", "`r`n"))
    SendMessage(0xB1, e + add, e + add, h)                                        ; EM_SETSEL
    SendMessage(0xB7, 0, 0, h)                                                    ; EM_SCROLLCARET
}
