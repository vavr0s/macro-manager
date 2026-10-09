; ============ hotkey registration / script processes ============
Apply() {
    global Registered, TogReg
    for r in Registered {
        try {
            HotIf(r[2])
            Hotkey(r[1], "Off")
        }
    }
    HotIf()
    Registered := []
    for k in TogReg
        try Hotkey(k, "Off")
    TogReg := []
    if !Recording {
        if (MasterKey != "")
            RegToggle(MasterKey, ToggleMaster)
        for m in Macros
            if (m["tkey"] != "" && InProfile(m))
                RegToggle(m["tkey"], ToggleMacro.Bind(m))
    }
    for m in Macros {
        if (m["type"] = "script") {
            SyncScript(m)
            continue
        }
        if (!MasterOn || Recording || !m["enabled"] || !InProfile(m))
            continue
        trig := Trim(m["hotkey"])
        if (trig = "" || trig = "undefined")
            continue
        cond := MakeCond(m)
        try {
            HotIf(cond)
            Hotkey(TrigHot(trig), MakeRun(m, trig), "On")
            Registered.Push([TrigHot(trig), cond])
        } catch as e {
            HotIf()
            MsgBox _T("Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}", m["name"], trig, e.Message), "Macro Manager", 48
        }
    }
    HotIf()
}

RegToggle(key, fn) {
    try {
        Hotkey(TrigHot(key), fn, "On")
        TogReg.Push(TrigHot(key))
    }
}

SyncScript(m) {
    if (Procs.Has(m) && !ProcessExist(Procs[m]))
        Procs.Delete(m)
    want := MasterOn && m["enabled"] && InProfile(m) && !NeedsTrust(m)
    running := Procs.Has(m)
    if (want && !running)
        StartScript(m)
    else if (!want && running)
        StopScript(m)
}

; ============ imported scripts: ask before they run for the first time ============
; a script macro runs as its own process with the rights of this app (administrator), so it can do anything on the PC
NeedsTrust(m) => (m["type"] = "script" && !m["trusted"])

; turns a macro on - from its check box (viaKey = false) or from its toggle key (viaKey = true).
; an imported script asks first; a trigger key that an active macro already uses is pointed out
EnableMacro(m, viaKey := false) {
    if !IndexOf(m)
        return
    if NeedsTrust(m) {
        code := ""
        if (m["file"] != "" && FileExist(ScriptPath(m)))
            try code := FileRead(ScriptPath(m), "UTF-8")
        r := ConfirmScript(m["name"], code)
        if (r = "code") {
            Main.Show()
            for i, v in View
                if (v == m)
                    return EditMacro(i)
            return
        }
        if (r != "on")
            return
        m["trusted"] := 1
    }
    other := KeyClash(m)
    if (other && !viaKey) {
        if (Mb(_T("Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work.`n`nTurn it on anyway?", m["name"], m["hotkey"], other["name"]), "Macro Manager", "YesNo Icon! Default2") != "Yes") {
            Save()                                  ; keeps a "trusted" that was just given
            return
        }
    }
    m["enabled"] := 1
    Save()
    Apply()
    Refresh()
    if viaKey
        Toast(m["name"] ": " _T("ON") (other ? "`n" _T("Same trigger key as `"{1}`" - only one of them works", other["name"]) : ""))
}

; ============ same trigger key as another active macro ============
; comparable form of a macro's trigger key ("" = none)
TrigId(m) {
    k := Trim(m["hotkey"])
    if (k = "" || k = "undefined")
        return ""
    if (m["type"] = "script")
        k := RegExReplace(k, "^[~$*]+")             ; hotkey prefixes in a script that don't change the key
    return StrLower(TrigHot(k))
}

; another macro that is on, in the current profile, and reacts to the same key in the same place (or 0)
KeyClash(m) {
    id := TrigId(m)
    if (id = "")
        return 0
    app := m["type"] = "script" ? "" : m["app"]
    for x in Macros {
        if (x == m || !x["enabled"] || !InProfile(x) || TrigId(x) != id)
            continue
        xa := x["type"] = "script" ? "" : x["app"]
        if (app = "" || xa = "" || app = xa)        ; "everywhere" overlaps with every application
            return x
    }
    return 0
}

; what the code can do, in plain words (a quick look for the usual commands, not a real security check)
ScriptRisks(code) {
    code := RegExReplace(code, "s)/\*.*?\*/", "")            ; block comments
    code := RegExReplace(code, "m)(^|\s);.*$", "")             ; line comments
    checks := [
        ["\b(Run|RunWait|ShellExecute)\b", _T("starts other programs or commands")],
        ["\b(Download|URLDownloadToFile|WinHttp|XMLHTTP)\b|https?://", _T("connects to the internet or downloads files")],
        ["\b(FileDelete|DirDelete|FileRecycle|FileRecycleEmpty)\b", _T("deletes files or folders")],
        ["\b(FileAppend|FileOpen|FileCopy|FileMove|DirCopy|DirMove|FileSetAttrib)\b", _T("writes, copies or moves files")],
        ["\b(RegWrite|RegDelete|RegDeleteKey)\b", _T("changes the Windows registry")],
        ["\b(DllCall|ComObject|ComObjCreate|ComObjGet|ComCall)\b", _T("calls Windows functions directly")],
        ["\b(InputHook|ClipboardAll|A_Clipboard|Clipboard)\b", _T("reads what you type or the clipboard")],
        ["\b(ProcessClose|Shutdown|WinKill)\b", _T("closes programs or shuts the PC down")],
        ["#Include\b", _T("loads code from other files")],
        ["%\s*\w+\s*%\s*\(|%\s*[`"']", _T("calls commands by a computed name (can hide what it does)")]
    ]
    out := []
    for c in checks
        if RegExMatch(code, "i)" c[1])
            out.Push(c[2])
    return out
}

; themed dialog: "on" (turn it on), "code" (show the code in the editor) or "" (cancel)
ConfirmScript(name, code) {
    res := "", done := false
    risks := ScriptRisks(code)
    owner := (DllCall("IsWindowVisible", "Ptr", Main.Hwnd) ? Main : 0)
    g := Gui((owner ? "+Owner" Main.Hwnd " " : "") "+ToolWindow +AlwaysOnTop", _T("Imported script"))
    g.SetFont("s10 bold", "Segoe UI")
    g.AddText("x16 y14 w468", _T("Turn on `"{1}`"?", name))
    g.SetFont("s9 norm", "Segoe UI")
    g.AddText("x16 y+8 w468", _T("This script was imported. It runs with administrator rights, so it can do anything on this PC. Only turn it on if you trust the person it came from."))
    if risks.Length {
        g.SetFont("s9 bold", "Segoe UI")
        g.AddText("x16 y+12 w468", _T("Found in the code - the script:"))
        g.SetFont("s9 norm", "Segoe UI")
        for x in risks
            g.AddText("x28 y+4 w456", Chr(0x2022) "  " x)
    } else
        AddHint(g, "x16 y+12 w468", _T("No risky commands were found. This is only a quick check, not a guarantee."))
    btnY := 0
    g.AddText("x16 y+16 w1 h1").GetPos(, &btnY)                ; buttons go below the last line
    DoOn(*) {
        res := "on"
        Close()
    }
    DoCode(*) {
        res := "code"
        Close()
    }
    Close(*) {
        done := true
        g.Destroy()
    }
    AddBtn(g, "x16 y" btnY " w140 h32", _T("Show the code"), DoCode)
    AddBtn(g, "x254 y" btnY " w120 h32", _T("Turn on"), DoOn, "btndanger")
    AddBtn(g, "x384 y" btnY " w100 h32", _T("Cancel"), Close, "btnprimary")
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    ShowOver(g, "w500 h" (btnY + 46), owner ? Main : 0)
    while !done
        Sleep 50
    return res
}

StartScript(m) {
    if (m["file"] = "" || !FileExist(ScriptPath(m))) {
        MsgBox _T("Script file for `"{1}`" is missing.", m["name"]), "Macro Manager", 48
        return
    }
    ahk := AhkExe()
    if (ahk = "") {
        MsgBox _T("Script macros need AutoHotkey v2 installed (not found)."), "Macro Manager", 48
        return
    }
    Run('"' ahk '" "' ScriptPath(m) '"', , , &pid)
    Procs[m] := pid
}

StopScript(m) {
    if Procs.Has(m) {
        try ProcessClose(Procs[m])
        Procs.Delete(m)
    }
}

MakeCond(m) => (*) => (m["app"] = "" || WinActive("ahk_exe " m["app"]))
MakeRun(m, trig) => (*) => (AltGrFake(trig) ? 0 : (m["type"] = "move" ? RunMove(m, trig) : RunSeq(m, trig)))

Active(m, trig) => GetKeyState(TrigMain(trig), "P") && !AltGrFake(trig, true) && (m["app"] = "" || WinActive("ahk_exe " m["app"]))

; Keyboards with an AltGr key (Czech, Polish, German, ...) send AltGr as a fake Left Ctrl + Right Alt.
; A macro on Left Ctrl must not react to that fake Left Ctrl.
IsLCtrlTok(t) => RegExMatch(Trim(t), "i)^L(Ctrl|Control)$")
AltGrFake(trig, mainToo := false) {
    if !GetKeyState("RAlt", "P")
        return false
    parts := StrSplit(Trim(trig), "+")
    for i, p in parts {
        if (Trim(p) = "" )
            continue
        if RegExMatch(Trim(p), "i)^R(Alt|Menu)$")
            return false
        if (IsLCtrlTok(p) && (mainToo || i < parts.Length))
            return true
    }
    return false
}

; ---- trigger keys: "XButton1", "WheelUp", "sc01e", or a combination such as "LCtrl+XButton1" ----
IsModTok(t) => RegExMatch(t, "i)^[LR]?(Control|Ctrl|Shift|Alt|Win)$")

TrigMain(trig) {
    parts := StrSplit(Trim(trig), "+")
    return parts.Length > 1 && parts[parts.Length] != "" ? Trim(parts[parts.Length]) : Trim(trig)
}

IsWheel(trig) => RegExMatch(TrigMain(trig), "i)^Wheel(Up|Down|Left|Right)$")

; hotkey name for Hotkey(): "*" + modifier symbols + main key
TrigHot(trig) {
    trig := Trim(trig)
    parts := StrSplit(trig, "+")
    pre := ""
    if (parts.Length > 1 && parts[parts.Length] != "") {
        for i, p in parts {
            if (i = parts.Length)
                break
            if !RegExMatch(Trim(p), "i)^([LR]?)(Control|Ctrl|Shift|Alt|Win)$", &r)
                return "*" trig
            side := StrUpper(r[1]) = "L" ? "<" : (StrUpper(r[1]) = "R" ? ">" : "")
            sym := RegExMatch(r[2], "i)^Con|^Ctrl") ? "^" : (RegExMatch(r[2], "i)^Shift") ? "+" : (RegExMatch(r[2], "i)^Alt") ? "!" : "#"))
            pre .= side sym
        }
        last := Trim(parts[parts.Length])
        return "*" pre (IsLCtrlTok(last) ? "sc01D" : last)
    }
    return "*" (IsLCtrlTok(trig) ? "sc01D" : trig)
}

; modifiers that are physically held right now, as "LCtrl", "RShift", ...
HeldMods() {
    out := []
    for k in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin"]
        if GetKeyState(k, "P")
            out.Push(k)
    return out
}

NormMod(t) {
    if RegExMatch(t, "i)^([LR]?)(Control|Ctrl)$", &r)
        return StrUpper(r[1]) "Ctrl"
    return t
}

ComboTok(mods, tok) {
    s := ""
    for m in mods
        s .= m "+"
    return s tok
}
