; ============ installer ============
; Installs "Macro Manager.ahk" + "Macro Manager.exe" (a copy of the AutoHotkey interpreter with our icon and name,
; so Explorer, the taskbar and Task Manager show Macro Manager instead of AutoHotkey).
Bootstrap() {
    reg := "HKCU\Software\MacroManager"
    prev := RegRead(reg, "InstallDir", "")
    if (prev != "")
        InitLang(prev "\config\macros.ini")             ; an existing install keeps its language
    if (prev != "" && FileExist(prev "\config\.installed") && FindInstalled(prev) != "") {
        r := MsgBox(_T("Macro Manager is already installed in:`n{1}`n`nYes = update the installed copy with this file and start it`nNo = just start the installed copy`nCancel = exit", prev), _T("Macro Manager setup"), "YesNoCancel 64")
        if (r = "Cancel")
            return
        if (r = "Yes") {
            try {
                InstallProgram(prev)
            } catch as e {
                MsgBox _T("Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}", e.Message), _T("Macro Manager setup"), 48
            }
        }
        LaunchInstalled(prev)
        return
    }

    dir := DirSelect("*" A_ProgramFiles, 1, _T("Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there."))
    if (dir = "")
        return
    target := RTrim(dir, "\") "\MacroManager"
    compiled := false
    try {
        DirCreate(target "\config\assets")
        B64ToFile(IconB64(), target "\config\assets\app.ico")
        B64ToFile(LogoB64(), target "\config\assets\logo.png")
        compiled := InstallProgram(target)
        FileAppend "installed", target "\config\.installed"
        RegWrite(target, "REG_SZ", reg, "InstallDir")
    } catch as e {
        MsgBox _T("Installation failed:`n{1}", e.Message), _T("Macro Manager setup"), 16
        return
    }

    icon := target "\config\assets\app.ico"
    if (MsgBox(_T("Create a Start Menu shortcut?"), _T("Macro Manager setup"), "YesNo 32") = "Yes")
        MakeShortcut(A_Programs "\Macro Manager.lnk", target, icon)
    if (MsgBox(_T("Create a Desktop shortcut?"), _T("Macro Manager setup"), "YesNo 32") = "Yes")
        MakeShortcut(A_Desktop "\Macro Manager.lnk", target, icon)
    MsgBox _T("Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config", target), _T("Macro Manager setup"), 64
    LaunchInstalled(target)
}

; copies this script into `target` as "Macro Manager.ahk" next to "Macro Manager.exe" = branded copy of the
; AutoHotkey interpreter that runs it.  (Older versions could compile the app into the .exe with Ahk2Exe;
; such an install can't take updates, so it is turned into this layout here and in InstallUpdate.)
; returns true when the branded .exe exists
InstallProgram(target) {
    old := FindInstalled(target)
    src := target "\Macro Manager.ahk"
    exe := target "\Macro Manager.exe"
    ico := target "\config\assets\app.ico"
    if (old != "" && old != src && !InStr(old, ".exe") && FileExist(old))
        try FileDelete(old)                         ; script from an older install under another name
    hadCompiled := FileExist(exe) && !FileExist(src)
    FileCopy(A_ScriptFullPath, src, 1)
    if (hadCompiled && FileExist(exe)) {            ; a compiled exe can't run the new .ahk
        try FileDelete(exe)
        catch
            FileMove(exe, exe ".bak", 1)            ; still running: a running .exe can be renamed, not deleted
    }
    if !FileExist(exe) {
        FileCopy(A_AhkPath, exe, 1)
        if !PatchExe(exe, ico)
            try FileDelete(exe)
    }
    return FileExist(exe) ? true : false
}

; path of the installed program inside `dir` (exe preferred), or ""
FindInstalled(dir) {
    if FileExist(dir "\Macro Manager.exe")
        return dir "\Macro Manager.exe"
    if FileExist(dir "\Macro Manager.ahk")
        return dir "\Macro Manager.ahk"
    loop files dir "\*.ahk"                          ; older installs used the original file name
        return A_LoopFileFullPath
    return ""
}

; the AutoHotkey v2 interpreter (a compiled Macro Manager can't use its own A_AhkPath for scripts)
AhkExe() {
    if !A_IsCompiled
        return A_AhkPath
    p := RegRead("HKCU\Software\MacroManager", "AhkPath", "")
    if (p != "" && FileExist(p))
        return p
    for c in [A_ProgramFiles "\AutoHotkey\v2\AutoHotkey64.exe", A_ProgramFiles "\AutoHotkey\v2\AutoHotkey32.exe"]
        if FileExist(c)
            return c
    return ""
}

; [program, arguments] that start the installed copy
LaunchParts(dir) {
    ahk := dir "\Macro Manager.ahk"
    exe := dir "\Macro Manager.exe"
    if FileExist(ahk)
        return [FileExist(exe) ? exe : AhkExe(), '"' ahk '"']
    if FileExist(exe)
        return [exe, ""]
    f := FindInstalled(dir)
    return f = "" ? ["", ""] : [AhkExe(), '"' f '"']
}

LaunchInstalled(dir) {
    lp := LaunchParts(dir)
    if (lp[1] != "")
        Run('"' lp[1] '" ' lp[2], dir)
}

; ============ branded interpreter copy ============
; "Macro Manager.exe" = copy of AutoHotkey64.exe with our icon + version info (name, company),
; so Explorer, the taskbar and Task Manager show Macro Manager instead of AutoHotkey.
PatchExe(exe, ico) {
    h := 0
    try {
        f := FileOpen(ico, "r")
        icoBuf := Buffer(f.Length)
        f.RawRead(icoBuf, f.Length)
        f.Close()
        count := NumGet(icoBuf, 4, "UShort")
        if (count < 1)
            return false

        ; what does the interpreter already contain? (icon groups + version language)
        groups := []
        curLang := 0
        NameCb(hm, t, nm, lp) {
            if (nm < 65536)
                groups.Push(nm)
            return 1
        }
        LangCb(hm, t, nm, lang, lp) {
            curLang := lang
            return 0                                   ; first language is enough
        }
        hMod := DllCall("LoadLibraryExW", "Str", exe, "Ptr", 0, "UInt", 2, "Ptr")   ; LOAD_LIBRARY_AS_DATAFILE
        if !hMod
            return false
        cb1 := CallbackCreate(NameCb, , 4)
        DllCall("EnumResourceNamesW", "Ptr", hMod, "Ptr", 14, "Ptr", cb1, "Ptr", 0)  ; RT_GROUP_ICON
        langs := Map()
        cb2 := CallbackCreate(LangCb, , 5)
        for gid in groups {
            curLang := 0
            DllCall("EnumResourceLanguagesW", "Ptr", hMod, "Ptr", 14, "Ptr", gid, "Ptr", cb2, "Ptr", 0)
            langs[gid] := curLang ? curLang : 1033
        }
        curLang := 0
        DllCall("EnumResourceLanguagesW", "Ptr", hMod, "Ptr", 16, "Ptr", 1, "Ptr", cb2, "Ptr", 0)   ; RT_VERSION
        vLang := curLang ? curLang : 1033
        DllCall("FreeLibrary", "Ptr", hMod)
        CallbackFree(cb1)
        CallbackFree(cb2)
        if !groups.Length {
            groups.Push(159)
            langs[159] := 1033
        }

        h := DllCall("BeginUpdateResourceW", "Str", exe, "Int", 0, "Ptr")
        if !h
            return false

        ; icon images (RT_ICON 3) with new ids
        loop count {
            e := 6 + 16 * (A_Index - 1)
            size := NumGet(icoBuf, e + 8, "UInt"), off := NumGet(icoBuf, e + 12, "UInt")
            if !DllCall("UpdateResourceW", "Ptr", h, "Ptr", 3, "Ptr", 5000 + A_Index, "UShort", 1033, "Ptr", icoBuf.Ptr + off, "UInt", size)
                throw Error("icon")
        }
        ; the icon groups (RT_GROUP_ICON 14) now point at our images
        grp := Buffer(6 + 14 * count, 0)
        NumPut("UShort", 0, "UShort", 1, "UShort", count, grp)
        loop count {
            e := 6 + 16 * (A_Index - 1), g := 6 + 14 * (A_Index - 1)
            DllCall("RtlMoveMemory", "Ptr", grp.Ptr + g, "Ptr", icoBuf.Ptr + e, "UPtr", 12)
            NumPut("UShort", 5000 + A_Index, grp, g + 12)
        }
        for gid in groups
            if !DllCall("UpdateResourceW", "Ptr", h, "Ptr", 14, "Ptr", gid, "UShort", langs[gid], "Ptr", grp, "UInt", grp.Size)
                throw Error("group")

        ; version info (name, description, company)
        vi := BuildVersionInfo()
        if !DllCall("UpdateResourceW", "Ptr", h, "Ptr", 16, "Ptr", 1, "UShort", vLang, "Ptr", vi, "UInt", vi.Size)
            throw Error("version")
        ok := DllCall("EndUpdateResourceW", "Ptr", h, "Int", 0)
        h := 0
        return ok != 0
    } catch {
        if h
            DllCall("EndUpdateResourceW", "Ptr", h, "Int", 1)      ; discard
        return false
    }
}

BufCat(parts*) {
    total := 0
    for p in parts
        total += IsObject(p) ? p.Size : 0
    out := Buffer(total, 0)
    pos := 0
    for p in parts {
        if (IsObject(p) && p.Size) {
            DllCall("RtlMoveMemory", "Ptr", out.Ptr + pos, "Ptr", p.Ptr, "UPtr", p.Size)
            pos += p.Size
        }
    }
    return out
}

BufPad4(b) {
    if (Mod(b.Size, 4) = 0)
        return b
    out := Buffer(b.Size + 4 - Mod(b.Size, 4), 0)
    DllCall("RtlMoveMemory", "Ptr", out.Ptr, "Ptr", b.Ptr, "UPtr", b.Size)
    return out
}

; one VS_VERSIONINFO node: length, value length, type, key, (padded) value, (padded) children
VerNode(key, value, vtype, vlen, children := "") {
    k := Buffer(StrPut(key, "UTF-16") * 2, 0)
    StrPut(key, k, "UTF-16")
    hdr := Buffer(6, 0)
    NumPut("UShort", 0, "UShort", vlen, "UShort", vtype, hdr)
    b := BufPad4(BufCat(hdr, k))
    b := BufPad4(BufCat(b, value))
    b := BufCat(b, children)
    NumPut("UShort", b.Size, b, 0)
    return b
}

VerString(key, val) {
    v := Buffer(StrPut(val, "UTF-16") * 2, 0)
    StrPut(val, v, "UTF-16")
    return BufPad4(VerNode(key, v, 1, v.Size // 2))
}

BuildVersionInfo() {
    fixed := Buffer(52, 0)
    NumPut("UInt", 0xFEEF04BD, "UInt", 0x10000, "UInt", 0x10000, "UInt", 0, "UInt", 0x10000, "UInt", 0, "UInt", 0x3F
         , "UInt", 0, "UInt", 0x40004, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0, fixed)
    strs := BufCat(VerString("CompanyName", "VAVROS"), VerString("FileDescription", "Macro Manager")
        , VerString("FileVersion", "1.0.0.0"), VerString("InternalName", "Macro Manager")
        , VerString("OriginalFilename", "Macro Manager.exe"), VerString("ProductName", "Macro Manager")
        , VerString("ProductVersion", "1.0.0.0"))
    st := BufPad4(VerNode("040904B0", "", 1, 0, strs))
    sfi := BufPad4(VerNode("StringFileInfo", "", 1, 0, st))
    tr := Buffer(4, 0)
    NumPut("UInt", 0x04B00409, tr)
    vr := BufPad4(VerNode("Translation", tr, 0, 4))
    vfi := BufPad4(VerNode("VarFileInfo", "", 1, 0, vr))
    return VerNode("VS_VERSION_INFO", fixed, 0, 52, BufCat(sfi, vfi))
}

; ============ uninstaller ============
; adds the app to Windows "Apps & features" (per-user) and remembers where it lives
RegisterUninstall() {
    k := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManager"
    cmd := A_IsCompiled ? '"' A_ScriptFullPath '" /uninstall' : '"' A_AhkPath '" "' A_ScriptFullPath '" /uninstall'
    if !A_IsCompiled
        try RegWrite(A_AhkPath, "REG_SZ", "HKCU\Software\MacroManager", "AhkPath")
    try {
        RegWrite("Macro Manager", "REG_SZ", k, "DisplayName")
        RegWrite("Macro Manager", "REG_SZ", k, "Publisher")
        RegWrite(cmd, "REG_SZ", k, "UninstallString")
        RegWrite(A_ScriptDir, "REG_SZ", k, "InstallLocation")
        RegWrite(FileExist(IconFile) ? IconFile : (A_IsCompiled ? A_ScriptFullPath : A_AhkPath), "REG_SZ", k, "DisplayIcon")
        RegWrite(1, "REG_DWORD", k, "NoModify")
        RegWrite(1, "REG_DWORD", k, "NoRepair")
        RegWrite(A_ScriptDir, "REG_SZ", "HKCU\Software\MacroManager", "InstallDir")
    }
}

UninstallApp(fromArg := false) {
    dir := A_ScriptDir
    if (StrLen(dir) <= 3 || !FileExist(dir "\config\.installed")) {
        MsgBox _T("This doesn't look like an installed copy, nothing was removed."), _T("Uninstall Macro Manager"), 48
        return false
    }
    if (Mb(_T("Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}", dir), _T("Uninstall Macro Manager"), "YesNo 48 Default2") != "Yes") {
        if fromArg
            LaunchInstalled(dir)
        return false
    }
    ; offer a backup of the macros before everything is deleted
    if (!Macros.Length && FileExist(IniFile))
        try Load()
    if Macros.Length {
        r := Mb(_T("Export all your macros to a folder before uninstalling?"), _T("Uninstall Macro Manager"), "YesNoCancel 32")
        if (r = "Cancel") {
            if fromArg
                LaunchInstalled(dir)
            return false
        }
        if (r = "Yes") {
            bdir := DirSelect("*" A_Desktop, 3, _T("Choose a folder for the backup"))
            if (bdir = "") {
                if fromArg
                    LaunchInstalled(dir)
                return false
            }
            MsgBox _T("{1} macro(s) exported to:`n{2}", ExportAllTo(bdir), bdir), _T("Uninstall Macro Manager"), 64
        }
    }
    ; stop imported scripts started by the manager
    for m, pid in Procs
        try ProcessClose(pid)
    ; remove registry entries and the Start Menu / Desktop shortcuts
    try RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManager")
    try RegDeleteKey("HKCU\Software\MacroManager")
    try FileDelete(A_Programs "\Macro Manager.lnk")
    try FileDelete(A_Desktop "\Macro Manager.lnk")
    MsgBox _T("Macro Manager has been uninstalled.`nThe folder will be removed in a moment."), _T("Uninstall Macro Manager"), 64
    ; a separate hidden process deletes the folder after this app has exited
    Run(A_ComSpec ' /c ping -n 3 127.0.0.1 >nul & rmdir /s /q "' dir '"', A_Temp, "Hide")
    ExitApp
}
