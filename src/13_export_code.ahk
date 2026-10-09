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

    if (m["type"] = "move") {
        data := "rep := " (m["repeat"] ? "true" : "false") "`n"
            . "dirs := " ArrLit(SplitKeys(m["dirs"])) "`n"
            . "acts := " ArrLit(SplitKeys(m["actions"])) "`n"
            . "g1 := " m["g1"] ", g2 := " m["g2"] ", g3 := " m["g3"] ", ge := " m["ge"]
        body := TplMove()
    } else {
        data := "rep := " (m["repeat"] ? "true" : "false") "`n"
            . "steps := " StepsLit(m["seq"])
        body := TplSeq()
    }
    code := TplHeader() "`n" body
    code := StrReplace(code, "@DATA@", data)
    code := StrReplace(code, "@HOT@", TrigHot(m["hotkey"]))
    code := StrReplace(code, "@TRIG@", TrigMain(m["hotkey"]))
    app := StrReplace(m["app"], '"', "")
    code := StrReplace(code, "@APP@", app)
    code := StrReplace(code, "@HOTIF@", app = "" ? "" : '#HotIf WinActive("ahk_exe ' app '")')   ; plain criterion: checked by the hook itself

    code .= "`n`n; ===== Macro Manager metadata (used when importing this file) =====`n"
    for k in ["type", "hotkey", "app", "dirs", "actions", "g1", "g2", "g3", "ge", "seq", "repeat", "tkey"]
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

if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

trig := "@TRIG@"
app := "@APP@"
@DATA@
if InStr(trig, "Wheel") = 1
    rep := false        ; a wheel can't be held

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

Active() => GetKeyState(trig, "P") && (app = "" || WinActive("ahk_exe " app))

@HOTIF@
)"
}

TplMove() {
    return "
(
@HOT@:: {
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    while (rep ? Active() : n < acts.Length) {
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            Send Down(dir)
            Sleep g1 > 0 ? g1 : -1
            Send Down(key)
            Sleep g2 > 0 ? g2 : -1
            Send Up(dir)
            Sleep g3 > 0 ? g3 : -1
            Send Up(key)
            di := di >= dirs.Length ? 1 : di + 1
        } else {
            Send Down(key)
            Sleep g2 > 0 ? g2 : -1
            Send Up(key)
        }
        Sleep ge > 0 ? ge : -1
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
#HotIf
)"
}

TplSeq() {
    return "
(
@HOT@:: {
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
            Sleep s[3] > 0 ? s[3] : -1
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
#HotIf
)"
}
