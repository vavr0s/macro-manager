; ============ hotkey registration / script processes ============
Apply() {
    global Registered, TogReg
    for r in Registered {
        try {
            SetCrit(r[2])
            Hotkey(r[1], "Off")
        }
    }
    HotIf()
    Registered := []
    for k in TogReg
        try Hotkey(k, "Off")
    TogReg := []
    used := Map()                                    ; key -> who uses it (to point out keys used twice)
    clash := []
    if !Recording {
        if (MasterKey != "") {
            RegToggle(MasterKey, ToggleMaster)
            used[KeyId(MasterKey)] := _T("the All macros toggle key")
        }
        for m in Macros
            if (m["tkey"] != "" && InProfile(m)) {
                RegToggle(m["tkey"], ToggleMacro.Bind(m))
                id := KeyId(m["tkey"]), who := _T("the toggle key of `"{1}`"", m["name"])
                if used.Has(id)
                    clash.Push([m["tkey"], used[id], who])
                else
                    used[id] := who
            }
    }
    ; macros on the same key in the same place share one handler: a "normal" macro takes the key as soon as it
    ; goes down; otherwise the handler tells short tap / double tap / long press apart (each can be another macro)
    groups := Map()
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
        id := StrLower(TrigHot(trig)) "|" StrLower(m["app"])
        if !groups.Has(id)
            groups[id] := {trig: trig, app: m["app"], name: m["name"], set: Map()}
        groups[id].set[PressEff(m)] := m             ; same key and same press mode: the later macro wins (as before)
        kid := KeyId(trig)
        if (used.Has(kid) && !used.Has("!" kid)) {   ; a toggle key (one line per key is enough)
            clash.Push([trig, used[kid], _T("the trigger key of `"{1}`"", m["name"])])
            used["!" kid] := true
        }
    }
    if !Recording
        ClashHint(clash)
    for id, gr in groups {
        fn := gr.set.Has("") ? MakeRun(gr.set[""], gr.trig) : MakePress(gr.set, gr.trig)
        try {
            SetCrit(gr.app)
            Hotkey(TrigHot(gr.trig), fn, gr.set.Has("") ? "On T1" : "On T2")   ; press modes: a 2nd thread notes the 2nd press
            Registered.Push([TrigHot(gr.trig), gr.app])
            if !IsWheel(gr.trig) {
                Hotkey(TrigHot(gr.trig) " up", NoteUp.Bind(gr.trig), "On")     ; release of a press from another program
                Registered.Push([TrigHot(gr.trig) " up", gr.app])
            }
        } catch as e {
            HotIf()
            ThemedNote(_T("Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}", gr.name, gr.trig, e.Message), , true)
        }
    }
    HotIf()
}

; one key used both as a toggle key and as a trigger (e.g. after an import): say so once, it would just not work
ClashHint(clash) {
    static last := ""
    txt := ""
    for c in clash
        txt .= (txt = "" ? "" : "`n") _T("The key {1} is used twice - as {2} and as {3}. Only one of them works.", c[1], c[2], c[3])
    if (txt != "" && txt != last)
        Toast(txt, 5000)
    last := txt
}

; comparable form of any key ("" = none)
KeyId(k) => (Trim(k) = "" || Trim(k) = "undefined") ? "" : StrLower(TrigHot(Trim(k)))

; who already uses key `id` in the profiles `profs` (a macro's toggle key, the All macros key, or - when
; `triggersToo` - a macro's trigger key): a description such as 'the toggle key of "Heal"', or "" when free
KeyTaken(id, self, profs, triggersToo) {
    if (id = "")
        return ""
    if (KeyId(MasterKey) = id)
        return _T("the All macros toggle key")
    for x in Macros {
        if (x == self || !ProfOverlap(x["profiles"], profs))
            continue
        if (KeyId(x["tkey"]) = id)
            return _T("the toggle key of `"{1}`"", x["name"])
        if (triggersToo && TrigId(x) = id)
            return _T("the trigger key of `"{1}`"", x["name"])
    }
    return ""
}

; press mode that really applies: a wheel has no hold and no release, so wheel macros always play at once
PressEff(m) => (m["type"] = "script" || IsWheel(m["hotkey"])) ? "" : PressOf(m)

RegToggle(key, fn) {
    try {
        Hotkey(TrigHot(key), fn, "On")
        TogReg.Push(TrigHot(key))
    }
}

SyncScript(m) {
    if (Procs.Has(m) && !ProcessExist(Procs[m]))
        return ScriptEnded(m)
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
        if (ThemedAsk("ComboCrown", _T("Same trigger key"), _T("Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work.", m["name"], m["hotkey"], other["name"])
            , [[_T("Turn on anyway"), "yes", "btn"], [_T("Cancel"), "", "btnprimary"]]) != "yes") {
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
    p := PressEff(m)
    for x in Macros {
        if (x == m || !x["enabled"] || !InProfile(x) || TrigId(x) != id)
            continue
        xp := PressEff(x)
        if (p != "" && xp != "" && p != xp)          ; e.g. short tap and long press on one key: both work
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
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Imported script"))
    g.SetFont("s10 bold", "Segoe UI")
    DlgText(g, "x16 y14 w468", _T("Turn on `"{1}`"?", name))
    g.SetFont("s9 norm", "Segoe UI")
    DlgText(g, "x16 y+8 w468", _T("This script was imported. It runs with administrator rights, so it can do anything on this PC. Only turn it on if you trust the person it came from."))
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
        if done
            return
        done := true
        if oh
            DllCall("EnableWindow", "Ptr", oh, "Int", 1)
        g.Destroy()
    }
    AddBtn(g, "x16 y" btnY " w140 h32", _T("Show the code"), DoCode)
    AddBtn(g, "x254 y" btnY " w120 h32", _T("Turn on"), DoOn, "btndanger")
    AddBtn(g, "x384 y" btnY " w100 h32", _T("Cancel"), Close, "btnprimary")
    hb := g.AddButton("Default x-300 y-300 w1 h1")              ; invisible: Enter = Cancel
    hb.OnEvent("Click", Close)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w500 h" (btnY + 46), oh)
    while !done
        Sleep 50
    return res
}

StartScript(m) {
    if (m["file"] = "" || !FileExist(ScriptPath(m))) {
        ThemedNote(_T("Script file for `"{1}`" is missing.", m["name"]), , true)
        return
    }
    ahk := AhkExe()
    if (ahk = "") {
        ThemedNote(_T("Script macros need AutoHotkey v2 installed (not found)."), , true)
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

; a script that has finished by itself turns its macro off (unticked), so it runs again only when the user turns
; it on again - before, every change in the list (another macro ticked, profile switched, ...) started it once more
ScriptWatch() {
    for m, pid in Procs.Clone()
        if !ProcessExist(pid)
            ScriptEnded(m)
}

ScriptEnded(m) {
    global Populating
    Procs.Delete(m)
    m["enabled"] := 0
    Save()
    for i, v in View
        if (v == m) {
            Populating := true
            LV.Modify(i, "-Check")
            Populating := false
        }
}

; "only in app": a plain window criterion that the keyboard hook checks by itself. A script function as the
; criterion would make the hook wait for the app on every press (and every auto-repeat) of a trigger key - when
; the app is busy that stalls the whole keyboard, and Windows may drop the hook so a held macro never stops.
SetCrit(app) {
    if (app = "")
        HotIf()
    else
        HotIfWinActive("ahk_exe " app)
}
MakeRun(m, trig) => (*) => (AltGrFake(trig) ? 0 : (NoteDown(trig), RunPick(m, trig)))
MakePress(set, trig) => (*) => RunPress(set, trig)
RunPick(m, trig, once := false) => m["type"] = "move" ? RunMove(m, trig, once) : RunSeq(m, trig, once)

; one key, several press modes: waits only as long as needed to tell them apart.
; long press = still held after HoldMs; double tap = pressed again within DblMs after release; short tap = neither.
; (approach of evilC/TapHoldManager, MIT - rewritten for ComboCrown)
RunPress(set, trig) {
    if AltGrFake(trig)
        return
    k := TrigMain(trig), kk := StrLower(k)
    if PressBusy.Get(kk, false) {                       ; 2nd thread (hotkey option T2): the key was pressed again
        if DblWait.Get(kk, false) {
            NoteDown(trig)
            DblHit[kk] := true
        }
        return                                          ; otherwise ignored, as before (one macro run at a time)
    }
    NoteDown(trig)
    PressBusy[kk] := true
    try RunPress2(set, trig, k, kk)
    finally {
        PressBusy[kk] := false
        DblWait[kk] := false
    }
}

RunPress2(set, trig, k, kk) {
    inj := InjDown[kk]
    if set.Has("hold") {
        if !(inj ? WaitUp(trig, HoldMs) : KeyWait(k, "P T" HoldMs / 1000))   ; not released in time = long press
            return RunPick(set["hold"], trig)                                ; (repeat runs while held)
    } else if inj
        WaitUp(trig)
    else
        KeyWait(k, "P")
    if set.Has("double") {
        DblHit[kk] := false
        DblWait[kk] := true
        if inj {
            t := A_TickCount
            while (!DblHit[kk] && A_TickCount - t < DblMs)
                Sleep 5
            hit := DblHit[kk]
        } else
            hit := KeyWait(k, "D P T" DblMs / 1000)
        DblWait[kk] := false
        if hit
            return RunPick(set["double"], trig)         ; held on the 2nd press: "repeat while held" works here too
    }
    if set.Has("tap")
        RunPick(set["tap"], trig, true)                 ; the key is already up: plays one pass
}

; ---- trigger keys pressed by another program (mouse software, Steam Input, remote desktop, ...) ----
; Windows marks such presses as "injected" and AutoHotkey doesn't count them as physically held, so long press,
; double tap and "repeat while held" never saw the key held. For those presses the app follows the key's own
; down / up events instead. A real keyboard or mouse keeps using the physical key state, exactly as before.
NoteDown(trig) {
    k := TrigMain(trig)
    InjDown[StrLower(k)] := !GetKeyState(k, "P")
}

NoteUp(trig, *) {
    InjDown[StrLower(TrigMain(trig))] := false
}

; the trigger key is held (physically, or as a press from another program that hasn't been released yet)
Held(trig) {
    k := TrigMain(trig)
    if GetKeyState(k, "P")
        return true
    kk := StrLower(k)
    if !InjDown.Get(kk, false)
        return false
    parts := StrSplit(Trim(trig), "+")                  ; a combination: its modifiers must still be down too
    loop parts.Length - 1 {
        p := Trim(parts[A_Index])
        if (p != "" && !GetKeyState(p)) {
            InjDown[kk] := false
            return false
        }
    }
    return true
}

; waits until the trigger key is released (true) or ms have passed (false)
WaitUp(trig, ms := 0) {
    t := A_TickCount
    while Held(trig) {
        if (ms && A_TickCount - t >= ms)
            return false
        Sleep 5
    }
    return true
}

Active(m, trig) => Held(trig) && !AltGrFake(trig, true) && (m["app"] = "" || WinActive("ahk_exe " m["app"]))

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
