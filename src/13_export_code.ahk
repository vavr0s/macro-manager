; ============ export: a macro as a standalone AutoHotkey v2 script ============
WriteText(path, text) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

ArrLit(arr) {
    s := "["
    for i, parts in arr
        s .= (i > 1 ? ", " : "") '"' JoinPlus(parts) '"'
    return s "]"
}

StepsLit(seq) {
    s := "["
    n := 0
    for line in StrSplit(seq, "|") {
        if RegExMatch(Trim(line), "i)^(down|up|tap)\s+(\S+)(?:\s+(\d+))?$", &r) {
            n++
            s .= (n > 1 ? ", " : "") '["' StrLower(r[1]) '", "' JoinPlus(TokParts(r[2])) '", ' (r[3] = "" ? 0 : Integer(r[3])) ']'
        }
    }
    return s "]"
}

ExportCode(m) {
    if (m["type"] = "script")
        return (m["file"] != "" && FileExist(ScriptPath(m))) ? FileRead(ScriptPath(m), "UTF-8") : ""

    press := PressEff(m)
    if (m["type"] = "move") {
        data := "rep := " (m["repeat"] && press != "tap" ? "true" : "false") "`n"
            . "dirs := " ArrLit(SplitKeys(m["dirs"])) "`n"
            . "acts := " ArrLit(SplitKeys(m["actions"])) "`n"
            . "g1 := " m["g1"] ", g2 := " m["g2"] ", g3 := " m["g3"] ", ge := " m["ge"]
        body := TplMove()
    } else {
        data := "rep := " (m["repeat"] && press != "tap" ? "true" : "false") "`n"
            . "steps := " StepsLit(m["seq"])
        body := TplSeq()
    }
    code := TplHeader() "`n" body
    code := StrReplace(code, "@DATA@", data)
    code := StrReplace(code, "@PRESS@", press)
    code := StrReplace(code, "@EXACT@", m["exact"] ? "true" : "false")
    code := StrReplace(code, "@HOLDMS@", HoldMs)
    code := StrReplace(code, "@DBLMS@", DblMs)
    code := StrReplace(code, "@DBL@", Round(DblMs / 1000, 3))
    mods := "["                                       ; modifiers of a combination such as LCtrl+XButton1
    parts := StrSplit(Trim(m["hotkey"]), "+")
    loop parts.Length - 1
        if (Trim(parts[A_Index]) != "")
            mods .= (mods = "[" ? "" : ", ") '"' Trim(parts[A_Index]) '"'
    code := StrReplace(code, "@MODS@", mods "]")
    code := StrReplace(code, "@UP@", IsWheel(m["hotkey"]) ? "" : TrigHot(m["hotkey"]) " up:: {`n    global inj := false`n}")
    code := StrReplace(code, "@HOT@", TrigHot(m["hotkey"]))
    code := StrReplace(code, "@TRIG@", TrigMain(m["hotkey"]))
    app := StrReplace(m["app"], '"', "")
    code := StrReplace(code, "@APP@", app)
    code := StrReplace(code, "@HOTIF@", app = "" ? "" : '#HotIf WinActive("ahk_exe ' app '")')   ; plain criterion: checked by the hook itself

    code .= "`n`n; ===== ComboCrown metadata (used when importing this file) =====`n"
    for k in ["type", "hotkey", "app", "dirs", "actions", "g1", "g2", "g3", "ge", "seq", "repeat", "tkey", "press", "exact"]
        code .= "; MM:" k "=" m[k] "`n"
    return code
}

TplHeader() {
    return "
(
#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Event"
SetKeyDelay -1, -1
ProcessSetPriority "High"
st := Buffer(12, 0)     ; Windows 11: no slowed-down timers / efficiency mode for this background script
for mask in [0x5, 0x1] {
    NumPut("UInt", 1, "UInt", mask, "UInt", 0, st)
    try if DllCall("SetProcessInformation", "Ptr", -1, "Int", 4, "Ptr", st, "UInt", 12)
        break
}

if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

trig := "@TRIG@"
app := "@APP@"
press := "@PRESS@"      ; "" = at once, tap = short press, double = pressed twice quickly, hold = held a moment
exact := @EXACT@        ; true = delays kept to about a millisecond, false = plain Sleep
@DATA@
if InStr(trig, "Wheel") = 1
    rep := false        ; a wheel can't be held

; a press from another program (mouse software, Steam Input, remote desktop) is not "physical" for Windows:
; for such a press the script follows the key's own down / up events instead of the physical key state
mods := @MODS@          ; modifiers of a key combination (they must stay down too)
inj := false, busy := false, waiting := false, dblHit := false

Held() {
    global inj
    if GetKeyState(trig, "P")
        return true
    if !inj
        return false
    for k in mods
        if !GetKeyState(k) {
            inj := false
            return false
        }
    return true
}

; waits until the key is released (true) or ms have passed (false)
WaitUp(ms) {
    if !inj
        return ms ? KeyWait(trig, "P T" ms / 1000) : KeyWait(trig, "P")
    t := A_TickCount
    while Held() {
        if (ms && A_TickCount - t >= ms)
            return false
        Sleep 5
    }
    return true
}

; is this the press the macro waits for? (long press: still held after a moment; double tap: pressed again in time)
PressOk() {
    global inj, waiting, dblHit
    inj := !GetKeyState(trig, "P")
    fromApp := inj                                    ; (inj goes back to false when the key is released)
    if (press = "")
        return true
    if (press = "hold")
        return !WaitUp(@HOLDMS@)
    WaitUp(0)
    if (press = "tap")
        return true
    dblHit := false, waiting := true
    if fromApp {
        t := A_TickCount
        while (!dblHit && A_TickCount - t < @DBLMS@)
            Sleep 5
        hit := dblHit
    } else
        hit := KeyWait(trig, "D P T@DBL@")
    waiting := false
    return hit
}

; the trigger key: a 2nd press while the macro is busy only counts as the 2nd press of a double tap
OnTrigger(play) {
    global busy, inj, dblHit
    if busy {
        if waiting {
            inj := !GetKeyState(trig, "P")
            dblHit := true
        }
        return
    }
    busy := true
    try {
        if PressOk()
            play()
    } finally
        busy := false
}

; exact pause: most of it a normal Sleep, the rest measured in 1 ms steps (Sleep alone can be ~15 ms longer)
Wait(ms) {
    static f := 0
    if (ms <= 0) {
        Sleep -1
        return
    }
    if !exact {
        Sleep ms
        return
    }
    if !f
        DllCall("QueryPerformanceFrequency", "Int64*", &f)
    DllCall("QueryPerformanceCounter", "Int64*", &t := 0)
    stop := t + ms * f / 1000
    if (ms > 20)
        Sleep ms - 16
    loop {
        DllCall("QueryPerformanceCounter", "Int64*", &t)
        left := (stop - t) * 1000 / f
        if (left <= 0)
            break
        if (left > 1.5)
            DllCall("Sleep", "UInt", 1)
    }
}

Down(t) {
    s := "{Blind}"            ; held Shift / Ctrl / Alt are left alone (no stuck modifier keys)
    for k in StrSplit(t, "+")
        s .= "{" k " down}"
    return s
}

Up(t) {
    s := "{Blind}"
    for k in StrSplit(t, "+")
        s .= "{" k " up}"
    return s
}

Active() => Held() && (app = "" || WinActive("ahk_exe " app))

@HOTIF@
)"
}

TplMove() {
    return "
(
#MaxThreadsPerHotkey 2
@HOT@::OnTrigger(Play)
@UP@
#HotIf

Play() {
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    while (rep ? Active() : n < acts.Length) {
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            Send Down(dir)
            Wait(g1)
            Send Down(key)
            Wait(g2)
            Send Up(dir)
            Wait(g3)
            Send Up(key)
            di := di >= dirs.Length ? 1 : di + 1
        } else {
            Send Down(key)
            Wait(g2)
            Send Up(key)
        }
        Wait(ge)
        ai := ai >= acts.Length ? 1 : ai + 1
        if (rep && A_TickCount - t0 < 10)
            Sleep 10 - (A_TickCount - t0)       ; never flood Windows with key events
    }
    for k in dirs
        Send Up(k)
    for k in acts
        Send Up(k)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && InStr(trig, "Wheel") != 1)
        try KeyWait(trig)
}
)"
}

TplSeq() {
    return "
(
#MaxThreadsPerHotkey 2
@HOT@::OnTrigger(Play)
@UP@
#HotIf

Play() {
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    stop := false
    while !stop {
        t0 := A_TickCount
        for s in steps {
            if (rep && !Active()) {
                stop := true
                break
            }
            if (s[1] = "down")
                Send Down(s[2])
            else if (s[1] = "up")
                Send Up(s[2])
            else
                Send Down(s[2]) Up(s[2])
            Wait(s[3])
        }
        if (!rep)
            stop := true
        else if (!stop && A_TickCount - t0 < 10)
            Sleep 10 - (A_TickCount - t0)       ; never flood Windows with key events
    }
    for s in steps
        Send Up(s[2])
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && InStr(trig, "Wheel") != 1)
        try KeyWait(trig)
}
)"
}
