; ============ helpers ============
Sc(k) {
    k := Trim(k)
    if RegExMatch(k, "i)^sc[0-9a-f]+$")
        return StrLower(k)
    sc := GetKeySC(k)
    return sc ? Format("sc{:03x}", sc) : k
}

; "a,Shift+4,sc02e" -> [["sc01e"], ["sc02a","sc005"], ["sc02e"]]; one inner array = keys pressed together
SplitKeys(s) {
    arr := []
    for tok in StrSplit(s, ",") {
        parts := TokParts(tok)
        if parts.Length
            arr.Push(parts)
    }
    return arr
}

TokParts(tok) {
    tok := Trim(tok)
    parts := []
    if (tok = "")
        return parts
    if (tok = "+") {
        parts.Push(Sc("+"))
        return parts
    }
    for p in StrSplit(tok, "+") {
        p := Trim(p)
        if (p != "")
            parts.Push(Sc(p))
    }
    return parts
}

JoinPlus(parts) {
    s := ""
    for i, k in parts
        s .= (i > 1 ? "+" : "") k
    return s
}

DownStr(parts) {
    s := ""
    for k in parts
        s .= "{" k " down}"
    return s
}

UpStr(parts) {
    s := ""
    for k in parts
        s .= "{" k " up}"
    return s
}

ReleaseAll(arr) {
    for parts in arr
        KeyUp(parts)
}

; keys the macros are holding down right now (HeldKeys, released when the app exits in the middle of a macro)
KeyDown(parts) {
    Send DownStr(parts)
    for k in parts
        HeldKeys[k] := true
}
KeyUp(parts) {
    Send UpStr(parts)
    for k in parts
        if HeldKeys.Has(k)
            HeldKeys.Delete(k)
}
ReleaseHeld() {
    for k in HeldKeys.Clone()
        try Send "{" k " up}"
    HeldKeys.Clear()
}

; a pause between steps: 0 still lets Windows and the app breathe (Sleep -1 = handle messages, no wait)
StepWait(ms) {
    if (ms > 0)
        Sleep ms
    else
        Sleep -1
}

; repeated macros: one cycle takes at least this long, so a macro with 0 ms delays can't flood
; Windows with thousands of key events per second (that blocks the whole keyboard, even after the app is closed)
CycleFloor(t0) {
    rest := 10 - (A_TickCount - t0)
    if (rest > 0)
        Sleep rest
}

; ============ type: move + actions ============
RunMove(m, trig) {
    global MacroBusy
    MacroBusy++
    try RunMove2(m, trig)
    finally MacroBusy--
}

RunMove2(m, trig) {
    dirs := SplitKeys(m["dirs"])
    acts := SplitKeys(m["actions"])
    if !acts.Length
        return
    g1 := m["g1"], g2 := m["g2"], g3 := m["g3"], ge := m["ge"]
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    rep := m["repeat"] && !IsWheel(trig)          ; a wheel can't be held
    while (rep ? Active(m, trig) : n < acts.Length) {      ; once = every action one time
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            KeyDown(dir)      ; 1. direction down (all keys of a chord together)
            StepWait(g1)
            KeyDown(key)      ; 2. action down
            StepWait(g2)
            KeyUp(dir)        ; 3. direction up
            StepWait(g3)
            KeyUp(key)        ; 4. action up
            di := di >= dirs.Length ? 1 : di + 1
        } else {                   ; no movement: action only
            KeyDown(key)
            StepWait(g2)
            KeyUp(key)
        }
        StepWait(ge)
        ai := ai >= acts.Length ? 1 : ai + 1
        if rep
            CycleFloor(t0)
    }
    ReleaseAll(dirs)
    ReleaseAll(acts)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))          ; "once": don't restart until the key is released
}

; ============ type: custom sequence ============
RunSeq(m, trig) {
    global MacroBusy
    MacroBusy++
    try RunSeq2(m, trig)
    finally MacroBusy--
}

RunSeq2(m, trig) {
    steps := []
    used := []
    for line in StrSplit(m["seq"], "|") {
        if RegExMatch(Trim(line), "i)^(down|up|tap)\s+(\S+)(?:\s+(\d+))?$", &r) {
            k := TokParts(r[2])
            steps.Push([StrLower(r[1]), k, r[3] = "" ? 0 : Integer(r[3])])
            used.Push(k)
        }
    }
    if !steps.Length
        return
    rep := m["repeat"] && !IsWheel(trig)
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    stop := false
    while !stop {
        t0 := A_TickCount
        for s in steps {
            if (rep && !Active(m, trig)) {
                stop := true
                break
            }
            if (s[1] = "down")
                KeyDown(s[2])
            else if (s[1] = "up")
                KeyUp(s[2])
            else {
                KeyDown(s[2])
                KeyUp(s[2])
            }
            StepWait(s[3])
        }
        if !rep
            stop := true
        else if !stop
            CycleFloor(t0)
    }
    ReleaseAll(used)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))
}

; ============ stuck modifier keys ============
; AltGr = a fake Left Ctrl + Right Alt. A macro on Left Ctrl swallows the real Left Ctrl key, and the "up" of
; AltGr's fake Ctrl could get swallowed with it: Windows then keeps Ctrl pressed - every key and mouse click
; becomes Ctrl+..., so keyboard and mouse seem dead, and pressing Left Ctrl can't fix it while the macro is on.
AltGrUp(*) {
    Sleep 30
    for k in ["LCtrl", "RAlt"]
        if (GetKeyState(k) && !GetKeyState(k, "P"))
            Send "{Blind}{" k " up}"
}

; every 250 ms: Ctrl / Alt down for Windows but not held on the keyboard for over a second -> released
ModWatch() {
    static mods := ["LCtrl", "RCtrl", "LAlt", "RAlt"], since := Map()
    if (MacroBusy > 0 || Rec.ih || GetKeyState("RAlt", "P")) {      ; a macro is playing, recording, or AltGr is held
        since.Clear()
        return
    }
    for k in mods {
        if (GetKeyState(k) && !GetKeyState(k, "P")) {
            if !since.Has(k)
                since[k] := A_TickCount
            else if (A_TickCount - since[k] >= 1000) {
                Send "{Blind}{" k " up}"
                since.Delete(k)
            }
        } else if since.Has(k)
            since.Delete(k)
    }
}
