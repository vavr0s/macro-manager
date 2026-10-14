; ============ saving / loading ============
Defaults() {
    return Map("name", _T("New macro"), "hotkey", "LCtrl", "app", "", "type", "move", "enabled", 0,
        "dirs", "A,D", "actions", "1,2,3,4", "g1", 25, "g2", 30, "g3", 20, "ge", 10,
        "seq", "down A 25|tap 4 20|up A 5", "repeat", 1, "file", "", "tkey", "", "profiles", "", "trusted", 1, "press", "", "exact", 1)
}

; how the trigger key has to be pressed: "" = as soon as it goes down, "tap" = short press (plays after release),
; "double" = pressed twice quickly, "hold" = held down for a moment. Different press modes can share one key.
; (idea: evilC/TapHoldManager, MIT)
PressOf(m) {
    p := m.Has("press") ? StrLower(Trim(m["press"])) : ""
    return (p = "tap" || p = "double" || p = "hold") ? p : ""
}
PressShort(p) => p = "tap" ? _T("tap") : (p = "double" ? "2×" : (p = "hold" ? _T("hold") : ""))     ; in the list

Load() {
    global MasterOn, DarkOn, MasterKey, Profiles, CurProfile, AutoUpd, SeenVer, HoldMs, DblMs
    if (!FileExist(IniFile) && FileExist(IniFile ".bak"))
        try FileCopy(IniFile ".bak", IniFile)       ; saving was interrupted: take the last good copy
    if !FileExist(IniFile) {
        SeenVer := AppVersion      ; fresh install: nothing new to point out
        Save()      ; fresh install: empty macro list, the user imports their own
        return
    }
    MasterOn := IniRead(IniFile, "main", "master", "1") = "1"
    AutoUpd := IniRead(IniFile, "main", "autoupdate", "1") = "1"
    SeenVer := IniRead(IniFile, "main", "seenver", "")
    DarkOn := IniRead(IniFile, "main", "dark", "0") = "1"
    MasterKey := IniRead(IniFile, "main", "masterkey", "")
    HoldMs := Max(100, Min(2000, Num(IniRead(IniFile, "main", "holdms", HoldMs))))       ; long press: held at least this long
    DblMs := Max(100, Min(1000, Num(IniRead(IniFile, "main", "doublems", DblMs))))      ; double tap: 2nd press within this time
    pl := StrSplit(IniRead(IniFile, "main", "proflist", "Default"), "|")
    Profiles := []
    for pn in pl
        if (Trim(pn) != "")
            Profiles.Push(Trim(pn))
    if !Profiles.Length
        Profiles := ["Default"]
    CurProfile := IniRead(IniFile, "main", "profile", Profiles[1])
    if !HasProf(JoinProfs(Profiles), CurProfile)
        CurProfile := Profiles[1]
    n := Integer(IniRead(IniFile, "main", "count", "0"))
    loop n {
        s := "m" A_Index
        m := Defaults()
        for k, v in Defaults()
            m[k] := IniRead(IniFile, s, k, v)
        m["exact"] := IniRead(IniFile, s, "exact", "0")      ; macros saved before exact delays existed keep their old timing
        for k in ["enabled", "g1", "g2", "g3", "ge", "repeat", "trusted", "exact"]
            m[k] := Num(m[k])
        m["file"] := RegExReplace(m["file"], "^.*\\", "")   ; keep only the file name
        if (Trim(m["profiles"]) = "")
            m["profiles"] := Profiles[1]
        Macros.Push(m)
    }
}

; the whole file is built in memory and written in one go: first to macros.ini.tmp, then swapped in.
; the previous version is kept as macros.ini.bak - a crash or power cut while saving can't lose the macros
Save() {
    t := "[main]`r`n"
    t .= "master=" (MasterOn ? 1 : 0) "`r`n"
    t .= "dark=" (DarkOn ? 1 : 0) "`r`n"
    t .= "autoupdate=" (AutoUpd ? 1 : 0) "`r`n"
    t .= "seenver=" SeenVer "`r`n"
    t .= "masterkey=" MasterKey "`r`n"
    t .= "holdms=" HoldMs "`r`n"
    t .= "doublems=" DblMs "`r`n"
    t .= "language=" Lang "`r`n"
    t .= "proflist=" JoinProfs(Profiles) "`r`n"
    t .= "profile=" CurProfile "`r`n"
    t .= "count=" Macros.Length "`r`n"
    for i, m in Macros {
        t .= "[m" i "]`r`n"
        for k, v in m
            t .= k "=" IniVal(v) "`r`n"
    }
    tmp := IniFile ".tmp"
    try {
        f := FileOpen(tmp, "w", "UTF-16")
        f.Write(t)
        f.Close()
        if FileExist(IniFile)
            FileCopy(IniFile, IniFile ".bak", 1)
        FileMove(tmp, IniFile, 1)
    } catch as e {
        try FileDelete(tmp)
        Toast(_T("Saving the settings failed: {1}", e.Message))
    }
}

; a value as one ini line (no line breaks)
IniVal(v) => StrReplace(StrReplace(v, "`r", ""), "`n", " ")
