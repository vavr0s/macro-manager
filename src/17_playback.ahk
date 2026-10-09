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
        Send UpStr(parts)
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
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            Send DownStr(dir)      ; 1. direction down (all keys of a chord together)
            Sleep g1
            Send DownStr(key)      ; 2. action down
            Sleep g2
            Send UpStr(dir)        ; 3. direction up
            Sleep g3
            Send UpStr(key)        ; 4. action up
            di := di >= dirs.Length ? 1 : di + 1
        } else {                   ; no movement: action only
            Send DownStr(key)
            Sleep g2
            Send UpStr(key)
        }
        Sleep ge
        ai := ai >= acts.Length ? 1 : ai + 1
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
        for s in steps {
            if (rep && !Active(m, trig)) {
                stop := true
                break
            }
            if (s[1] = "down")
                Send DownStr(s[2])
            else if (s[1] = "up")
                Send UpStr(s[2])
            else
                Send DownStr(s[2]) UpStr(s[2])
            Sleep s[3]
        }
        if !rep
            stop := true
    }
    ReleaseAll(used)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))
}
