; ============ dialogs in the app's own look (instead of the grey system MsgBox / InputBox) ============
; the app window in front: the dialog belongs to it and blocks it while open (0 = none, e.g. hidden in the tray)
DlgOwner() {
    try {
        h := WinExist("A")
        if (h && WinGetPID("ahk_id " h) = ProcessExist() && DllCall("IsWindowVisible", "Ptr", h))
            return h
        if DllCall("IsWindowVisible", "Ptr", Main.Hwnd)
            return Main.Hwnd
    }
    return 0
}

; long words (paths) get line breaks after a "\" so they never run out of the window
DlgWrap(text, maxLen := 58) {
    out := ""
    for line in StrSplit(text, "`n") {
        words := []
        for w in StrSplit(line, " ") {
            while (StrLen(w) > maxLen) {
                cut := InStr(SubStr(w, 1, maxLen), "\", , -1)  ; last "\" within the limit
                cut := cut > 8 ? cut : maxLen
                words.Push(SubStr(w, 1, cut) "`n")
                w := SubStr(w, cut + 1)
            }
            words.Push(w)
        }
        l := ""
        for i, w in words
            l .= (i > 1 && SubStr(words[i - 1], -1) != "`n" ? " " : "") w
        out .= (A_Index > 1 ? "`n" : "") l
    }
    return out
}

; static text that wraps (also long paths) and gets exactly the height it needs
DlgText(g, opts, text) {
    text := DlgWrap(text)
    c := g.AddText(opts " +0x2080", text)                       ; SS_EDITCONTROL | SS_NOPREFIX (& stays &)
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", c.Hwnd, "Ptr", rc)
    hdc := DllCall("GetDC", "Ptr", c.Hwnd, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, c), "Ptr")     ; WM_GETFONT
    DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x2C10)       ; CALCRECT|WORDBREAK|EDITCONTROL|NOPREFIX
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    DllCall("ReleaseDC", "Ptr", c.Hwnd, "Ptr", hdc)
    c.Move(, , , Round((NumGet(rc, 12, "Int") + 2) * 96 / A_ScreenDPI))
    return c
}

; question / message window.  buttons: [[label, value, role], ...] at the bottom right, left to right;
; the "btnprimary" one is the default (Enter).  Esc / closing the window returns "".
ThemedAsk(title, heading, body, buttons, warn := true) {
    res := "", done := false
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", title)
    g.SetFont("s9", "Segoe UI")
    x0 := 16, y := 16
    if warn {
        try {
            bp := g.AddPicture("x16 y" (heading = "" ? 16 : 17) " w16 h16", DarkOn ? BadgeDkFile : BadgeLtFile)   ; the yellow !
            Roles[bp.Hwnd] := "skip"
            x0 := 40
        }
    }
    if (heading != "") {
        g.SetFont("s10 bold", "Segoe UI")
        hc := DlgText(g, "x" x0 " y14 w" (484 - x0), heading)
        hc.GetPos(, &hy, , &hh)
        y := hy + hh + 8
        g.SetFont("s9 norm", "Segoe UI")
        bx := 16
    } else
        bx := x0
    bc := DlgText(g, "x" bx " y" y " w" (484 - bx), body)
    bc.GetPos(, &by, , &bh)
    btnY := by + bh + 18
    Pick(v, *) {
        res := v
        Close()
    }
    Close(*) {
        if done
            return
        done := true
        if oh
            DllCall("EnableWindow", "Ptr", oh, "Int", 1)        ; before Destroy, so the owner gets the focus back
        g.Destroy()
    }
    def := "", x := 484, i := buttons.Length
    while (i >= 1) {
        b := buttons[i]
        w := Max(100, 28 + 7 * StrLen(b[1]))
        x -= w
        AddBtn(g, "x" x " y" btnY " w" w " h32", b[1], Pick.Bind(b[2]), b[3])
        if (b[3] = "btnprimary")
            def := b[2]
        x -= 10
        i--
    }
    hb := g.AddButton("Default x-300 y-300 w1 h1")              ; invisible: Enter = the highlighted button
    hb.OnEvent("Click", Pick.Bind(def))
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)            ; modal: the owner waits
    ShowOver(g, "w500 h" (btnY + 46), oh)
    while !done
        Sleep 50
    return res
}

; message with an OK button
ThemedNote(text, title := "Macro Manager", warn := false, heading := "") {
    ThemedAsk(title, heading, text, [[_T("OK"), "ok", "btnprimary"]], warn)
}

; text input; returns the text, or false when cancelled
ThemedInput(title, prompt, default := "") {
    res := false, done := false
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", title)
    g.SetFont("s9", "Segoe UI")
    pc := DlgText(g, "x16 y16 w368", prompt)
    pc.GetPos(, &py, , &ph)
    ed := g.AddEdit("x16 y" (py + ph + 8) " w368 h26", default)
    ed.SetFont("s10")
    btnY := py + ph + 8 + 26 + 18
    Ok(*) {
        res := ed.Value
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
    AddBtn(g, "x174 y" btnY " w100 h32", _T("OK"), Ok, "btnprimary")
    AddBtn(g, "x284 y" btnY " w100 h32", _T("Cancel"), Close)
    hb := g.AddButton("Default x-300 y-300 w1 h1")
    hb.OnEvent("Click", Ok)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w400 h" (btnY + 46), oh)
    ed.Focus()
    SendMessage(0xB1, 0, -1, ed)                                ; EM_SETSEL: all selected, typing replaces it
    while !done
        Sleep 50
    return res
}
