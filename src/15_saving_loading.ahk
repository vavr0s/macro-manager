; ============ saving / loading ============
Defaults() {
    return Map("name", _T("New macro"), "hotkey", "LCtrl", "app", "", "type", "move", "enabled", 0,
        "dirs", "A,D", "actions", "1,2,3,4", "g1", 25, "g2", 30, "g3", 20, "ge", 10,
        "seq", "down A 25|tap 4 20|up A 5", "repeat", 1, "file", "", "tkey", "", "profiles", "", "trusted", 1, "press", "", "exact", 1, "libshare", "",     ; libshare = its id in the macro library once shared
        "libsharehash", "",                                 ; fingerprint of what was shared (changed since: offer an update)
        "libpend", "",                                      ; 1 = its update could not be sent (offline) - sent later by itself
        "libsrc", "", "libsrcby", "", "libsrchash", "", "libsrcver", "",   ; downloaded from the library: id, author, fingerprint, version
        "libchk", "")                                       ; 1 = already asked Macro Hub whether it is one of its macros
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
    global MasterOn, DarkOn, MasterKey, Profiles, CurProfile, AutoUpd, SeenVer, HoldMs, DblMs, LibId, LibAuthor, LibGame
    if (!FileExist(IniFile) && FileExist(IniFile ".bak"))
        try FileCopy(IniFile ".bak", IniFile)       ; saving was interrupted: take the last good copy
    if !FileExist(IniFile) {
        SeenVer := AppVersion      ; fresh install: nothing new to point out
        Save()      ; fresh install: empty macro list, the user imports their own
        return
    }
    ini := IniParse(FileRead(IniFile))              ; the whole file in one read (one IniRead per value was slow with many macros)
    Get(sec, key, def) => (ini.Has(sec) && ini[sec].Has(key)) ? ini[sec][key] : def
    MasterOn := Get("main", "master", "1") = "1"
    AutoUpd := Get("main", "autoupdate", "1") = "1"
    SeenVer := Get("main", "seenver", "")
    DarkOn := Get("main", "dark", "0") = "1"
    MasterKey := Get("main", "masterkey", "")
    LibId := Get("main", "libid", "")
    LibAuthor := Get("main", "libauthor", "")
    LibGame := Get("main", "libgame", "")
    HoldMs := Max(100, Min(2000, Num(Get("main", "holdms", HoldMs))))       ; long press: held at least this long
    DblMs := Max(100, Min(1000, Num(Get("main", "doublems", DblMs))))      ; double tap: 2nd press within this time
    pl := StrSplit(Get("main", "proflist", "Default"), "|")
    Profiles := []
    for pn in pl
        if (Trim(pn) != "")
            Profiles.Push(Trim(pn))
    if !Profiles.Length
        Profiles := ["Default"]
    CurProfile := Get("main", "profile", Profiles[1])
    if !HasProf(JoinProfs(Profiles), CurProfile)
        CurProfile := Profiles[1]
    n := Num(Get("main", "count", "0"))
    loop n {
        s := "m" A_Index
        m := Defaults()
        for k, v in Defaults()
            m[k] := Get(s, k, v)
        m["exact"] := Get(s, "exact", "0")          ; macros saved before exact delays existed keep their old timing
        for k in ["enabled", "g1", "g2", "g3", "ge", "repeat", "trusted", "exact"]
            m[k] := Num(m[k])
        m["file"] := RegExReplace(m["file"], "^.*\\", "")   ; keep only the file name
        if (Trim(m["profiles"]) = "")
            m["profiles"] := Profiles[1]
        Macros.Push(m)
    }
}

; ini text -> Map(section -> Map(key -> value)), read the way IniRead reads it: names without regard to case,
; the first of two equal keys wins, spaces around the value and one pair of enclosing quotes are dropped
IniParse(text) {
    out := Map(), out.CaseSense := "Off"
    cur := 0
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line, " `t")
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if RegExMatch(line, "^\[(.*)\]$", &h) {
            sec := Trim(h[1])
            if !out.Has(sec) {
                out[sec] := Map(), out[sec].CaseSense := "Off"
            }
            cur := out[sec]
            continue
        }
        if (!cur || !(p := InStr(line, "=")))
            continue
        k := Trim(SubStr(line, 1, p - 1), " `t"), v := Trim(SubStr(line, p + 1), " `t")
        if (StrLen(v) >= 2 && (q := SubStr(v, 1, 1)) = SubStr(v, -1) && (q = '"' || q = "'"))
            v := SubStr(v, 2, -1)
        if !cur.Has(k)
            cur[k] := v
    }
    return out
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
    t .= "libid=" LibId "`r`n"
    t .= "libauthor=" IniVal(LibAuthor) "`r`n"
    t .= "libgame=" IniVal(LibGame) "`r`n"
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
