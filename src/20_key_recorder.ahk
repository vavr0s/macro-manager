; ============ key recorder (trigger key + "Record" buttons) ============
; "name" of a pressed key; falls back to a scan code when the name is ambiguous
KeyToken(vk, sc) {
    if !sc {                               ; keys injected by mouse / keyboard software often come without a scan code
        n := GetKeyName(Format("vk{:x}", vk))
        return n != "" ? n : Format("vk{:02x}", vk)
    }
    code := Format("sc{:03x}", sc)
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "" || (StrLen(name) = 1 && InStr(",+&|", name)))
        return code
    if (GetKeySC(name) != sc)
        return code
    return name
}

HasTok(arr, v) {
    for k in arr
        if (k = v)
            return true
    return false
}

RecStart(mode, cb) {
    global Recording
    RecStop()
    Rec.mode := mode
    Rec.cb := cb
    Rec.down := []
    Rec.chord := []
    Rec.toks := []
    Rec.mpend := []
    Recording := true
    Apply()                          ; macro hotkeys are off while recording
    HotIf()
    if (mode = "single") {
        for b in MouseToks
            try Hotkey("*" b, RecMouse.Bind(b), "On")
    }
    ih := InputHook("L1023")
    ih.KeyOpt("{All}", "NS")         ; notify + suppress: nothing is typed into the window
    ih.OnKeyDown := RecDown
    ih.OnKeyUp := RecUp
    Rec.ih := ih
    ih.Start()
}

RecStop() {
    global Recording
    if !Rec.ih
        return
    try Rec.ih.Stop()
    Rec.ih := 0
    Rec.mode := ""                   ; not recording any more (update checks wait while this is set)
    for b in MouseToks
        try Hotkey("*" b, "Off")
    Recording := false
    Apply()
}

RecMouse(name, *) {
    if (Rec.ih && Rec.mode = "single") {
        cb := Rec.cb
        mods := HeldMods()
        RecStop()
        cb(ComboTok(mods, name))
    }
}

RecDown(ih, vk, sc) {
    if (!sc && !vk)
        return
    tok := KeyToken(vk, sc)
    if (Rec.mode = "single") {
        if IsModTok(tok) {                  ; modifier: wait - it's either the key itself or the start of a combination
            if !HasTok(Rec.mpend, tok)
                Rec.mpend.Push(tok)
            return
        }
        cb := Rec.cb
        mods := (tok = "Escape" || tok = "Backspace" || tok = "Delete") ? [] : HeldMods()
        RecStop()
        cb(ComboTok(mods, tok))
        return
    }
    if HasTok(Rec.down, tok)         ; auto-repeat
        return
    Rec.down.Push(tok)
    if !HasTok(Rec.chord, tok)
        Rec.chord.Push(tok)
    RecShow()
}

RecUp(ih, vk, sc) {
    if (!sc && !vk)
        return
    tok := KeyToken(vk, sc)
    if (Rec.mode = "single") {
        if (IsModTok(tok) && Rec.mpend.Length && HeldMods().Length = 0) {   ; only modifiers were pressed -> the first one is the key
            cb := Rec.cb
            first := NormMod(Rec.mpend[1])
            RecStop()
            cb(first)
        }
        return
    }
    if (Rec.mode != "list")
        return
    for i, k in Rec.down {
        if (k = tok) {
            Rec.down.RemoveAt(i)
            break
        }
    }
    if (Rec.down.Length = 0 && Rec.chord.Length) {
        Rec.toks.Push(JoinPlus(Rec.chord))     ; all keys of the chord are released -> one entry
        Rec.chord := []
    }
    RecShow()
}

RecShow() {
    s := ""
    for t in Rec.toks
        s .= (s = "" ? "" : ",") t
    if Rec.chord.Length
        s .= (s = "" ? "" : ",") JoinPlus(Rec.chord)
    cb := Rec.cb                     ; copy first: Rec.cb(s) would pass Rec as an extra first argument
    if cb
        cb(s)
}

; ends any running recording and restores the buttons
FinishRec() {
    if (Rec.ih && Rec.mode = "list" && Rec.chord.Length) {
        Rec.toks.Push(JoinPlus(Rec.chord))
        Rec.chord := []
        RecShow()
    }
    RecStop()
    if Rec.btn {
        try {
            Rec.btn.Text := _T("Record")
            Roles[Rec.btn.Hwnd] := "btn"
            PaintBtn(Rec.btn.Hwnd, false)
        }
        Rec.btn := 0
    }
    if Rec.undo {
        undo := Rec.undo
        Rec.undo := 0
        undo()
    }
}

StartListRec(edit, btn) {
    same := (Rec.btn == btn)
    FinishRec()
    if same
        return
    Rec.btn := btn
    btn.Text := _T("Done")
    Roles[btn.Hwnd] := "btnprimary"
    PaintBtn(btn.Hwnd, false)
    edit.Value := ""
    RecStart("list", (txt) => edit.Value := txt)
}

KeyLabel(prefix, v) => prefix (v = "" ? _T("none") : v)

; click-to-capture a key into st[field]; Esc cancels, Backspace/Delete clear (when allowClear)
CaptureKey(btn, st, field, allowClear, prefix := "", onDone := 0) {
    FinishRec()
    btn.Text := allowClear ? _T("Press a key or mouse button...   (Esc = cancel, Backspace = none)") : _T("Press a key or mouse button...   (Esc = cancel)")
    Rec.undo := (*) => btn.Text := KeyLabel(prefix, st[field])
    RecStart("single", (tok) => KeyCaptured(btn, st, field, allowClear, prefix, onDone, tok))
}

KeyCaptured(btn, st, field, allowClear, prefix, onDone, tok) {
    Rec.undo := 0
    if (tok != "Escape") {
        if (allowClear && (tok = "Backspace" || tok = "Delete"))
            st[field] := ""
        else
            st[field] := tok
    }
    btn.Text := KeyLabel(prefix, st[field])
    if (onDone && tok != "Escape")
        onDone()
}
