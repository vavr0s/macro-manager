; ============ macro editor ============
EditMacro(idx) {
    isNew := !idx
    m := isNew ? Defaults() : View[idx]
    if isNew
        m["profiles"] := CurProfile
    pv := Map("v", m["profiles"])
    origProfs := m["profiles"]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", isNew ? _T("New macro") : _T("Edit macro"))
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)             ; same banner as the main window
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", isNew ? _T("New macro") : _T("Edit macro"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }

    g.AddText("x10 y100 w136 +0x200 h26", _T("Name"))
    eName := g.AddEdit("x150 y100 w250 h26", m["name"])
    g.AddText("x405 y100 w85 +0x200 h26", _T("Profiles"))
    bProfs := AddBtn(g, "x495 y100 w155 h26", ProfLabel(pv["v"]), (*) => (pv["v"] := PickProfiles(g, pv["v"]), bProfs.Text := ProfLabel(pv["v"])))
    g.AddText("x10 y136 w136 +0x200 h26", _T("Trigger key"))
    st := Map("key", m["hotkey"], "tkey", m["tkey"])
    bKey := AddBtn(g, "x150 y136 w250 h26", st["key"], (*) => CaptureKey(bKey, st, "key", false))
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
    rl := g.AddText("x10 y244 w136 +0x200 h26", _T("Run"))
    rb := []
    for i, nm in [_T("Once per key press"), _T("Repeat while key is held")]
        rb.Push(AddBtn(g, "x" (150 + (i - 1) * 255) " y244 w245 h26", nm, SetRun.Bind(i), i = rsel ? "btnprimary" : "btn"))

    ; --- group: move + actions ---
    mv := []
    mv.Push(g.AddText("x10 y292 w136 +0x200 h26", _T("Directions (optional)")))
    eDirs := g.AddEdit("x150 y292 w420 h26", m["dirs"])
    rb1 := AddBtn(g, "x580 y292 w70 h26", _T("Record"), (*) => StartListRec(eDirs, rb1))
    mv.Push(eDirs, rb1)
    mv.Push(g.AddText("x10 y328 w136 +0x200 h26", _T("Actions in order")))
    eActs := g.AddEdit("x150 y328 w420 h26", m["actions"])
    rb2 := AddBtn(g, "x580 y328 w70 h26", _T("Record"), (*) => StartListRec(eActs, rb2))
    mv.Push(eActs, rb2)
    mv.Push(g.AddText("x10 y364 w136 +0x200 h26", _T("Delays (ms)")))
    e1 := g.AddEdit("x150 y364 w110 h26 Number", m["g1"])
    e2 := g.AddEdit("x275 y364 w110 h26 Number", m["g2"])
    e3 := g.AddEdit("x400 y364 w110 h26 Number", m["g3"])
    e4 := g.AddEdit("x525 y364 w110 h26 Number", m["ge"])
    mv.Push(e1, e2, e3, e4)
    mv.Push(AddHint(g, "x150 y394 w120 h32", _T("dir↓ → action↓")))
    mv.Push(AddHint(g, "x275 y394 w120 h32", _T("action↓ → dir↑")))
    mv.Push(AddHint(g, "x400 y394 w120 h32", _T("dir↑ → action↑")))
    mv.Push(AddHint(g, "x525 y394 w120 h32", _T("between cycles")))
    mv.Push(AddHint(g, "x10 y434 w640", _T("Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4).")))

    ; --- group: sequence ---
    eSeq := g.AddEdit("x10 y292 w640 h120 Multi WantReturn", StrReplace(m["seq"], "|", "`n"))
    sq := [eSeq, AddHint(g, "x10 y418 w640", _T("One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"))]

    ; --- group: script ---
    code := ""
    if (m["type"] = "script" && m["file"] != "" && FileExist(ScriptPath(m)))
        code := FileRead(ScriptPath(m), "UTF-8")
    eCode := g.AddEdit("x10 y292 w640 h150 Multi WantReturn -Wrap HScroll", code)
    eCode.SetFont("s9", "Consolas")
    Roles[eCode.Hwnd] := "code"
    sc := [eCode, AddHint(g, "x10 y448 w640", _T("Runs as its own process while this macro is checked (AutoHotkey v2)."))]

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
    Toggle(*) {
        t := tsel
        for c in mv
            c.Visible := (t = 1)
        for c in sq
            c.Visible := (t = 2)
        for c in sc
            c.Visible := (t = 3)
        bKey.Enabled := (t != 3)
        eApp.Enabled := (t != 3)
        bApp.Enabled := (t != 3)
        rl.Visible := (t != 3)
        for c in rb
            c.Visible := (t != 3)
    }

    ; a macro that belongs to several profiles: apply the change everywhere, or only in the current profile
    Detach() {
        if (isNew || !HasProf(pv["v"], CurProfile) || StrSplit(pv["v"], "|").Length < 2)
            return true
        r := ThemedAsk("Macro Manager", _T("This macro is in several profiles ({1}).", ProfLabel(pv["v"]))
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
        }
        m["name"] := nm = "" ? "Macro" : nm
        m["profiles"] := pv["v"] = "" ? CurProfile : pv["v"]
        m["tkey"] := st["tkey"]
        if isNew
            Macros.Push(m)
        g.Destroy()
        Save()
        Apply()
        Refresh()
    }

    AddBtn(g, "x450 y482 w95 h34", _T("Save"), Commit, "btnprimary")
    AddBtn(g, "x555 y482 w95 h34", _T("Cancel"), (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Close", (*) => (FinishRec(), g.Destroy()))
    Toggle()
    ApplyTheme(g)
    ShowOver(g, "w660 h532", Main)
}

Num(v) => IsInteger(v) ? Integer(v) : 0
