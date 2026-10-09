; ============ backup / restore: everything in one .mmbackup file ============
; a text file: the settings (macros.ini) as they are + every script file in base64
;   [[macros.ini]]  <ini lines>   [[script name.ahk]]  <base64>   [[end]]

OnBackupBtn(*) {
    r := ThemedAsk(_T("Backup"), _T("Backup and restore"), _T("Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file.")
        , [[_T("Cancel"), "", "btn"], [_T("Restore..."), "restore", "btn"], [_T("Create backup..."), "create", "btnprimary"]], false)
    if (r = "create")
        CreateBackup()
    else if (r = "restore")
        RestoreBackup()
}

CreateBackup() {
    Save()
    path := FileSelect("S16", A_Desktop "\Macro Manager backup " FormatTime(, "yyyy-MM-dd") ".mmbackup", _T("Create backup"), _T("Macro Manager backup (*.mmbackup)"))
    if (path = "")
        return
    if !RegExMatch(path, "i)\.mmbackup$")
        path .= ".mmbackup"
    try {
        WriteBackup(path)
        ThemedNote(_T("Backup saved to:`n{1}", path))
    } catch as e
        ThemedNote(_T("The backup could not be saved:`n{1}", e.Message), , true)
}

WriteBackup(path) {
    t := "; Macro Manager backup - restore it with the Backup... button in the app (or drop this file onto its window)`n"
    t .= "; version=" AppVersion " date=" FormatTime(, "yyyy-MM-dd HH:mm") " macros=" Macros.Length "`n"
    t .= "[[macros.ini]]`n" StrReplace(FileRead(IniFile), "`r", "") "`n"
    for m in Macros {
        if (m["type"] != "script" || m["file"] = "" || !FileExist(ScriptPath(m)))
            continue
        data := FileRead(ScriptPath(m), "RAW")
        t .= "[[script " m["file"] "]]`n" B64Enc(data, data.Size) "`n"
    }
    t .= "[[end]]`n"
    WriteText(path, t)
}

B64Enc(buf, size) {
    if !size
        return ""
    n := 0
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &n)   ; BASE64 | NOCRLF
    out := Buffer(n * 2, 0)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size, "UInt", 0x40000001, "Ptr", out, "UInt*", &n)
    return StrGet(out, n, "UTF-16")
}

; reads a backup file: Map("ini", text, "scripts", Map(name -> base64), "date", .., "count", ..) or throws
ReadBackup(path) {
    text := FileRead(path, "UTF-8")
    res := Map("ini", "", "scripts", Map(), "date", "", "count", "?")
    if RegExMatch(text, "m)^; version=\S* date=(.+?) macros=(\d+)", &mm)
        res["date"] := mm[1], res["count"] := mm[2]
    cur := "", buf := ""
    for line in StrSplit(text, "`n", "`r") {
        if RegExMatch(line, "^\[\[(.+)\]\]$", &h) {
            if (cur = "macros.ini")
                res["ini"] := buf
            else if (SubStr(cur, 1, 7) = "script ")
                res["scripts"][SubStr(cur, 8)] := buf
            cur := h[1], buf := ""
            continue
        }
        if (cur != "")
            buf .= (cur = "macros.ini") ? line "`r`n" : line
    }
    if (!InStr(res["ini"], "[main]") || !RegExMatch(res["ini"], "m)^count=\d+"))
        throw Error("not a Macro Manager backup")
    return res
}

RestoreBackup(path := "") {
    if (path = "") {
        path := FileSelect(1, A_Desktop, _T("Restore from backup"), _T("Macro Manager backup (*.mmbackup)"))
        if (path = "")
            return
    }
    try b := ReadBackup(path)
    catch {
        ThemedNote(_T("This is not a Macro Manager backup file:`n{1}", path), , true)
        return
    }
    if (ThemedAsk(_T("Restore from backup"), _T("Restore this backup?")
        , _T("All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}", b["date"], b["count"], ConfigDir "\backup-before-restore.mmbackup")
        , [[_T("Restore"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
        return
    try {
        Save()
        WriteBackup(ConfigDir "\backup-before-restore.mmbackup")
        for m, pid in Procs
            try ProcessClose(pid)
        ; script files: a script that is not already on this PC (same name, same content) asks again before it runs
        DirCreate(ScriptsDir)
        known := Map()
        tmp := A_Temp "\MacroManager-restore.tmp"
        for name, b64 in b["scripts"] {
            if !RegExMatch(name, "^[\w .()\-]+\.ahk$")
                continue
            B64ToFile(b64, tmp)
            dest := ScriptsDir "\" name
            known[name] := FileExist(dest) && Sha256(dest) = Sha256(tmp)
            FileCopy(tmp, dest, 1)
        }
        try FileDelete(tmp)
        ini := RestoreTrust(b["ini"], known)
        f := FileOpen(IniFile ".tmp", "w", "UTF-16")
        f.Write(ini)
        f.Close()
        if FileExist(IniFile)
            FileCopy(IniFile, IniFile ".bak", 1)
        FileMove(IniFile ".tmp", IniFile, 1)
    } catch as e {
        ThemedNote(_T("The backup could not be restored:`n{1}", e.Message), , true)
        return
    }
    Reload()
}

; script macros whose file was not on this PC before: trusted=0 and switched off (they ask before the first run)
RestoreTrust(ini, known) {
    out := "", sect := []
    Flush() {
        isScript := false, file := ""
        for l in sect {
            if (l = "type=script")
                isScript := true
            if (SubStr(l, 1, 5) = "file=")
                file := SubStr(l, 6)
        }
        if (isScript && !(known.Has(file) && known[file])) {
            keep := []
            for l in sect
                if (SubStr(l, 1, 8) != "trusted=" && SubStr(l, 1, 8) != "enabled=")
                    keep.Push(l)
            keep.Push("trusted=0", "enabled=0")
            sect := keep
        }
        for l in sect
            out .= l "`r`n"
        sect := []
    }
    for line in StrSplit(ini, "`n", "`r") {
        if (SubStr(line, 1, 1) = "[")
            Flush()
        if (line != "")
            sect.Push(line)
    }
    Flush()
    return out
}
