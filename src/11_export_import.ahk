; ============ export / import ============
OnExportBtn(*) {
    sel := SelMacros()
    if !sel.Length {
        ThemedNote(_T("Select a macro first."), , true)
        return
    }
    if (sel.Length > 1) {
        dir := DirSelect("*" A_Desktop, 3, _T("Choose a folder for the {1} exported macros", sel.Length))
        if (dir = "")
            return
        ThemedNote(_T("{1} macro(s) exported to:`n{2}", ExportAllTo(dir, sel), dir))
        return
    }
    m := sel[1]
    if (m["type"] != "script") {
        k := Trim(m["hotkey"])
        if (k = "" || k = "undefined") {
            ThemedNote(_T("Set a trigger key for this macro first."), , true)
            return
        }
    }
    code := ExportCode(m)
    if (code = "") {
        ThemedNote(_T("Nothing to export (script file is missing)."), , true)
        return
    }
    safe := RegExReplace(m["name"], '[\\/:*?"<>|]', "_")
    path := FileSelect("S16", A_Desktop "\" safe ".ahk", _T("Export macro"), _T("AutoHotkey scripts (*.ahk)"))
    if (path = "")
        return
    if !RegExMatch(path, "i)\.ahk$")
        path .= ".ahk"
    WriteText(path, code)
    ThemedNote(_T("Exported to:`n{1}", path))
}

OnExportAll(*) {
    if !Macros.Length {
        ThemedNote(_T("There are no macros to export."), , true)
        return
    }
    dir := DirSelect("*" A_Desktop, 3, _T("Choose a folder for the exported macros"))
    if (dir = "")
        return
    n := ExportAllTo(dir)
    ThemedNote(_T("{1} macro(s) exported to:`n{2}", n, dir))
}

; writes every macro as its own .ahk file (names made unique); returns how many were written
ExportAllTo(dir, list := 0) {
    n := 0
    used := Map()
    for m in (list ? list : Macros) {
        code := ""
        try code := ExportCode(m)
        if (code = "")
            continue
        base := RegExReplace(m["name"], '[\\/:*?"<>|]', "_")
        nm := base
        k := 1
        while used.Has(StrLower(nm))
            nm := base " (" k++ ")"
        used[StrLower(nm)] := true
        try {
            WriteText(RTrim(dir, "\") "\" nm ".ahk", code)
            n++
        }
    }
    return n
}

OnImportBtn(*) {
    files := FileSelect("M3", , _T("Import macros"), _T("AutoHotkey scripts (*.ahk)"))
    if !files.Length
        return
    ImportFiles(files)
}

; drag & drop of .ahk files onto the window = same as Import...
OnDropFiles(g, ctrl, files, x, y) {
    if (DragOut || A_TickCount - DragEnd < 800)        ; our own drag-out dropped back onto the window
        return
    list := []
    for f in files
        if RegExMatch(f, "i)\.ahk$")
            list.Push(f)
    if !list.Length {
        Toast(_T("Drop .ahk files to import them"))
        return
    }
    Main.Show()
    ImportFiles(list)
}

ImportFiles(files) {
    added := 0
    for path in files
        if ImportOne(path)
            added++
    if !added
        return
    Save()
    Apply()
    Refresh()
    LV.Modify(View.Length, "Select Focus Vis")
}

NextImportedName() {
    n := 1
    loop {
        nm := "imported " n
        taken := false
        for m in Macros {
            if (m["name"] = nm) {
                taken := true
                break
            }
        }
        if !taken
            return nm
        n++
    }
}

; macro name = file name without extension; duplicates get " (1)", " (2)"...
ImportName(path) {
    SplitPath(path, , , , &base)
    base := Trim(base)
    if (base = "")
        return NextImportedName()
    nm := base
    n := 1
    loop {
        taken := false
        for m in Macros {
            if (m["name"] = nm) {
                taken := true
                break
            }
        }
        if !taken
            return nm
        nm := base " (" n ")"
        n++
    }
}

ImportOne(path) {
    try text := FileRead(path, "UTF-8")
    catch {
        ThemedNote(_T("Can't read:`n{1}", path), , true)
        return false
    }
    meta := Map()
    for line in StrSplit(text, "`n", "`r")
        if RegExMatch(line, "^; MM:(\w+)=(.*)$", &r)
            meta[r[1]] := r[2]

    m := Defaults()
    m["profiles"] := CurProfile
    m["name"] := ImportName(path)
    m["enabled"] := 0

    if (meta.Has("type") && (meta["type"] = "move" || meta["type"] = "seq")) {
        ; file exported by Macro Manager -> editable native macro
        m["type"] := meta["type"]
        for k in ["app", "dirs", "actions", "seq", "tkey"]
            if meta.Has(k)
                m[k] := meta[k]
        for k in ["g1", "g2", "g3", "ge", "repeat"]
            if meta.Has(k)
                m[k] := Num(meta[k])
        m["hotkey"] := (meta.Has("hotkey") && Trim(meta["hotkey"]) != "") ? Trim(meta["hotkey"]) : "undefined"
    } else {
        ; any other script -> runs as its own process while the macro is on
        if (!InStr(text, "#Requires AutoHotkey v2")
            && ThemedAsk("Macro Manager", _T("Import anyway?"), _T("This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work."), [[_T("Import anyway"), "yes", "btn"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
            return false
        m["type"] := "script"
        m["trusted"] := 0                           ; someone else's code: asked before it runs for the first time
        m["file"] := NewScriptFile()
        WriteText(ScriptPath(m), text)
        m["hotkey"] := DetectKey(text)
    }
    Macros.Push(m)
    return true
}

DetectKey(code) {
    if RegExMatch(code, "m)^[ \t]*([~$*!+^#<>]*[^\s:;,{}`"'(]+)[ \t]*::", &r)
        return r[1]
    return "undefined"
}

; returns only the file name; the file lives in <install folder>\config\scripts
NewScriptFile() {
    DirCreate(ScriptsDir)
    return "script_" FormatTime(, "yyyyMMdd_HHmmss") "_" Random(1000, 9999) ".ahk"
}

ScriptPath(m) => ScriptsDir "\" m["file"]
