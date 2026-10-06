#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName Macro Manager
;@Ahk2Exe-SetDescription Macro Manager
;@Ahk2Exe-SetProductName Macro Manager
;@Ahk2Exe-SetInternalName Macro Manager
;@Ahk2Exe-SetOrigFilename Macro Manager.exe
;@Ahk2Exe-SetCompanyName VAVROS
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-UpdateManifest 1
#SingleInstance Force
Persistent
SendMode "Event"
SetKeyDelay -1, -1
ProcessSetPriority "High"

; ============ always run as administrator ============
if !A_IsAdmin {
    try {
        args := ""
        for a in A_Args
            args .= ' "' a '"'
        if A_IsCompiled
            Run '*RunAs "' A_ScriptFullPath '"' args
        else
            Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"' args
    }
    ExitApp
}

; ============ first run: install into a folder chosen by the user ============
if !FileExist(A_ScriptDir "\config\.installed") {
    Bootstrap()
    ExitApp
}

; ============ global state ============
ConfigDir := A_ScriptDir "\config"
IniFile := ConfigDir "\macros.ini"
ScriptsDir := ConfigDir "\scripts"
AssetsDir := ConfigDir "\assets"
IconFile := AssetsDir "\app.ico"
LogoFile := AssetsDir "\logo.png"
LogoWideFile := AssetsDir "\logo_wide.png"
CbIL := 0
CbDC := 0
CbSz := 28
CbDarkFile := AssetsDir "\cb_dark.png"
CbLightFile := AssetsDir "\cb_light.png"
BadgeMainFile := AssetsDir "\badge_main.png"     ; yellow ! with glow (banner / dark window / light window)
BadgeDkFile := AssetsDir "\badge_dk.png"
BadgeLtFile := AssetsDir "\badge_lt.png"
SwOffFile := AssetsDir "\switch_off.png"
SwOnFile := AssetsDir "\switch_on.png"
AssetVersion := "7"     ; bump when the embedded logo/icon change
AppVersion := "1.12.5"     ; bump on every release (must match version.json in the GitHub repo)
UpdAvail := false       ; a newer version exists (icon in the banner turns green)
UpdInfo := Map()
UpdRepo := "vavr0s/macro-manager"
UpdBranch := "beta"      ; the test (beta) build uses "beta"
UpdateUrl := "https://raw.githubusercontent.com/" UpdRepo "/" UpdBranch "/version.json"      ; fallback (cached by GitHub for ~5 min)
UpdEtag := ""            ; GitHub API answers "not modified" for free when nothing changed
UpdBody := ""
; release notes of THIS version (shown in Help; also used as the text of the update prompt). No double quotes here.
ReleaseNotes := "BETA build - for testing.`n- When a macro belongs to several profiles and you change it, the app now asks: apply the change to all of its profiles, or only to the current one.`n- New Help topic: Support."
SeenVer := AppVersion   ; last version whose release notes the user has opened (! shown while different)
AutoUpd := true         ; check for updates when the app starts
Macros := []
MasterOn := true
Registered := []
Populating := false
DarkOn := false
HoverHwnd := 0
Recording := false
DragOut := false
DragEnd := 0
DragStart := Map("row", 0, "x", 0, "y", 0, "last", "")
MasterKey := ""        ; optional hotkey that toggles "All macros"
TogReg := []           ; registered toggle hotkeys
Profiles := ["Default"]
CurProfile := "Default"
ProfPop := 0
ProfClosed := 0
HelpGui := 0
View := []             ; macros of the current profile = rows of the list
SortCol := 0
SortAsc := true
Rec := {ih: 0, mode: "", cb: 0, down: [], chord: [], toks: [], mpend: [], btn: 0, undo: 0}
MouseToks := ["RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
Roles := Map()         ; control hwnd -> role (hint / skip / code) used by the theme
Procs := Map()          ; macro -> PID of running imported script
EnsureAssets()          ; logo + icon are embedded in this file

; started from Windows "Apps & features" (or manually) with /uninstall
for a in A_Args {
    if (a = "/uninstall") {
        UninstallApp(true)
        ExitApp
    }
}
RegisterUninstall()

Load()

; ============ main window ============
Main := Gui(, "Macro Manager (beta)")
Main.SetFont("s9", "Segoe UI")
try {
    Main.AddPicture("x10 y8 w820 h72", LogoWideFile)      ; black rounded banner with the logo
    Main.SetFont("s16 bold cD0AE6B", "Segoe UI")
    ttl := Main.AddText("x100 y29 w200 BackgroundTrans", "Macro Manager")
    Roles[ttl.Hwnd] := "skip"
    Main.SetFont("s9 norm cC9B27C", "Segoe UI")
    lbl := Main.AddText("x600 y50 w105 Right BackgroundTrans", "Dark mode")
    Roles[lbl.Hwnd] := "skip"
    swPic := Main.AddPicture("x712 y44", DarkOn ? SwOnFile : SwOffFile)
    swPic.OnEvent("Click", OnDarkToggle)
    swPic.OnEvent("DoubleClick", OnDarkToggle)
    lbl2 := Main.AddText("x600 y18 w105 Right BackgroundTrans", "All macros")
    Roles[lbl2.Hwnd] := "skip"
    swMaster := Main.AddPicture("x712 y12", MasterOn ? SwOnFile : SwOffFile)
    swMaster.OnEvent("Click", OnMaster)
    swMaster.OnEvent("DoubleClick", OnMaster)
    bProf := AddBtn(Main, "x330 y27 w150 h28", ProfBtnText(), ProfileMenu, "btnbanner")
    Main.SetFont("s13 bold", "Segoe UI")
    bHelp := AddBtn(Main, "x782 y14 w28 h28", "?", OpenHelp, "btnbanner")                 ; help on top, updates below (same size)
    bBadge := Main.AddPicture("x810 y12 w16 h16", BadgeMainFile)      ; yellow ! with glow beside the help icon: release notes not read yet
    Roles[bBadge.Hwnd] := "skip"
    bBadge.Visible := (SeenVer != AppVersion)
    Main.SetFont("s12 norm", "Segoe MDL2 Assets")
    bUpd := AddBtn(Main, "x782 y46 w28 h28", Chr(0xE896), OnUpdIcon, "btnupd0")      ; download arrow: grey = up to date, green = new version
    Main.SetFont("s9 norm cC9B27C", "Segoe UI")
    Main.SetFont("s9 norm c000000", "Segoe UI")
}
try {
    TraySetIcon(IconFile)
    A_IconTip := "Macro Manager BETA v" AppVersion
}
SetWinIcon(Main.Hwnd)
; column header strip (flat, themed) - the list itself has no native header
hdrNames := ["Name", "Key", "Application", "Type"]
hdrW := [300, 130, 240, 150]
hdrCtl := []
hx := 10
for i, nm in hdrNames {
    h := Main.AddText("x" hx " y92 w" hdrW[i] " h28 +0x200", "  " nm)
    Roles[h.Hwnd] := "hdr"
    h.OnEvent("Click", SortBy.Bind(i))
    hdrCtl.Push(h)
    hx += hdrW[i]
}
LV := Main.AddListView("x10 y120 w820 r13 -Hdr -E0x200 Checked Multi", ["Name", "Key", "Application", "Type"])
LV.SetFont("s10")
LV.Opt("+LV0x10020")                          ; LVS_EX_DOUBLEBUFFER (no flicker on repaint) + full-row select                             ; full-row select: the whole row can be picked / dragged, not only the Name cell
LV.ModifyCol(1, 300)
LV.ModifyCol(2, 130)
LV.ModifyCol(3, 240)
LV.ModifyCol(4, 130)
LV.OnNotify(-12, OnLvDraw)                   ; custom draw: themed selection, no dotted focus rectangle
SendMessage(0x127, 0x10001, 0, LV.Hwnd)      ; WM_CHANGEUISTATE: hide focus rectangles
bAdd := AddBtn(Main, "x10 y+14 w130 h36", "Add", (*) => EditMacro(0), "btnprimary")
bCopy := AddBtn(Main, "x+8 yp w130 h36", "Copy", OnCopyBtn)
bEdit := AddBtn(Main, "x+8 yp w130 h36", "Edit", OnEditBtn)
bDel := AddBtn(Main, "x+8 yp w130 h36", "Delete", OnDelBtn, "btndanger")
bExport := AddBtn(Main, "x+8 yp w130 h36", "Export...", OnExportBtn)
bImport := AddBtn(Main, "x+8 yp w130 h36", "Import...", OnImportBtn)
bUp := AddBtn(Main, "x10 y+8 w130 h36", "Move up", (*) => MoveRow(-1))
bDown := AddBtn(Main, "x+8 yp w130 h36", "Move down", (*) => MoveRow(1))
bExpAll := AddBtn(Main, "x+8 yp w150 h36", "Export all...", OnExportAll)
MKst := Map("key", MasterKey)
bMKey := AddBtn(Main, "x+8 yp w386 h36", KeyLabel("All macros toggle key:  ", MKst["key"]), (*) => CaptureKey(bMKey, MKst, "key", true, "All macros toggle key:  ", OnMasterKey))
AddHint(Main, "x10 y+16 w700", "Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit).")
bUninst := AddBtn(Main, "x740 yp w90 h28", "Uninstall", (*) => UninstallApp(), "btnghost")
verTxt := AddHint(Main, "x726 y+4 w104 Center", "beta v" AppVersion)

LV.OnEvent("ItemCheck", OnCheck)
OnMessage(0x201, OnLvLDown)
OnMessage(0x203, OnLvLDown)                ; mouse down on the list: drag over rows = select, drag out = export
DllCall("ole32\OleInitialize", "Ptr", 0)
LV.OnEvent("DoubleClick", OnDouble)
Main.OnEvent("Close", OnMainClose)
Main.OnEvent("DropFiles", OnDropFiles)
; the app runs elevated: allow drops from the (non-elevated) Explorer (WM_DROPFILES, WM_COPYDATA, WM_COPYGLOBALDATA)
for msg in [0x233, 0x4A, 0x49]
    DllCall("ChangeWindowMessageFilterEx", "Ptr", Main.Hwnd, "UInt", msg, "UInt", 1, "Ptr", 0)

A_TrayMenu.Delete()
A_TrayMenu.Add("Open window", (*) => (Main.Show(), AutoCheck(120000)))
A_TrayMenu.Add("Check for updates...", OnUpdIcon)
A_TrayMenu.Add("Check for updates at start", ToggleAutoUpd)
if AutoUpd
    A_TrayMenu.Check("Check for updates at start")
A_TrayMenu.Add("Uninstall...", (*) => UninstallApp())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Open window"
OnExit(ExitHandler)

Refresh()
Apply()
ApplyTheme(Main)
SetTimer(HoverTick, 40)
Main.Show()
SetTimer(() => AutoCheck(), -4000)
SetTimer(AutoCheck, 60000)         ; background check (every 2 minutes)
return

; ============ window handlers ============
OnMainClose(*) {
    Main.Hide()
    return 1
}

ExitHandler(*) {
    for m, pid in Procs
        try ProcessClose(pid)
    try DirDelete(A_Temp "\MacroManager-drag", 1)
}

OnCheck(ctrl, item, checked) {
    if Populating
        return
    View[item]["enabled"] := checked ? 1 : 0
    Save()
    Apply()
}

OnDouble(ctrl, row) {
    if row
        EditMacro(row)
}

SelRows() {
    rows := []
    r := 0
    while (r := LV.GetNext(r))
        rows.Push(r)
    return rows
}

SelMacros() {
    out := []
    for r in SelRows()
        out.Push(View[r])
    return out
}

; selects the rows that show these macros
SelectMacros(list) {
    LV.Modify(0, "-Select")
    first := 0
    for i, m in View {
        for x in list {
            if (x == m) {
                LV.Modify(i, "Select")
                if !first
                    first := i
                break
            }
        }
    }
    if first
        LV.Modify(first, "Focus Vis")
}

OnCopyBtn(*) {
    list := SelMacros()
    if !list.Length
        return
    made := []
    for src in list {
        base := RegExReplace(src["name"], "\s*\(\d+\)$", "")
        n := 1
        loop {
            newName := base " (" n ")"
            taken := false
            for m in Macros {
                if (m["name"] = newName) {
                    taken := true
                    break
                }
            }
            if !taken
                break
            n++
        }
        c := src.Clone()
        c["name"] := newName
        c["enabled"] := 0
        c["tkey"] := ""
        if (src["type"] = "script") {
            c["file"] := NewScriptFile()
            try FileCopy(ScriptPath(src), ScriptPath(c), 1)
        }
        Macros.InsertAt(IndexOf(src) + 1, c)
        made.Push(c)
    }
    Save()
    Apply()
    Refresh()
    SelectMacros(made)
}

OnEditBtn(*) {
    row := LV.GetNext()
    if row
        EditMacro(row)
}

OnDelBtn(*) {
    list := SelMacros()
    if !list.Length
        return
    msg := list.Length = 1 ? "Delete macro `"" list[1]["name"] "`"?" : "Delete " list.Length " selected macros?"
    if Mb(msg, "Macro Manager", "YesNo 32") != "Yes"
        return
    for m in list {
        StopScript(m)
        if (m["type"] = "script" && m["file"] != "")
            try FileDelete(ScriptPath(m))
        Macros.RemoveAt(IndexOf(m))
    }
    Save()
    Apply()
    Refresh()
}

OnMaster(*) {
    global MasterOn
    MasterOn := !MasterOn
    swMaster.Value := MasterOn ? SwOnFile : SwOffFile
    Save()
    Apply()
}

OnMasterKey() {
    global MasterKey
    MasterKey := MKst["key"]
    Save()
    Apply()
}

ToggleMaster(*) {
    global MasterOn
    MasterOn := !MasterOn
    swMaster.Value := MasterOn ? SwOnFile : SwOffFile
    Save()
    Apply()
    Toast("All macros: " (MasterOn ? "ON" : "OFF"))
}

ToggleMacro(m, *) {
    m["enabled"] := m["enabled"] ? 0 : 1
    Save()
    Apply()
    Refresh()
    Toast(m["name"] ": " (m["enabled"] ? "ON" : "OFF"))
}

Toast(txt) {
    ToolTip(txt)
    SetTimer(() => ToolTip(), -1200)
}

MoveRow(d) {
    sel := SelMacros()
    if !sel.Length
        return
    flag := Map()
    for m in sel
        flag[m] := true
    order := View.Clone()
    n := order.Length
    if (d < 0) {
        loop n {
            i := A_Index
            if (i > 1 && flag.Has(order[i]) && !flag.Has(order[i - 1])) {
                t := order[i - 1], order[i - 1] := order[i], order[i] := t
            }
        }
    } else {
        i := n - 1
        while (i >= 1) {
            if (flag.Has(order[i]) && !flag.Has(order[i + 1])) {
                t := order[i + 1], order[i + 1] := order[i], order[i] := t
            }
            i--
        }
    }
    ; write the new order back into the full list (the view items keep their slots)
    idx := []
    for m in View
        idx.Push(IndexOf(m))
    for k, m in order
        Macros[idx[k]] := m
    Save()
    Refresh()
    SelectMacros(sel)
}

; click on a column header: stable sort of the macro list (again = reverse)
SortBy(col, *) {
    global SortCol, SortAsc
    SortAsc := (SortCol = col) ? !SortAsc : true
    SortCol := col
    field := ["name", "hotkey", "app", "type"][col]
    ; insertion sort (stable, the list is small)
    loop Macros.Length - 1 {
        i := A_Index + 1
        cur := Macros[i]
        j := i - 1
        while (j >= 1 && SortCmp(Macros[j][field], cur[field], SortAsc)) {
            Macros[j + 1] := Macros[j]
            j--
        }
        Macros[j + 1] := cur
    }
    for i, h in hdrCtl
        h.Text := "  " hdrNames[i] (i = col ? (SortAsc ? "  ▲" : "  ▼") : "")
    Save()
    Refresh()
}

; true when a must move behind b
SortCmp(a, b, asc) {
    c := DllCall("shlwapi\StrCmpLogicalW", "Str", a, "Str", b, "Int")
    return asc ? c > 0 : c < 0
}

TypeLabel(t) => t = "move" ? "Move + actions" : (t = "seq" ? "Sequence" : "Script (.ahk)")

Refresh() {
    global Populating
    Populating := true
    LV.Delete()
    global View
    View := []
    for m in Macros
        if InProfile(m)
            View.Push(m)
    for m in View
        LV.Add(m["enabled"] ? "Check" : "", m["name"], m["hotkey"], (m["app"] = "" || m["type"] = "script") ? "(everywhere)" : m["app"], TypeLabel(m["type"]))
    LV.ModifyCol(4, "AutoHdr")                    ; last column fills the rest, so nothing stale is left on the right
    Populating := false
}

; ============ export / import ============
OnExportBtn(*) {
    sel := SelMacros()
    if !sel.Length {
        MsgBox "Select a macro first.", "Macro Manager", 48
        return
    }
    if (sel.Length > 1) {
        dir := DirSelect("*" A_Desktop, 3, "Choose a folder for the " sel.Length " exported macros")
        if (dir = "")
            return
        MsgBox ExportAllTo(dir, sel) " macro(s) exported to:`n" dir, "Macro Manager", 64
        return
    }
    m := sel[1]
    if (m["type"] != "script") {
        k := Trim(m["hotkey"])
        if (k = "" || k = "undefined") {
            MsgBox "Set a trigger key for this macro first.", "Macro Manager", 48
            return
        }
    }
    code := ExportCode(m)
    if (code = "") {
        MsgBox "Nothing to export (script file is missing).", "Macro Manager", 48
        return
    }
    safe := RegExReplace(m["name"], '[\\/:*?"<>|]', "_")
    path := FileSelect("S16", A_Desktop "\" safe ".ahk", "Export macro", "AutoHotkey scripts (*.ahk)")
    if (path = "")
        return
    if !RegExMatch(path, "i)\.ahk$")
        path .= ".ahk"
    WriteText(path, code)
    MsgBox "Exported to:`n" path, "Macro Manager", 64
}

OnExportAll(*) {
    if !Macros.Length {
        MsgBox "There are no macros to export.", "Macro Manager", 48
        return
    }
    dir := DirSelect("*" A_Desktop, 3, "Choose a folder for the exported macros")
    if (dir = "")
        return
    n := ExportAllTo(dir)
    MsgBox n " macro(s) exported to:`n" dir, "Macro Manager", 64
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
    files := FileSelect("M3", , "Import macros", "AutoHotkey scripts (*.ahk)")
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
        Toast("Drop .ahk files to import them")
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
        MsgBox "Can't read:`n" path, "Macro Manager", 48
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
            && Mb("This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work.`n`nImport anyway?", "Macro Manager", "YesNo 48") != "Yes")
            return false
        m["type"] := "script"
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

; ============ installer ============
; Installs "Macro Manager.ahk" and - when Ahk2Exe is available - compiles it to "Macro Manager.exe"
; (own icon + name in Explorer, taskbar and Task Manager instead of AutoHotkey's).
Bootstrap() {
    reg := "HKCU\Software\MacroManagerBeta"
    prev := RegRead(reg, "InstallDir", "")
    if (prev != "" && FileExist(prev "\config\.installed") && FindInstalled(prev) != "") {
        r := MsgBox("Macro Manager is already installed in:`n" prev "`n`nYes = update the installed copy with this file and start it`nNo = just start the installed copy`nCancel = exit", "Macro Manager setup", "YesNoCancel 64")
        if (r = "Cancel")
            return
        if (r = "Yes") {
            try {
                InstallProgram(prev)
            } catch as e {
                MsgBox "Couldn't update the installed copy (is it running?). Starting the installed version.`n`n" e.Message, "Macro Manager setup", 48
            }
        }
        LaunchInstalled(prev)
        return
    }

    dir := DirSelect("*" A_ProgramFiles, 1, "Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there.")
    if (dir = "")
        return
    target := RTrim(dir, "\") "\MacroManagerBeta"
    compiled := false
    try {
        DirCreate(target "\config\assets")
        B64ToFile(IconB64(), target "\config\assets\app.ico")
        B64ToFile(LogoB64(), target "\config\assets\logo.png")
        compiled := InstallProgram(target)
        FileAppend "installed", target "\config\.installed"
        RegWrite(target, "REG_SZ", reg, "InstallDir")
    } catch as e {
        MsgBox "Installation failed:`n" e.Message, "Macro Manager setup", 16
        return
    }

    icon := target "\config\assets\app.ico"
    if (MsgBox("Create a Start Menu shortcut?", "Macro Manager setup", "YesNo 32") = "Yes")
        MakeShortcut(A_Programs "\Macro Manager Beta.lnk", target, icon)
    if (MsgBox("Create a Desktop shortcut?", "Macro Manager setup", "YesNo 32") = "Yes")
        MakeShortcut(A_Desktop "\Macro Manager Beta.lnk", target, icon)
    MsgBox "Installed to:`n" target "`n`nYour macros and settings are stored in:`n" target "\config", "Macro Manager setup", 64
    LaunchInstalled(target)
}

; copies this script into `target` and brands the program:
;  1) Ahk2Exe available -> compiled "Macro Manager.exe" (the script is inside it)
;  2) otherwise -> "Macro Manager.exe" = branded copy of the AutoHotkey interpreter that runs "Macro Manager.ahk"
; returns true when a branded .exe exists
InstallProgram(target) {
    old := FindInstalled(target)
    src := target "\Macro Manager.ahk"
    exe := target "\Macro Manager.exe"
    ico := target "\config\assets\app.ico"
    if (old != "" && old != src && !InStr(old, ".exe") && FileExist(old))
        try FileDelete(old)                         ; script from an older install under another name
    hadCompiled := FileExist(exe) && !FileExist(src)
    ahk2exe := FindAhk2Exe()
    if (ahk2exe != "" && FileExist(exe))
        FileDelete(exe)                             ; errors when the old copy is still running
    FileCopy(A_ScriptFullPath, src, 1)
    if (ahk2exe != "") {
        cmd := '"' ahk2exe '" /in "' src '" /out "' exe '" /icon "' ico '" /base "' A_AhkPath '" /silent'
        try RunWait(cmd, target, "Hide")
        if FileExist(exe) {
            try FileDelete(src)                     ; the exe contains the script
            ; script macros still need an interpreter: keep a private copy next to the app
            try {
                DirCreate(target "\runtime")
                FileCopy(A_AhkPath, target "\runtime\AutoHotkey.exe", 1)
                RegWrite(target "\runtime\AutoHotkey.exe", "REG_SZ", "HKCU\Software\MacroManagerBeta", "AhkPath")
            }
            return true
        }
    }
    if (hadCompiled && FileExist(exe))
        FileDelete(exe)                             ; a compiled exe can't run the new .ahk
    if !FileExist(exe) {
        FileCopy(A_AhkPath, exe, 1)
        if !PatchExe(exe, ico)
            try FileDelete(exe)
    }
    return FileExist(exe) ? true : false
}

FindAhk2Exe() {
    SplitPath(A_AhkPath, , &d)
    cand := [d "\..\Compiler\Ahk2Exe.exe", d "\Compiler\Ahk2Exe.exe", A_ProgramFiles "\AutoHotkey\Compiler\Ahk2Exe.exe"]
    try cand.Push(RegRead("HKLM\SOFTWARE\AutoHotkey", "InstallDir") "\Compiler\Ahk2Exe.exe")
    for c in cand
        if FileExist(c)
            return c
    return ""
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
    p := RegRead("HKCU\Software\MacroManagerBeta", "AhkPath", "")
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

; ============ branded interpreter copy (used when Ahk2Exe is not available) ============
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
    k := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManagerBeta"
    cmd := A_IsCompiled ? '"' A_ScriptFullPath '" /uninstall' : '"' A_AhkPath '" "' A_ScriptFullPath '" /uninstall'
    if !A_IsCompiled
        try RegWrite(A_AhkPath, "REG_SZ", "HKCU\Software\MacroManagerBeta", "AhkPath")
    try {
        RegWrite("Macro Manager (beta)", "REG_SZ", k, "DisplayName")
        RegWrite("Macro Manager", "REG_SZ", k, "Publisher")
        RegWrite(cmd, "REG_SZ", k, "UninstallString")
        RegWrite(A_ScriptDir, "REG_SZ", k, "InstallLocation")
        RegWrite(FileExist(IconFile) ? IconFile : (A_IsCompiled ? A_ScriptFullPath : A_AhkPath), "REG_SZ", k, "DisplayIcon")
        RegWrite(1, "REG_DWORD", k, "NoModify")
        RegWrite(1, "REG_DWORD", k, "NoRepair")
        RegWrite(A_ScriptDir, "REG_SZ", "HKCU\Software\MacroManagerBeta", "InstallDir")
    }
}

UninstallApp(fromArg := false) {
    dir := A_ScriptDir
    if (StrLen(dir) <= 3 || !FileExist(dir "\config\.installed")) {
        MsgBox "This doesn't look like an installed copy, nothing was removed.", "Uninstall Macro Manager", 48
        return false
    }
    if (Mb("Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n" dir, "Uninstall Macro Manager", "YesNo 48 Default2") != "Yes") {
        if fromArg
            LaunchInstalled(dir)
        return false
    }
    ; offer a backup of the macros before everything is deleted
    if (!Macros.Length && FileExist(IniFile))
        try Load()
    if Macros.Length {
        r := Mb("Export all your macros to a folder before uninstalling?", "Uninstall Macro Manager", "YesNoCancel 32")
        if (r = "Cancel") {
            if fromArg
                LaunchInstalled(dir)
            return false
        }
        if (r = "Yes") {
            bdir := DirSelect("*" A_Desktop, 3, "Choose a folder for the backup")
            if (bdir = "") {
                if fromArg
                    LaunchInstalled(dir)
                return false
            }
            MsgBox ExportAllTo(bdir) " macro(s) exported to:`n" bdir, "Uninstall Macro Manager", 64
        }
    }
    ; stop imported scripts started by the manager
    for m, pid in Procs
        try ProcessClose(pid)
    ; remove registry entries and the Start Menu / Desktop shortcuts
    try RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManagerBeta")
    try RegDeleteKey("HKCU\Software\MacroManagerBeta")
    try FileDelete(A_Programs "\Macro Manager Beta.lnk")
    try FileDelete(A_Desktop "\Macro Manager Beta.lnk")
    MsgBox "Macro Manager has been uninstalled.`nThe folder will be removed in a moment.", "Uninstall Macro Manager", 64
    ; a separate hidden process deletes the folder after this app has exited
    Run(A_ComSpec ' /c ping -n 3 127.0.0.1 >nul & rmdir /s /q "' dir '"', A_Temp, "Hide")
    ExitApp
}

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
    code := StrReplace(code, "@APP@", StrReplace(m["app"], '"', ""))

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
    s := ""
    for k in StrSplit(t, "+")
        s .= "{" k " down}"
    return s
}

Up(t) {
    s := ""
    for k in StrSplit(t, "+")
        s .= "{" k " up}"
    return s
}

Active() => GetKeyState(trig, "P") && (app = "" || WinActive("ahk_exe " app))

#HotIf app = "" || WinActive("ahk_exe " app)
)"
}

TplMove() {
    return "
(
@HOT@:: {
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    while (rep ? Active() : n < acts.Length) {
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            Send Down(dir)
            Sleep g1
            Send Down(key)
            Sleep g2
            Send Up(dir)
            Sleep g3
            Send Up(key)
            di := di >= dirs.Length ? 1 : di + 1
        } else {
            Send Down(key)
            Sleep g2
            Send Up(key)
        }
        Sleep ge
        ai := ai >= acts.Length ? 1 : ai + 1
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
            Sleep s[3]
        }
        if (!rep)
            stop := true
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

; ============ macro editor ============
EditMacro(idx) {
    isNew := !idx
    m := isNew ? Defaults() : View[idx]
    if isNew
        m["profiles"] := CurProfile
    pv := Map("v", m["profiles"])
    origProfs := m["profiles"]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", isNew ? "New macro" : "Edit macro")
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)             ; same banner as the main window
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", isNew ? "New macro" : "Edit macro")
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }

    g.AddText("x10 y100 w130 +0x200 h26", "Name")
    eName := g.AddEdit("x150 y100 w250 h26", m["name"])
    g.AddText("x410 y100 w55 +0x200 h26", "Profiles")
    bProfs := AddBtn(g, "x470 y100 w180 h26", ProfLabel(pv["v"]), (*) => (pv["v"] := PickProfiles(g, pv["v"]), bProfs.Text := ProfLabel(pv["v"])))
    g.AddText("x10 y136 w130 +0x200 h26", "Trigger key")
    st := Map("key", m["hotkey"], "tkey", m["tkey"])
    bKey := AddBtn(g, "x150 y136 w250 h26", st["key"], (*) => CaptureKey(bKey, st, "key", false))
    g.AddText("x410 y136 w55 +0x200 h26", "Toggle")
    bTog := AddBtn(g, "x470 y136 w180 h26", KeyLabel("", st["tkey"]), (*) => CaptureKey(bTog, st, "tkey", true))
    g.AddText("x10 y172 w130 +0x200 h26", "Only in app (exe)")
    eApp := g.AddEdit("x150 y172 w420 h26", m["app"])
    bApp := AddBtn(g, "x580 y172 w70 h26", "Select", (*) => (eApp.Value := PickApp(g, eApp.Value)))

    ; type + run mode: flat segmented buttons instead of native controls
    tsel := m["type"] = "move" ? 1 : (m["type"] = "seq" ? 2 : 3)
    rsel := m["repeat"] ? 2 : 1
    g.AddText("x10 y208 w130 +0x200 h26", "Type")
    tb := []
    for i, nm in ["Move + actions", "Sequence", "Script (.ahk)"]
        tb.Push(AddBtn(g, "x" (150 + (i - 1) * 170) " y208 w160 h26", nm, SetType.Bind(i), i = tsel ? "btnprimary" : "btn"))
    rl := g.AddText("x10 y244 w130 +0x200 h26", "Run")
    rb := []
    for i, nm in ["Once per key press", "Repeat while key is held"]
        rb.Push(AddBtn(g, "x" (150 + (i - 1) * 255) " y244 w245 h26", nm, SetRun.Bind(i), i = rsel ? "btnprimary" : "btn"))

    ; --- group: move + actions ---
    mv := []
    mv.Push(g.AddText("x10 y292 w130 +0x200 h26", "Directions (optional)"))
    eDirs := g.AddEdit("x150 y292 w420 h26", m["dirs"])
    rb1 := AddBtn(g, "x580 y292 w70 h26", "Record", (*) => StartListRec(eDirs, rb1))
    mv.Push(eDirs, rb1)
    mv.Push(g.AddText("x10 y328 w130 +0x200 h26", "Actions in order"))
    eActs := g.AddEdit("x150 y328 w420 h26", m["actions"])
    rb2 := AddBtn(g, "x580 y328 w70 h26", "Record", (*) => StartListRec(eActs, rb2))
    mv.Push(eActs, rb2)
    mv.Push(g.AddText("x10 y364 w130 +0x200 h26", "Delays (ms)"))
    e1 := g.AddEdit("x150 y364 w110 h26 Number", m["g1"])
    e2 := g.AddEdit("x275 y364 w110 h26 Number", m["g2"])
    e3 := g.AddEdit("x400 y364 w110 h26 Number", m["g3"])
    e4 := g.AddEdit("x525 y364 w110 h26 Number", m["ge"])
    mv.Push(e1, e2, e3, e4)
    mv.Push(AddHint(g, "x150 y394 w120 h32", "dir↓ → action↓"))
    mv.Push(AddHint(g, "x275 y394 w120 h32", "action↓ → dir↑"))
    mv.Push(AddHint(g, "x400 y394 w120 h32", "dir↑ → action↑"))
    mv.Push(AddHint(g, "x525 y394 w120 h32", "between cycles"))
    mv.Push(AddHint(g, "x10 y434 w640", "Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4)."))

    ; --- group: sequence ---
    eSeq := g.AddEdit("x10 y292 w640 h120 Multi WantReturn", StrReplace(m["seq"], "|", "`n"))
    sq := [eSeq, AddHint(g, "x10 y418 w640", "One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)")]

    ; --- group: script ---
    code := ""
    if (m["type"] = "script" && m["file"] != "" && FileExist(ScriptPath(m)))
        code := FileRead(ScriptPath(m), "UTF-8")
    eCode := g.AddEdit("x10 y292 w640 h150 Multi WantReturn -Wrap HScroll", code)
    eCode.SetFont("s9", "Consolas")
    Roles[eCode.Hwnd] := "code"
    sc := [eCode, AddHint(g, "x10 y448 w640", "Runs as its own process while this macro is checked (AutoHotkey v2).")]

    SetSeg(arr, n) {
        for i, c in arr {
            Roles[c.Hwnd] := (i = n) ? "btnprimary" : "btn"
            PaintBtn(c.Hwnd, false)
        }
    }
    SetType(n, *) {
        tsel := n
        SetSeg(tb, n)
        Toggle()
    }
    SetRun(n, *) {
        rsel := n
        SetSeg(rb, n)
    }
    Toggle(*) {
        t := tsel
        for c in mv
            c.Visible := (t = 1)
        for c in sq
            c.Visible := (t = 2)
        for c in sc
            c.Visible := (t = 3)
        bKey.Enabled := (t != 3)
        eApp.Enabled := (t != 3)
        bApp.Enabled := (t != 3)
        rl.Visible := (t != 3)
        for c in rb
            c.Visible := (t != 3)
    }

    ; a macro that belongs to several profiles: apply the change everywhere, or only in the current profile
    Detach() {
        if (isNew || !HasProf(pv["v"], CurProfile) || StrSplit(pv["v"], "|").Length < 2)
            return true
        r := MsgBox("This macro is in several profiles (" ProfLabel(pv["v"]) ").`n`n"
            . "Yes = apply the change to all of them`n"
            . "No = only in the current profile (" CurProfile "); the other profiles keep (or get) the old, unchanged version",
            "Macro Manager", 0x23)
        if (r = "Cancel")
            return false
        if (r = "Yes")
            return true
        old := m
        StopScript(old)
        rest := []
        for p in StrSplit(pv["v"], "|")
            if (p != CurProfile)
                rest.Push(p)
        old["profiles"] := JoinProfs(rest)
        m := old.Clone()
        m["file"] := ""
        pv["v"] := CurProfile
        isNew := true
        return true
    }

    Commit(*) {
        FinishRec()
        t := tsel
        nm := Trim(eName.Value)
        if (t = 3) {
            txt := eCode.Value
            if (Trim(txt) = "") {
                MsgBox "Paste or write a script first.", "Macro Manager", 48
                return
            }
            if !Detach()
                return
            StopScript(m)
            if (m["file"] = "" || !FileExist(ScriptPath(m)))
                m["file"] := NewScriptFile()
            WriteText(ScriptPath(m), txt)
            m["hotkey"] := DetectKey(txt)
            m["type"] := "script"
        } else {
            key := Trim(st["key"])
            if (key = "") {
                MsgBox "Enter a trigger key.", "Macro Manager", 48
                return
            }
            if !Detach()
                return
            StopScript(m)
            m["hotkey"] := key
            m["app"] := Trim(eApp.Value)
            m["type"] := t = 1 ? "move" : "seq"
            m["dirs"] := Trim(eDirs.Value)
            m["actions"] := Trim(eActs.Value)
            m["g1"] := Num(e1.Value)
            m["g2"] := Num(e2.Value)
            m["g3"] := Num(e3.Value)
            m["ge"] := Num(e4.Value)
            lines := ""
            for l in StrSplit(eSeq.Value, "`n", "`r")
                if (Trim(l) != "")
                    lines .= (lines = "" ? "" : "|") Trim(l)
            m["seq"] := lines
            m["repeat"] := rsel = 2 ? 1 : 0
        }
        m["name"] := nm = "" ? "Macro" : nm
        m["profiles"] := pv["v"] = "" ? CurProfile : pv["v"]
        m["tkey"] := st["tkey"]
        if isNew
            Macros.Push(m)
        g.Destroy()
        Save()
        Apply()
        Refresh()
    }

    AddBtn(g, "x450 y482 w95 h34", "Save", Commit, "btnprimary")
    AddBtn(g, "x555 y482 w95 h34", "Cancel", (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Close", (*) => (FinishRec(), g.Destroy()))
    Toggle()
    ApplyTheme(g)
    ShowOver(g, "w660 h532", Main)
}

Num(v) => IsInteger(v) ? Integer(v) : 0

; ============ saving / loading ============
Defaults() {
    return Map("name", "New macro", "hotkey", "LCtrl", "app", "", "type", "move", "enabled", 0,
        "dirs", "A,D", "actions", "1,2,3,4", "g1", 25, "g2", 30, "g3", 20, "ge", 10,
        "seq", "down A 25|tap 4 20|up A 5", "repeat", 1, "file", "", "tkey", "", "profiles", "")
}

Load() {
    global MasterOn, DarkOn, MasterKey, Profiles, CurProfile, AutoUpd, SeenVer
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
        for k in ["enabled", "g1", "g2", "g3", "ge", "repeat"]
            m[k] := Num(m[k])
        m["file"] := RegExReplace(m["file"], "^.*\\", "")   ; keep only the file name
        if (Trim(m["profiles"]) = "")
            m["profiles"] := Profiles[1]
        Macros.Push(m)
    }
}

Save() {
    try FileDelete IniFile
    FileAppend "", IniFile, "UTF-16"
    IniWrite MasterOn ? 1 : 0, IniFile, "main", "master"
    IniWrite DarkOn ? 1 : 0, IniFile, "main", "dark"
    IniWrite AutoUpd ? 1 : 0, IniFile, "main", "autoupdate"
    IniWrite SeenVer, IniFile, "main", "seenver"
    IniWrite MasterKey, IniFile, "main", "masterkey"
    IniWrite JoinProfs(Profiles), IniFile, "main", "proflist"
    IniWrite CurProfile, IniFile, "main", "profile"
    IniWrite Macros.Length, IniFile, "main", "count"
    for i, m in Macros
        for k, v in m
            IniWrite v, IniFile, "m" i, k
}

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
            MsgBox "Macro `"" m["name"] "`" can't be enabled (key `"" trig "`"):`n" e.Message, "Macro Manager", 48
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
    want := MasterOn && m["enabled"] && InProfile(m)
    running := Procs.Has(m)
    if (want && !running)
        StartScript(m)
    else if (!want && running)
        StopScript(m)
}

StartScript(m) {
    if (m["file"] = "" || !FileExist(ScriptPath(m))) {
        MsgBox "Script file for `"" m["name"] "`" is missing.", "Macro Manager", 48
        return
    }
    ahk := AhkExe()
    if (ahk = "") {
        MsgBox "Script macros need AutoHotkey v2 installed (not found).", "Macro Manager", 48
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
MakeRun(m, trig) => (*) => (m["type"] = "move" ? RunMove(m, trig) : RunSeq(m, trig))

Active(m, trig) => GetKeyState(TrigMain(trig), "P") && (m["app"] = "" || WinActive("ahk_exe " m["app"]))

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
        return "*" pre Trim(parts[parts.Length])
    }
    return "*" trig
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

; ============ embedded logo / icon ============
EnsureAssets() {
    try {
        DirCreate(AssetsDir)
        verFile := AssetsDir "\version.txt"
        cur := FileExist(verFile) ? Trim(FileRead(verFile)) : ""
        if (cur != AssetVersion || !FileExist(IconFile) || !FileExist(LogoFile) || !FileExist(SwOnFile) || !FileExist(LogoWideFile) || !FileExist(CbDarkFile) || !FileExist(BadgeMainFile)) {
            B64ToFile(IconB64(), IconFile)
            B64ToFile(LogoB64(), LogoFile)
            B64ToFile(SwOffB64(), SwOffFile)
            B64ToFile(SwOnB64(), SwOnFile)
            B64ToFile(LogoWideB64(), LogoWideFile)
            B64ToFile(CbDarkB64(), CbDarkFile)
            B64ToFile(CbLightB64(), CbLightFile)
            B64ToFile(BadgeMainB64(), BadgeMainFile)
            B64ToFile(BadgeDkB64(), BadgeDkFile)
            B64ToFile(BadgeLtB64(), BadgeLtFile)
            WriteText(verFile, AssetVersion)
        }
    }
}

B64ToFile(b64, path) {
    size := 0
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
    buf := Buffer(size)
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0)
    f := FileOpen(path, "w")
    f.RawWrite(buf, size)
    f.Close()
}

SetWinIcon(hwnd) {
    try {
        big := LoadPicture(IconFile, "w48 h48 Icon3", &t)
        small := LoadPicture(IconFile, "w16 h16 Icon1", &t)
        SendMessage(0x80, 1, big, hwnd)
        SendMessage(0x80, 0, small, hwnd)
    }
}

MakeShortcut(lnk, target, icon) {
    try {
        lp := LaunchParts(target)
        FileCreateShortcut(lp[1], lnk, target, lp[2], "Macro Manager", icon)
    }
}

IconB64() {
    return "
(Join
AAABAAQAEBAAAAEAIABXAgAARgAAACAgAAABACAA/AUAAJ0CAAAwMAAAAQAgAD8KAACZCAAAAAAAAAEAIAA4fAAA2BIAAIlQTkcNChoKAAAADUlIRFIAAAAQ
AAAAEAgGAAAAH/P/YQAAAh5JREFUeJylk09IVFEUxn/nvvfmvXkzOuOQOTpKKBRZWBZau6KlYZuSWjS4MaJtEEnboF1BBNGiyKC0WkSBSBBBS7OibKBF0UTg
H0prpgRTaXynzYzOBBXhhQ/uvd855+N+9xxEoCkZ7436oaznOgXPtQPPtfUPCDzXKUT9ULYpGe8VAVLJeNpxLAX+C45jaSoZTxPxQ1PFy0KJFBEF1IioKe5F
KgoUAI34oSk8114hbMv8U7k8xnNtNZSteHWYC6f3EwmHEBF2tNazs7UBI4LvOZw/1UVNdbg8hZUCtmX4kp/nw0SOdPd2VJX+vr309+0hUOVodzsfp/PM5uex
rVVd8VxHF5d+koiFOdK1jczbT6QPtPN49D3NqRqMMeTnFmjbWMfgyGs6tqa48zDD128/CLsONigiQu77Ah1bUuzrbKY66rGrrZEzFx9R5bs8Gejj0uAoxw51
EHIsLt9+ioigaOkJCsDVe895k52h5+QQqfUxEjEfY4TMu8/cePCSqZk5rtwdozzHBlAFI8JYZpITh3cT9UNcv/+C4z2dLAcBQyPjNNRWsaE+zrPMJEaEQLXS
RDGCqnJz+BUD53porIuxuaWWtk1JkuuquHb2ILeGxwlUESPlJtq6uFSo+JraRIQgUFoaE4hAdiKHMcJsbr4iznNtKhoJUPlLE/3Oea6txrLMdLHgcskaEUFE
MEWUzroqvgxgWWZ67cO01nH+BVfz8R7qs73iAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAFw0lEQVR4nMWXf2xUVRbH
P/e+N7TT6XQ67fTHYmux0wqUFikGqltSsRVFEESrJUuA3ZUYVMgaBcXf0bj4h5KqUBN/rImsLCsrGMVFG5BQV1rWVRMXdhH5JaKyBAtlSy2dzrx39o/3Zmxl
BjArcpKTvNxzz/mee+75cZ/CIQOwbr6q4sJP935754neyHX9/bFhIngAxf9HohTRIUPMA/6MtL+OKct79vX3dh6MY3Kz88HYyuKmUDDzsMdjCHBO2OMxJBTM
PDy2srgJSGBTPeqCxoDfG98YA2wF8lMyYLu2JeD3SvWoCxoBuOGKqqJQ0HcMsJVyNpxLdjHsUNB37IYrqoooH5bXbBo6fvJzCj6AY6ahpXxYXjP5If9+Nzz2
z+iADdj5If9+HYtaxYBSKbJdKYVWyQtBKYVKIdOnkblYKha1ik0BM+kuF0BEENdDkcFy+eFCQg9sVxa3kYwETJ3Ke4DSoiBvrZhN46RRiIDWasDpoLQoh3Bx
Dkp9r6O1QgRmNFTw1orZlBYFB9k8BSvZoi2C1ooDh44T6bd49I4Gsv3piDgnwo3G4t9OYMm8OicyKn5ayMpM49E7Goj0Wxw4dBytVSIiZ+WAUmBojWXZPNyy
iZyAl1tvGoeIYBoa2xaqLi6kvibMxHGljBnxC2zbkYkIt9x4KXk5Ph5u2YRl2RhakyIAyR0QgWjMQmvF7i86Wf3OduY3jWdofhaWZQNw99xaunsidHWf5K65
tQBYtk1Bbia3z6zhzxv+ye4DnWitiMasU/InQcFAhtMgQJRSAkhpUY5MGFsihtMfJBT0yf7WxfLkoskCSMNlYelsf1Curx8p100cIcc6HpKJ4y4SQH7/u0ny
xcbFUhjKFEAMQ0ttdYmEi3PcRqTinVGCgQxJWgE9vRGW3dNEZ1cvGzv28Mamf7N89TYW/2YCy1d1MLVuOHsPHmXD+58jImzffZiFsy7n8NEe5k6vZvmqDiL9
FnfNraW+JkxBro9pC15NGgAVDGRI1397UThuGYZz93fO+SVLbqmjty8KwJ6DRxk+LMS6jf9iTesOhub7Wb9lFwBT6obT8sA0vjnSjWlqZi56jZVPNFJ2YQil
FM0rP6B5ZXvCdhwrGMg4NQfEdi7rL607OH6ijw1/+5xHWt4jEonR3ROh8epKlIL1W3ZhGBqtFa1bd7P5w32MKsunZfU2CnJ9rHl3B2tat9Pd08dr7+4YZDtl
DriOidZOLjy1aLJ8um6huLNCKsL50r5qvqx9epZorRIMyCtLG6XjT/PF5x2SsPfJ6wtk2T3XDrI5ECsYyJCUDiiQkaV5cqjtPrlt5viE7Pr6kdLZ/qBcU1ue
WLtyfKkcbX9Imq6pSqzdetM4+U/b/VIRzhd1GgeSNyJbUErx2f5v2bxtH7OnVZOeZuIxDVq37uHD7V9z77w6TEOjlGLJvDo+2fkN69s+wzQ0aUMM5kyvZvPf
97Jz3xGUUtjJwk+KPgCg3Lb78hsfc3FJLpMuLyMas4j0x1j6whbGjhzK5AnlNFxWSs3oYpa+2EZfJEbMsqmvCTPiohB/WPfxIFtJcX5YBYOE7iR8+7k5BPzp
vN22C5/Xw/Nr/sFjC6+iqrwAyxb2fNnJ/c9s5LaZ4+k9GWVq3XBOfBdh2oI/YsupQ+u0VTAoPEph2TYvrfuIjHQPM+or+NWU0cyZPobmlVvJzc6gMDeTZa98
wKypo5k15RJm1Ffg96Xx0tqPsGxJOYTOKgIDyef1YNvOaPameejqPsnLj9+IaWh+/cBasrO89EWiKJyJ+N3JaGrQARFIWgVnyxXhfKksK/jRemdsxUm9HhDJ
+JXu3HfkjHvORKZyHqNndCSZwfiTK55kZwua0IeYNj3GV67uj1R3gFM9t06r516B6TG+0oHM9DdNQyucl+rPRbZpaBXITH9TV5YUNmdnebtwq+5cI7sYOjvL
21VZUtgMnOdfs/P9cxovnPP2e/4/QElNAKLtwyYAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAMAAAADAIBgAAAFcC+YcAAAoGSURBVHic3Zp5cJRF
GsZ/3XNkch+QO0ASQiQkhnCEhBtEFFyD5SISwANXVkXU3dIq19ott2r/2611aw+1VpfSRQULSJYSRTEoIHIEuQIJBEiAAMZAuJLJJJnM1b1/fJPZcAQSBIF9
qrpqaqbnfZ+n3+737e7vE3TBrFmYSkrwAUwZM3j0ebtjblube5LL7U1VSocCgp8GWkrRFmQ1Hw8NtX7TJzL84/XbDpVfyvEizJqFCaBo4pCMnMzEkoTYCE+I
zaKFEBq4JU0IoUNsFp0QG+HJyUwsKZo4JKMr18vITygYOCM1uU9zkNXcacQLKMPYT9v8/pWfgw6ymnVqcp/mCQUDZ1wkIkB+ZEZRckKUz/9HTxcjt7z5uXgA
nZwQ5ZswMqOoK3dRNDU3LTUlpgVQwq/4dmx+bio1JaalaGpuGiAQArIzE1ZZLKaAytu8eSwWk87OTFglBDBtQnZ+fN9wH+C7naZNt1EwOPri+4b7pk3Izpen
zjbPtzs6JKC15raHn6O2OzrkqbPN82Vrm3uyy+2Bny7H3wgIl9tDa5t7svR4PQP8quQtJtUbSK3B4/UMMCtFCIAQgfB0CyFACiNQSuse9Df6Xmtu9t6uwVUp
QsxX73oxtAZfLxZKTxdVb+12RY8ESClQSnNPQTozp+bQ2u7ibx9t4/Q5ByAuI2qMvCY2OhQhBGcutF61X9/oUF5+YiwRYTZK1+1n445jAZ/X5NYTAZ1+a06c
Z+yw/iyYmc9zj45CayOclxn1h/jlJ8fx6i/GX7PfM4/k88ysUYwZ1p/aE+cv8nmDBGhMUlJ/2s7fl5bT7HAyY3IWd6X1RSmNlP9j1zly6SkxTB+fyX1jB5GZ
epV+/WL4+dRsmh1O/rG0nPpGOyYpezz9epx5lFYIISgpq6L2xHliIkN4YU7hlQUDL8wrxGY1YzGZeHHe6G77PV9cQGx0KLUnzrPyyyqEECitekrr2gKEEIFV
L4Wgtd3N4tKdeLw+phRmUJDbD6U0JikCozosK5FpYzNxexUer+LewoHk56QEonBpP4/Hx+LSnbQ53UghAlNOXGne9VaA9qc1k0kCBoHVGw+yp/oHwkKsLJw9
CuGv751YNKeQ8NAgDh47Q/XR04QGW3l+TsFl62Dh7AIiw4PYXd3A6o0H/VNMYzJJtO5ZFutWQKez1ORowkKs+HwKnz8rKKV5Z+VOnC4vY/IGcG/hQJTSKKWZ
NCqd8cPTcLm9vPHvzfzpvc243D7G5vVnSmFGoN/4EalMGJlGe4eHd0t2BDKOT2l8PkVosJXU5GiDy/UI6Cwsg9P6Uvav+by2YCIjhiQFBGz47ihb9xwnJNjC
wuICTFIQbLPw0rzRBNvMfLu7jh1V9ew52MCmncewBVl4vrgAs1kihGDRnAJCbBa2VZxk/fajKKURwIjsZF5bMIGyxfPJyYgzuMjuJXRbB3xKIwSs23aEF+YW
8uK80TxWlMfhY2dZ/91RyrbW8tcPt5I3OJHhWUk8dM8QyrbWkhwXjsvt5c1l2wO23l6+ncKh/RmelcT9YwfR3uGh4O5+tDndvPVxOdERwTxelMfE/DQGp8US
FR5MZc1p1m6pRQiuWg+uWsiklPh8io8+3cvgtDicTg+5dyVSmGfUgl0H6rG3dhASbOVXj41m9YZqlqyuYNjgRCoONgRGruLgKdZuqWH2tLt5ad4YlFKYpOCr
8iPsrm7grd8VMe/BPM5caKPF0UGQ1czSNRX4fAqTyeBwXQKUUgjgi801PPvoKJJiIzjecIF2p4fsjHhmTM6iye7E7uigf1I0T88cyeKSncTFhAYylxDGHP7n
8u1MHZ1BclwEWmta2lz8+f3NTMpP45H7cti0q44Qm4V+CVHUN9pZs+kwws/hqoN8tR+1NqLgaHPxyfpqwkKsKKV59g+f8PTrq1hcupPT5x3ERIbQ1u7mqYdH
EB0RTMNZB8K/dTBSp+RYfRNLP6vAYpYEBZn5z1cH+P60nUED+vDkb0tZ8PtVeL2K8FArn6yvxu7oQPqz0XULMEQYFkq/OkB9o52s9DjuHZ3Bpl11vP7m1zz0
4lJ+/cc1NLU4SYoNZ8EjI4Er53CX24vVauZ8czvvrNyBEILFpbso21rLlIKBZA+K54fGFkrX7Td834i9kNJG7m8408LX5UeQUjDr/hyCbRbMJklLq4vPvz3M
sjV70RpmTs0mPSUapZVRtPyVNSU+gsdnDEcKWLG2klNnHYGiZrOamT09F7MUfL39CPWNLUax+zF14EpYvraKC3Yn2QPjmZSfhtensJhNmEySZZ/vo+bEOeJi
wnhudsH/Qu9fC88+Oor4vmHU1TfxwacVRoXHyDDjhg/g7kHxXLA7Wf5FZW8o9UyAUhopBPuPNFK+7yS2IAuzp+cihMDrzxCONhfvr9qNx6uYPj6TYVmJKKXR
SpOVHkvRpCx8PsWS1XtosjuRUgQKY/EDQwmxWSnfd5Kq2kYjaj2YPj0WACD8KXHF2kraO1yMyklhZHYyQoBJSixmyeoN1VTWnCIyzMaiYmOjp4GFxQXERAZT
ffQMJev2YzFLTFIiBAzLSqRwaD/aOtys+LLqIl83VIDPpxACNu8+TuXhRsJDg3jswaEopXF7vHi8CqfLy7srd9Dh8jIxP40RQ5K4K60v940ZhMvjNTZs7W48
XoXb40Upzdyf5REVbqPy8Gm+3VWHEFw171+KXh0ppZR4vIqSsipGDEmicGh/5jyQS1OLkyCrmcbzrXy5pZbvqr5n4sg0Xpk/Do/XR4jNQvnek6zecJCC3H4k
9A3D5fYSGWZj3PABeLw+VpZV4fFeu3BdCpGSEKXrTzf3+FAPEBps5bO3nyA5PgKr2WQcyqXA7fEx+an36BMVwoq/FONyewGwBVl4/DcrOXmqmU0f/BJbkAWl
FMbNgqK+0U7Rog9pc7qBnvHQGlISonqXhYzKapwJPv58H80tTg7VnaXm+DkO1J7hXFMbTz08nIqDDXyz4xgWkwmzlGyrOM72yu+Z//BwLtid7K9tpOb4OQ7V
naWppZ1la/bS2u42tuW9PNv3KgKBP2EsztBgq/+T8a3WGqvFhL21gyED41jxRjFSSua+uoJ9h43F7fb4LjkXCNqc7oDNHvnvEoFerYFOdDrqDHlXtHd4kFJw
4MgZvtlZh9ViYu+hU0gpaHZ0XNNmb3FdAjrR3YmvcxP3xpItSGkcSenmZqKz//XiRwno3rHxw/Efmrp8c3Nujm/qfahxIXBz74yllLTDjwtjdzAuBG684U6T
UtIuLWbLic571Rvu6eZBCQEWs+WEDAu1bgyyWuD6E8GtgA6yWggLtW6UibFRSyLDbYqe3SPdcvg5ishwm0qMjVpyxz/kk1oj0gfEvZIcH+kATIIrPMa/TeDn
ZkqOj3SkD4h7RWvE/8WD7jv7VYNO3Kkve1yUd+7E123+C0+BBXu5gheMAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAB7
/0lEQVR4nO29d4AUx5n+/6nqnrA5kHPOOSggIVYIJYSibSRZcs4+n/278+U7+xzve77kC75zzpIsW7JyTggECCFyzmHJafPuxO6q3x/VPTPLzsICCyzQjz2A
JnRXd9f71lvv+7zvK+i6kFVVyJ6L0E+Cm/vBtGl9CkXaGmpJa6DrqBkIUYjW1yGErbUuEUKMuliDDnD5Qmu9TQjRhNYOQryL1jHLlstc5e7TIXf3qlWHY7nf
nw/WsSrEokUoQF2kYZ8S4mIP4CSIqiqsk2/YtWP7V6ZD1iTh6hsQzEDrUQj6CiEjwrsCrXMPo+l6lxbg0kbrOZU777RWSTSHEGIbmmXaEotDaXfde5sP1OYc
QFZVIRctwvUO1iXQVaTEvzmO/8a08YNG2xYzlNb3as1MKUWlEAKtdfb2CbQQQgForQWAVlo4ruoq1xXgMoJtSS2k0ABCmL+11hLtyZEAf44qpWuFYIkU4lnH
ZdmqjdVb/eNUVWF3FavgogrKfLCYD08+aUz8a8YP6eVa6g6h9T1a69staUU0Gq1BCJQApUEopUUq7YhkyhWxRArHUbTEkgC4riKRck553gABzgbRsI1lSQCK
CiPYtqQwGiYStnQ4ZGsphRbGKJBaI4UAgcBVblII8aoW4jnLlS8v37jnKMD8+Vg8CSdvcS8kLpYCkJh1XANMn9h/vNDWx7XQH7Wk7KW1RmuNEMI1N1DJWDwl
mmNJmlqSJJJpkikHpbqMJRXgCoaUgkjYJhoJUVIUobgwQmFBWFtSKrOAaUsIgRACV6mjQotHtHB/s3L9gY3eIYT3uuAWwYVWAGL+fKS/4k+bPOAWqeVH0foB
KWXYdRVCCFdKQTrtyqaWhKhvjNMcSxJPpPMfUIC5DE8Z6C60wQpwWSEz1TL/pU/yPWVREA1RXBihvLSAkqKoDoUspZRRBpYlUUqlEOIPSqhHVq3d/wYYi+DJ
J1FcwCl8wRSAd3EueCs+8l+FEHO9FR5LCkdrrFgiJU7UtVBbHyOVbm3K53f4BQjQNdDe/AyHbCrLC+leUURhNKyFwHWVti0p8SyEVzTqr32LIFdWzvuYL8A5
pPe3mjSpf7+wlt8BHhZChJXSypJCu0rL2vqYqKlvprE5kbmBvsYNBD7ApQjhGaY6579Li6N0Ky+msrxQW1IoV2khpZBa6xTwWEqor69bd+AgOXJzPscoT/+V
s8f8+ViYC1BXTRz45TBytZTyk1oTxjg+5LHaZmvTjsNi9/4TNDQlfIcf4DkJAuEPcIlCnyT8WkNDU4Ld+0+wacdhcay22cLIoKs1YSnlJ8PI1VdNHPhlPLnx
ZOi84XxZAGI+yCfBvWpi35FC2/8jLHmbt8d3pMA6UdciDh1ryOztT9aWAQJcjjjZqi2Ihujbs4zuFUVaaVyttW1ZEu2q17RwvrJi/aHt88F6kvPjG+h0BZC7
f7lqwsDPCMG/I0SZ62onZEursTkhDhypp7E5YQYQmPgBrlDkzv3S4ij9e5dTWhzVaUe5liVstG7Qmr9csWHfz+H8+AY6VQH4Axw1qltJWaT4+0KKz7iOQkrh
Oq6yjhxv5PDxhkDgAwTIAyGgT48yevcoxbakq5S2LFuilf55Q7L5q9u21TR1thLoNAXgsZuc6RMHTZFC/0IKOSXtuG7ItmRDU0LsOXCCRNJ49YNVP0CA1siV
iWjEZkj/7pSVRHXacVXItiyl1RqlxadXrq9e48tap5y3Mw7iD2jauIHXS0u8IAQVSmnHktI+fLyB/YfrPOeeR+UNECBAXvgyIgQM6FNBnx5luEo5Ugpba+qU
q+9atWnf0s5SAuesAPyBTJ0w8LO2ED9UWttSGJN/74Eaahtipz9IgAAB8qKyrJDB/buZLYHWlhTCcbT+k9Ub9v2sM5TAOSmAXOEPSfFTx9XasoSOxVNy9/4a
YvFUYO4HCHCW8GWnsCDM0AHdKCwIK9fVwraESCv9uc5QAmetANoKv3JDtiUbWxJi2+5jmJBfIPwBApwLfBmyLMmooT0pLTJ+AduSVmcogbNSAHlWfte2pTxR
1yz2HqgNhD9AgE5ErhIY3L+S7hXF2nGUsi1xzkrgjBVAa+GXP3Vc17UtSx6taRR7W9U/CBAgwPnA4P6V9OpWqh3XVbZlWWmlzloJnBEVeP58rEWLcKaMHzTD
FuInjuuqkG3JE/Vm5RfiQqQWBAhw5UIIwd4DtZyobxYh25KO6ypbiJ9MGT9oxqJFOGdKHe6wAvjGN0wa77QJ/SfYkheV1tq2JI3NiczKH4T4AgQ4v/BlbO+B
WhqbE8K2JEprbUtenDah/4Qnn8T9xjc6Ltcd/aLYvBkxcWKvIinkYwIqpRC6JZ6S2/YYh1+AAAEuHFxXsW3PMVriKSmF0EYm5WMTJ/Yq2rw5U2DktOiQAqiq
MvTDkA7/wJJygtLacV1l7dp3IuPwCxAgwIWDEEYJeDJoKa0dS8oJIR3+wZNP4lZVdWwrcFoF4O/7p4/v/8mQZX0y7biOJYW9+0AN8UTaYy6d+wUFCBCg4/CZ
tfFEmt0HarCksNOO64Qs65PTx/f/ZEf9AadUAN6+X00bN2CYEPIHXqzfOnSskbqGmBeeCKQ/QICLAZ8yXNcQ49CxRkK2ZTmucoWQP5g2bsCwJ59Enc4fcMoP
vb2EFoKfCCmKpBA0NCXE/iN1QZw/QIAuAL+Azv4jdTQ0JYQUAiFFkRD8BNCeDLeLdhWAn3Y4fcLAL9m2NcdVynGVsnbvPxFU7QgQoKtBw+79J3CVslylHNu2
5kyfMPBLTz6Je6qtQHvaQQL6qrGDemHrzVpTZltSVB+qFYePNQZZfQECdDH4MtmnZymD+lZqx1VaCBpwxNgVm6uP0k7Z8bwWwPz5xvRXUn9PSlkhhFCNzQlx
5HhTsO8PEKALwvcHHDneRGNzQgghlJSyQkn9PUB7Mt0GbRSAT/iZPmHwKCl50HFcJQXWvsP1geAHCNDFobVm3+F6pMByHFdJyYPTJwwe1R5BKJ9WkICaPn7g
a9IStwJuTV2LtWvficDxFyBAF4cvo8MGdqdbRZELWMrVr6/cuO82PNnO/X4rjeA5C/S0SYNulJa41XW1q5S2DhxtuHBXECBAgHPGgaMNKKUt19WutMSt0yYN
uhGzFWjlEDzJJJgPoIWrPgdg21LX1LWQTKaD1T9AgEsAflgwmUxTU9eCbUvTzdjItPZkPIOMAjB7/yfVlCmDxggp7lNKa9dV1uHjjRf2CgIECNApOHy80dCE
ldZCivumTBk05sknn2xFDsr8Y+HCKgloy3E/I6WMSind2voWkUgGdN8AAS4l+DThRDJNbX2LkFK6Usqo5bifAbQn60DWCSgAPXny8B62k9yIED2kFGzZdVQ0
NScC8z9AgEsMvsyWFEcZM6yXVkqD1scdOzJ+7dqdx/FkXgJUVVVZAFKn51m21VMIoVpiKdHcYrr3BMIfIMClBV9mm1sStMRSQgihLNvqKXV6HuTIPMCiRYsU
gHTUh7TWWkrBifqWjCkRIECASw/+1v1EfQtSCrTWWjrqQ5Aj895LTZ7cbwRS3KS1Jp12ZW19CxCw/gIEuFThy25tfQvptCu11iDFTZMn9xuB4QNIWVVlHAK2
tmdaliwQQqim5oRIpzu1B2GAAAEuEtJplyaPHmxZssDW9kyAqqoqKXsuWmTUhFIf0lojENQ1xYHA/A8Q4FKHL8N1TXEEXhKfMtuAnosWaQEwYcLAiojWe4QU
ZUqjN24/LJLJ9EUcdoAAAToTkUiI8SP7aCkQWumGpBBDNmzYVycBwkpMkpYsFUKoeCwVCH+AAJcZksk0cS8aIC1ZGlZiEnhRACH0LGGgmuJJzHuB+R8gwOUA
X5ab4kmEEMqIup4FYJtvcI0XOBRNLUnvZ4H3P0CAywNGlptakqDNth/BNQBy2rQ+hVrrMRpwlBaJhDH/g+hfgACXB3xZTiTSOEoLDWitx0yb1qfQFi3WUEL0
AUilHJlKn1O78UsWQogz7m+gdcCT6EqQ8kwfIKgr6Pml0g6plCMLoiGEoA8t1lAbKYYKIaICdCrlCKWunBuSC631FWn1CO+Py+Har9S521EopUmlHAqjIS2E
iGrJUBuL6UIIEELFk2kLuCKLfo4c0p2+PUo6NIk0YEnB9r01HDrWeEknS2nvD8Gl6/URgJCCiSN7U1FagHOablUasISkrjHGxh1Hca8AxeHLdDyZplwUKgGW
tvR0G0SR/6WUc+Wx/6QQKK0ZPaQ7//Lnt+IoEKcRB6U0hdEQry/bwVf/5RWSKeeSEyB/QgzpV86Q/pUsWL77Yg/prCClQCnNvFkj+e5XbiVknzp1XQvQrqao
0OaXT61mw/ajV9SC11rGRZHUmuu8vayIxVPeB1fGzQBzpQJ4Y+kulq7ejy0tEkmHdFp7L5Xzb/NyXE1jS4qZkwZx0zVDTdLUme4/LzL8FfKhOyfxtc/Npl+v
MuAs9tEXEb7glpdE+PjdU4iGLeJxJ+8zS6cVTsolnXBBw56DDTzx2iaUV0338oeR6Vg8hdZaGJnnOilEtijIFaIEW0FrjZCCeDLNr59bTTKVImT567lnGwsj
MP5LCgEa7JDFw/MmUloc9coyXxozyV81x4/oxdxZo+jfu5T7bx0PXFpzQGDGe9eNY5gwog+xeArblhmHbu4LAVoKtNCEQzavL9nBjuoTCCGuKN9B7vMVAim1
psx8oIWrrsw230oZ4X137T4WraymoCCE0ipH4NtOEClNxZXJo/py75wxmVpsXR2+0FhS8tG7JtOttJBYIs3dc0YzZmgPtNZGwXVxCG/r1rtHKQ/MnYijXRCS
jOI++fsAShMOhdh3uI7HXlxnnu8FHvfFhqsU2uMCaE2ZFIJRAI6jRDJpQoCX0irQWRDCKIJfPL2KpuY0lpSZaeRzJ9r8BgkCPnDrOHp7DsSubgUIkxfONRP7
cdM1Q0mlFcpV9Kos4cG5k7CkuCQ2gP5d/tCtYxkxoBvJpIPZvUjaE2stNLYteeL1jRz0OlxdKWFA/zKTSQfHUSb4Ixh12vbgVwqU0kgp2LD9MK8s2UZRURjl
KpNB1bajkoGUJFMuowb24IM3j7uwAz4L+NGKcNjm4XlTKCmM4Kg0UlqkHYdbrh3KtHH9jBXQhX0BUhrBHTawkvtuGkvSdZHCd93mF2ilIBwOsW33MZ55c3PG
ErrSESiAk6A1/Oa51ZyojRGyLaMY2llRhFYIIUk7LvfOGcOwAZVd2oT2nWazrxnKtZMHEE86WEi0MI7NivICHrprIqGQZbY0F3vA7cDUtRB8eO4E+vUqI512
zLWd0qRXSOCxl9dTUx/LWEJXOgIFkAOljPDuqK7hmTc3UhQN4yplYkd5ppbArKqOo+jfs5QH504wE/GCj/z08IW/pCjMR+ZNpCASRmvlOS40UkgSSYeZkwdx
41WDu6xT0yttxeTRvbnzxjEkUg5SeGa/FoDZugmNsdy8rV1BNMSaLYd55Z3tQZXrHAQKIA+EgMdfXs++o/VEwzauzu9YMqxq4yx0HcXN141gwsheXdKE9s3/
u24czeTR/Ugm02aMQiAQCKlBCwqjET58xyRKiiJoupYSyDgwLclD8yZRXhJBuSeP0TwnLUBo6ZkLirSr+P0rG2iOJYMGtzkIFMBJUN7Kt/9II0+8toFw2GrX
B6D9kopCkHIVvbsV89AdE7At2aVMaOmt/r26F/PhOyYhUCAUIEF7+2ZtnOjxVJrpY/tx+8yRXeoaIOvAnDFpAFXTh5BIqbz8C4E2ylmA0lAQDrNy0wFeX+qt
/ldQ2O90CBRAHvghvSde2cDufbVEwqG83mIpfAqtAgnJlEvVVcOZMWlAhl/QFWCyv+BDt4xnxKDupNIKKb1M8Jx9syFFCaQleOCOCXSvKOoyVoC/+kciNg/P
m0xxURjXVXkVlBCefkOB0KTTLo88t45k2sWjcATwECiAPPD3vzUNcX77whrCYZl31dBao4VCIpAIXK0oKwrz0LxJFERDXYIb4O+ZB/Yp54O3jCWddk+ivip8
FSAQSKFJphVjhnTnAzeP7RLXANnV/6arhzJj8gDiSRernYEpr7alqzRFYZuFK/eyZE11sPrnQaAA2oHfE+HFhdvZsPUIhQU2SqkMddh8xzidfCehFIJU2uW6
yQOZc82wLuVI+8idk+jbs4yU47QSaO07ODNvGp+AVoIP3TqegX3KMiHSiwVfYZUVR/noXZOIhKRx8rU7ewUajS0lDS0JHn1hraf4gtX/ZAQKoB2YcB40tiR4
5KV1ZuIIQCgj77gI42rOaASBQKGxbZuP3DWJirLoRW2u4lN+xw3vyV03jSaVMmG/1jt77986+99SQCrtMrBPBR+eN/HCDjoPfAfmHVWjmTSmL/Gkg5BGzPNB
YngC4YjNq0t3s3LjgSuO8ttRBArgFPATRV5bvJ3Vmw9TEA6jXRMREFjkc5FJIUimHSaM6MU9VaM9K+CCDx3IEl0+/YFpVJYW4jpuh5+4EIJkKs1dVWMZN7Tn
RbMC/NW/R2URH7t7kjHhhUALP+zXFi4Ky5Icr2nh9y+tu4ISfs4cgQI4BfzVO550+MVTK0mlHYQ0Hv72GGdgYtBKw/23T6RXt+KLQhH29/7XTx3IzTNGEI87
CEt6ocvTQwhwXJceFYV89J7JF02A/NX/wbmTGNqvglRKmbi/1u3JP1pByLZ5+Z1tbN59zKR8B6t/XgQK4DTQnvAuXrWXBSt2UxAJoU6RNKURYBnP89ABlRkT
+kIKkMftIRSy+MS904hGbBzleruVjj9yQw5Kc/N1I7hqQv8LbgVIaZx2g/qW84FbxpByvG2X0Ag0wq9mkgOtIWxZ7D9cw+OvrLtgY71UESiA00Djr4aKR19Y
Q0NT3EsUai9BSCO0REhB0nG5b85YRgysvKDC4ye53HTVUGZNHUJzSxLb8rYsZ7AQCiFwlaIoGuJT900jZMsLzqDTwEPzJtO/VxnJtPKYlgK0zMQudKvvK4Ql
ePqtrVQfariiEn7OBoEC6AB8E3715sO8smQ7hZEwSp26epJE4DguvXuU8tCdk82bF2Ae+iZzQTTEJz84zQv3+aJyptAIaSjC100ZSNVVQy8Yy9F3YI4Z2oP7
5owlFkthe5Rf4V2S9lgYRgUotNaEbYvte0/w7ILNQNciMnVFBAqgg/Dpo4+9tJ6DxxsI26FTl57CEIXi8TTzZo1k8ujeqAsgPL7T7M4bRjN5VG9iifQ5nNM4
z1ytCduSj981mWjEvmDcACEEn7pvKpVlURy3PVqi9xCEyQFQCp54bT1HTzRnsgYDtI9AAXQQvgm/Y+8Jnn97K3YIlM7nC8jOUiEkrlKUlkT5yB1TsC15Xq2A
bImsKA/fPYlzr+9ixmtLQSyeZurYvtx2/Yjzzm/wV/9p3vmaYgmsdpWYx1twNZGwxdpth0zCD0G6b0cQKIAzgM+Nf+K1DVQfrCcStttZYfzkIYElJYmEy00z
hjBtXL/zagX45v8Hbx3PmGHdiSfPZfUHE+swfgMhJEh4aN5ESosj51UJ+BbGpz84lWgkjHJPXbpHY/IYEkmXR19aT0Nz8ooq9HkuCBTAGcDn9x882sgfXt2A
FNmqQdn5mTPpvH8qpSgoiPDxe6cSOk+JQn6oq1+vEh64fRxOWrVLlfXc5znuM9+jnjtsb6PtJdUIIUgmFeOH9+LuG89fCTQ/fHnjVUOZOXUwsXgKy+IUTldh
tighm2Vrq3lnxW7PURgIf0cQKIAzhC+8zy7YzJbdR4lEBEorNAotfF69T681vxFSkEymmDGpH7M8R1qnJwp5h3vg9okM7d+NeNKBdmP+fu0czzko/KpHGuGF
2DJjz62F4P01/7bx9KgsyoRIO+0SPAsmGrH56N2TiYRtrx6DNBmMeaC1wpLQ1JLgdy+tI5F0Luk+DRcagQI4Q/jCW9eQ4NfPrsZN4fURgPbWdQE4ShONhHhw
7oROTxTyV//hA7vxgZvHeo6/9h+tRptwmRA0tSTZc6gukwmo/Nh6HgGSQpBMuYwY1I35t47r9DU2U7Ho6iHMmDiAplgKy5Jk3P554AJh2+bVpTt5b/3+TG3H
AB1DoADOAj69941lO1m+bh8FUVM0ROYhpviwpCQed7lmQn/mzOjcRCGfq/CRuybTo7KItKNMDYD2Hq8WaC2xLfjVM6v4q397hSPHmwlbIhs2bNd4ELgK7rt5
HIP7lndaCTS/Sk9RQYiP3TUNhPQUq2fO56H9aa0J2ZJjtU384dX1l0RR1q6GQAGcBcw2QJBIOjzy0jqaYrlVhE+171ZYtuShOyZSXlLQKSa0v2eeMqYvt88c
QSLleo4/1e7D1cp4zDfsPMKzCzazo7qGJ9/YCJZvO4t2Z4ZJFHLo17uUB+dONOPvBJnzw6zzZo1m0uhexFNJpPB28tkE/9bXoc3q/9I729m8K6D8ng0CBXCW
8FfwZWv38fbynRREQrjtcoPMiiqlJJlymDyqD3fdOCqzcp8t/FCXbUkeunMiFV7Cj6lknMuQ05ltisZEIdIpxWPPr6e2IY6Ugufe2sKWXceJRiLoU8QPBRIp
IZ1yuHP2WMaPOPdEId/0rywt5MHbJ5h7oqRx7QuF1B77z/NdQHb1rz5Ux1OvbwzyfM8SgQI4S+RShH/38npqG2NeXzrPDjhJsgXCc7AZoZ1/+wR6dis6JxPa
L5Ix+5ph3HztCOIJU+LbP5/3D0/LGCef0mb1f3/jft54b2emIlBNQ4zfvbzOfO8UmXZGmUhcBd3KInx43iTPCjmrS8geVcO9N49mzIiexBKeFaNBaJnxTyBM
gVbfh2FZgufe2szuA3UB5fcscdkpAEvKC7YP9Peca7cc5rUlO4hGbHwLNF8MWmuBEKaXwMiB3bj/1vFnLTj+nrm4MMzD8yYSDVl5zF+Nl7roCQ1YQhCLp3js
Rd9jLjLpsq8s2cHqLYeJRkIo5ea17HVmoyNJpxxuunooV08YcNYUYb9eYb+epdx/6wRclb/MV/bCNSgIh2y2V9fw1FubLzjdV0rR5Yq+ni0uGwXgPxCv9RFC
mId0vpWBf/jfvbieozUtmYQZ/7zZ87cOp7mu5u6bxjC4X4UhB53hOP09823XjeDq8f2JJZ08k9LfBpg1VCtNNCJZuHIPS9dmS2T5422JpXj0hTUo5Z60hciF
FyoUmrSC8uICHp43iWj43CjCH7ptHEMGdCOVMit7Xqjs6i+04I+vb+ToiebzXuNf0FroldIXvUpSZ+GyUABCmJXk7htH8akPTKOspACtzUPSWmNZ0lMGnX9u
v5fA9mqTgFIYDWXOC/ktASk0iXSagb3LeOD28WeapJcR3MqyAj5y12TzZl5aMl67LLNu21JS25jmkefX4TiqVYks3yG5YPluFq/eR0lBKK8vQAiZ8RNaXlPV
mVMHMvvqoWcc2fC5+iMGd+NDN48n5bVZV3lj/l7CjxJEIhYbdx3jhYVbzyvlVwiBZfk5BmY+2ZZk1rQhfPK+qZQVR73vnZ/zXwhcJgpA4LiKeMrlrz55A8/8
10N8/2/mUTVtCL27F+O6yhPKrCY/H8/s8ZfWs2t/jbcVOPWsFEKSTmvumDWK8cN7npEJ7bvCPjBnLKOGdfc8/1be75qWBsY7Ho5YvL5kG+u2HmpTIsv3aaTS
Lr9+djUtyXRespLO8AT8rZYpvfXQvImUFZ1Zl2TfYvj4XVPo1b2YtFexSOQt9icy/Vm0Evz+5XU0NCU6ffWXQmTyDrTWuK7CtiVTRvflC/dfwxP/8SD/9/U7
mTyqL43NyUzthUsV9sUeQGdAKeNce3PZLt5evou5s0bRu0cJ99w4mm3Vx1m2fh9vL9vD6i2HiCXSmd9Z0hBfznUC+Sb8oeONPP7Kev7+MzeSSGmvVZXIdV57
kEgBaeXSo7KEh+ZN4R//9w1c9/TjkN6evV/vMj50+wSUQ5a5l89x53F6QrbF0RNNPObVN5R52HK+NbNiwwEWvLebu2ePobE5jpSW+X7mHKYLr/ZyBJJJE9mY
N3sUv3txHVKeflX2E36mj+vPzdcPJ5FMIyzhMQ/zQ3sdft5fv5/X392Z8YOcK/x24v49QEPIlvTvVcrdN41l/PCezJgywGSAKk19c5yfP70SV6lLPuPwslAA
YDziSmmeX7iNWVOHkHQcYkkY2LeCsUN68YE54zha28Lzb21h3dbDLN94EMfJxu3OVRmYFdSE0+6ZPY7RQ7oZRp5F3kntO+fTaYfbrhvOy4u2sGTNvoxgnA4f
vn0Cg/uW05JIYWUkLo/wCIGrXQpCIV5YuJ0d1TWnjpcL40d55Pm1VF01lJBt4SpT7FR6OU4nX47QAmnBh24ez4L3dplU3FN45TPhS1vykbsMJyLWnEaEPF+F
0G3umQlfSlJpl0deWkdLPNXhe5V3DMIUP/WfuT/UkYO7M2FEL+6dM4aRg7vRrbwElKIxliQWj1NUEGbZmv1s23PcbFcucd7BZaMAtDZWwJI11azfdZQpo/uS
iKdJpVxq4i1YIcnAXmX85cdnEk+5vL9xH6s3Heb5t7dw6HiTMT8xKyze6ngmysA34esa4zzy/Gr++c9uMau/zpataPV9L5zmuGZVe/iuyazcdMg0r/DZbych
U+V3WA/uvmkMqbRravxqDOsvrwGgCVuSw8eaOlQiy3durd12mJcWbeXhOyfR0JxASsvcj3y0XAnxtGK010vgh79//5RbLF9Zz5wyhFnTBpNIpMEWmdSFfCkM
WpkiJ4tW7OLt5bvPqsa/EFmnrFIa3+DqXl7IrOmDuX7aIKaP7c+gPuXEkmmU41LfGAdMSnTYliSTLi8v2W7uvbz0+wxcRgrACEhzS5JXl2xnypjeKKGxhUSH
JFoZHnss4SCE5vopg5kxcRAfvnMCazYfYcF7u1i55SDVB+sz5npWGegOmZrGkQYvvbOND902nilj+hKLt5eSKzzvsiKRTnPtxEHcfO0wXnxnmzex8l8jwEfv
mkqPbkXE4mksIT1locnn0tFKEYmGefyVdRw82tjhVVMAv3l+DbdcN5ziwhDKBS39rMHW1yM9B4KD4t6bxvHq0p3s3l+b1wrwE3UKC0I8dOckCqNhWhIO0vJN
i/yWjCUFTfEkv3h2Na7rm96nvQxjaeV4732lXllWyNUT+nHVhP7MuWYolWWFFERDxBNpTtTHkNKEOm3LDFq5moJIiHVbj/Dummpzby9h09/HZaMAICsgry/Z
ycfumkyfHmUkUw5CZstC25bZzDY2G6ppcUGE2dcM4ZYZw9l9oIZ1247y1vKdrNl8mON1LVllkOMYau+5m721IJly+O1zq5k6pi8Y45m2k1p7PXlstHKIRi3u
nzuBxauraWxJtMln9wW3avpg5lw7jGTC9Wr8a7TI3TtnBUgpTSQcYuuuEzz1xqYOZ8n5VsDu/bU8+9ZmvnD/1dQ0xQjpdqaLMKVGnbRiQO9SHrx9PP/883fy
+sZ85+Oca4dx9cR+xFNppASpTNKPEiBO2s64SlNcEObVt7azalNbB2abc3jnQXhC7323pCjCqCHduf36kUwa3Ytxw3tiCYuU4+I4Lg1NCSzLE3p88pTwmqcY
K+TFd7bSHDu37UdXwmWmAIwH+khNE2++t4tPfWA6iZTOUtxz4vC2F2t2XXAcF41L/17lDO3fjduuG8bBY428s7KapWurWbP1MC2xVOY8Pkst3x7XH8OC5btZ
uqaamVMH0RxLYmW89NmUYW9aIaVFIukweXRf5s4aye9fXt/Wkeb9++brRlBeGqWxOYElLbP6K8/RKHSGKec7BjWaR19cS0197Mwmrfe1R19Yy9wbRtG9otCE
DmW+mKXH1ROCtKO4beZIXli0nQ3bj7Q6p2+2V5QW8OG5EwlbFgnXtPc2MpbdBmhh0oDRCssW1DS28MgLazKrfz5F5jvzMiu9NjTp8SN6cs3EgdwwbSBjBveg
qCiK0opEwgUvK1IIX/Ahq3yE/1AJhyS7D9Ya52PO/bnUcVkpAMiamM+8uZl7bhpDYTSMUu3HanP3hWnHJent7Qb2q+BTg7ox//bxbN97gqVrqlm8qprt1SdI
JJ3M7/3JmI37g5QmnPbLp1Zx9YT+OdaD8ZqTiXOfZEoLwfxbJ7Dw/d0cOdHc2grwrOM1mw9xz+zRpj+BUFnev/DMc236+7lKE42GWbF+Py8v3nbGHnO/ctGh
4008/vI6/uITM0mnTF+Ek8dtDmtusutqelQU8vCdk/naf7+Om6NwhOd0u7NqFBPH9CaZQ11u81y0RKNwNZSEQ/zx1U1s3HksrxLzE6J868ySkqEDKrl2Yn9m
XTWY0UN60LOyGNdxSTvQkkghNWb71IGIpdIa25a8umQ7x2pO7eC81HDZKQCfnrujuoZFK3bzwVsn0NCUMPX4ThP9F0J41oLGSbmkUy62bTNldF8mj+7Hx+6Z
wtoth1i4ci8rNh5k177aVqubr3x8Us2y9ftY8N4u5s4aQVOzl9ueywg86dwpx2H04B7cO2csP/7D+60+9+fby4u3cfvM4cyaNpSWRBpbCrQ0HnotQAvXKBop
iSfSPPLCWlo8P8SZmqx+nP7pNzZxV9UohgyoNI05TnI1ZFKNtEBLRcpRzLl6MK9MGciilXuzSlJp+vQo4aE7JqMVKCGROYlKeZ4IUVty5HgTj7+8vt1x+tfV
r2cp104ewKxpg5gypi89youR0mzJmmNJwPQ6sKTA7+p2+ntgqg0dPtbEa0t3dOAXlxYuOwUAZMzAFxdu49aZo7D9MlwdZf8IP9It0dohljJ77GjYomr6MK6f
NoRjtS2s3niAxWv2sXz9fo4cb8oIqRSmxbbrKn7xzCpmTBlMJGQZfr3I31LMOy0uppfAq4t3sPdQXUZw/ShDIunw2+fXMXVMX2zb8lYiY5YLb3uhFBRGLV5Z
uoO3V+w5K485ZCMbJ+pj/Ob51XzzSze3M27Px2LypFGupqgwzIfvnMzyDQeMH0YYp938W8czpH8ZsaRrHG3t+VOEi1YCO2Tx/MIt7Npf00aJ+S7DmVMHcet1
I5g+ri8D+lQQCklSqTTxlGMsMmGsgswP/ISiPOHGtvfAbBffXVfNjuqayy7p6LJgAp4Mf7Iv33iQDduOEAlbZ+SxNUa6wHSgEVhCYEmNq6AlkSaddOhRVsid
N47ln758Cz/7xr18+0/nMPvqoXQrL0RpjeOYTsLrtx3h9SXbKIiGvVC99kqHtR2PQOI4iv69y3koT1NO37pZtm4fry7dQTQSylyXktpTWGBZgrrGBI++sA7X
bU35PVP4xU9eWbyD1ZsOURCx81gSWaGQyqQLJ1Mu100cwK0zhnlbJBjav5J7bhpDWplaBTJPRCF7sYKwbbPvSF1m9c99hFKaXIWp4/rxn38zlwfvmEj/vmU4
jktLLIWrhCf4ohWj0bRG81aDdoU/+76vdF9YuN180tFF5BLB5akAMA8unXZ5dsGWjAUAoLVf+05BO3XmQHhP2me9meo6UliZCeW6mlg8QdpxGDawkgfmTuI/
/+YOfvmd+/ibT1dRNX0IJYURAH7y5Pscr23CtiyzPdD5twF4zMG043LHDSOZOLJ3m6QTIcB1FY+9tI4jJ5oI25bhGvjXB4Rti1eWbGfNltN7zE97L7XZnrTE
0/z2hbUk0jldkTH30DAevfskwG+ZblsWD985mZIiU0X44XkT6d+znFRKteETmOeiMv4YrU19kide3cChY02t/CG+sRGyLT5612RKi6I0NCVw0iaT0MpQvX0n
nvdvLTyasW8x5b1iz7ei0a4iGrFZvvEAa7ccMjrjMvD85+KyVACQJQYtWrmHTTuPURANo5TyNLgpidX+FDjVJ+b3CFPgw6T3Km+PKRg+qILPfnA6//U3d/Cz
b9/H1z53IzOnDaL6UL3nAzi1J0Ji8hq6VRTykTvb5tr7dN0tu47z4sJtWCHhJc9kc+R9x51SndMV1/dpvLNyD++u2UM0GjYrvpAILbywXWsICfF0momj+jBv
1igmjezFnVVjSKYdL0EpN1NRezUMJVorlHYJhy027T7OM29taXMNPv//+qkDmTXdEIlClvToyu0/vY7Aj8yACUIk0y4vL9pGIuV4ZdYuL1yWPgDIEoNq62O8
sngbY4b0ILt++DhX6TC/N8lFpolGKgXxRALbEkwe1ZupY/rS1JKgOeaQPl0JMGGq84YwSmXOjBHcsHgbi1bsbbX/9Sfh4y+vY/Y1QxjUt5xU2jAZbSF56o2N
7Kiu7bQSWYbfYCIbj76wnqsmDCDi+R/8hKB898YSpmDKZz44nVTapbAwhOO4GSVsVnVjhekcHoPAdPj5/SvrqKmLtQ0laigqCPOJe6dSGLGIJVyTQqzPPclL
Y/w9rseh2LjziGEekj/se6njsrUAILtnfOmdHRw83kg4ZGez2TrtHNmYM2iEBNs263EskaapxXAAKkvDaKU851P7xwKBEso40qI2H71rEgWRUGbb6n9PSsHB
Y42GM+AJRci22bbnOM+8afrideZ09f0P763fz+vv7iActsze3t9T54O3XeleUUS/3qW4rttqNc/2LfRDowqlBOFwiFWbDvDqkp2ZugeZQ3r/fdv1I5g+pi+J
pMcLwD2FMuo4cq0StOb5t7fQFEtypmHUSwWXuQIwk/bA0QbefG8X0ZDvDDzFpPXQkZXEhP5yGXja+78E7zNLmkQaV3nHFDJvW2vwH4aRdGlDSzLJdZOGMOfa
oTmrrX9tRhheWLSNDTuOmBbgjssTb27i8ImmTGy8M+EL3+9eXM+x2hbjW1HZkbeGzlG2GuX62RAy51htfyWlIB5P89hL62k+SfB8f0ZlWQEPzZuI8IhQxqFo
ZbiV5wKJKZsWDtnsPljD2+/vPqfjdXVc1goAsqvm60t3UNcYz8bi9an2xzo7O7X2JtZJqwP6JAHLOgxNC/usI0pmYv9+/Dm/E9Dfogjtm7MWCPjoPZMpLgxn
HHJmWEYh1DfG+d2L64iEbTZsP8LLi7Z1mPJ7pvCtgC27jvHC21sJhyw8mybPt4Wf7UDG3M9Mt9ywrMgQmpQriIQE766t5p2VbcOX/h277+axjBvWk2Qq7e3L
jZL1oyzmXnrOXo9n0NHbYXSWQEp4Z+XejAPycjT/4QpQAL4jbM2Ww7y3cT/RiI2rQJ+ykKXhpJtogQYtcJWD0m7Wj9Bu151cnONqJASJZJqJw/tw142jMyG5
zCg9R+erS3fy0qKtPL9wC43NCTPhz9OE9Y3sJ17byN5DdURC9jmeSyOVEVNpCxqbkvzupfWk0m6r8KXPvhvQp4wHb5+Aq8hod78jkx/TFyi0FrhK4SqNEu2X
SG87GoFlS07Ux3ll8eUZ+svFZa8AwKyartI8/cZm4omkqfjSTgktMKu39Dz9CtOqqqggSjQURiuN45rqtJwkjOdF6IRxPj14x0S6lxdmVn5zTiMgyZTDv/9q
MQs8Z9X57IvnFz/Zd7ieP76+wcuLOJdpZITfVYqIbfHmit2s3HSwbcjNu9cfuXMSA/qWk0y7WMLbLmnLhO2E2WqkHU1YCgqjIYoLTREPRylO6YD1oJUmZEne
XbOXzbuPn3MYtavjilAAfpru8nX7WL35MOGQhbfE5/++8IVI0NiU4l9/vpAXF27lWG0TkbBFRWmB8Uy7hnPv78/PRwFSKSySaYfRg7pz381j22U07j/SSG1D
3GxOzvN81fgU4c1s2XWUSFiek4msUYQtwbHaJn73wjocV3lbBoNMHYThvbirajSplBF+jUQrjascXG2UclE0RGV5AU3xJJt3Heeff7GYxSv3mjJtpxFkn0RV
35zgmTc3d1oYtSvjsg0D5sKEsQTxpMMLi7Zx1fgBaM9j3F7gyOxJFZXlBew6WM+vnltLj8oiZl89hCmjejNz6mB6dCsGJK6rTIKQMPHszp0zxlJJKcX9t47j
1cU72H+0oU1Cyvna9+eDH4WobYjz+Csb+M6f5qcId/x4YIVsnl+4jU35OvxoQ+75xD2T6VZRSHPM8QhRLhHbIhQJI11BykmxZN1B1m05xNsr9rBl93GkkMz9
l5EZy+hUgUKNJmRbvL9+P6u3HgYu/Yo/p8MVoQAgG0patGIv2/ceZ8zQXiTS6byrtv/ItTBss/tvHce7a/ZxvLaFJ17dyBOvbmRwvwrGDe/JXbPGMHxQJYP6
lqERxBIpcMH1QoIWMpva6lkVp5uIuRBaZGoMDOxXwfzbJvD93y5pY+RfaB+Vb4m8ung791SNZvrEgcTiSa8EWrtNyQA8p5wCjOUQClnsOVDHk69taPMLf/W/
dsIA5lw7nOZ4GikgHAoRjUiO18XYt/c4by/fw5I1e9m1r7ZV3cc51w5h7LAeJsuzzbPOIXahkQLiSYdXFm8j7WWFBgrgMoHvQa9tiPHasl2MGd7jFKs/gEIK
08pr2oSBjB/Rk3XbjmJbZsXfe7COvQfreGnRNgb0LqVq+hCmj+vPdVMGUFQQocC2SabTXgqt6QrkK4AzsRAMa1hhCUilFHfdNIpnF2xm94HaizpBfSugOZbi
V8+tZsLoPl6WnUlNNtuu1orA3zoY8k8O8UcInluwmX2HG1p53H3KrxDwsbsnU1FWQDzu4CiX9TsOs3zdPt5de4A1Ww6SdrI+HcuSGdm+b85YwiGLZMrNVPtt
73rCIYsNmw+zbN1+P1B02eOKUQCQNZPfWLqDB24fT6/KEtKOOuU+z3VdyksizKsazdqtR3Bc03gkt3bg/iONPPriOh5/ZQOD+1VwzYT+3HbdMIb0q6RP71LS
KUU67ZrceJGlI3d8zCaclnYUvbsV8eF5E/mnnyy86BPUpwgvWV3NohV7mDtzBC0tKYRFXsvK1EjMFkTRWhEJSbbuOc6zeTr8+LUD76oaxU3XDGXd1kOs336U
15buZNPOo9Q3JTLfbV2xydTwnzyqN1dP6Es84SJFPqvEi+Zo829XaV5Zss1Ui7oCVn+4whSAH8fee7CO19/dySfum0oqnYeeK7Jlv4SwcBxN1fQhPPbCWvYe
qs/uv3MIKtJjve3aV8OufTU8/vI6xg3rxbWTBnDTNUMYNaQXhVEbISSJRBqllVkhxalVgSlmor3kNUUqLZg3axQvLdrG2q2HL64VQC5FeC1XT+hPkdcYpX2t
mkNmQqO14I+vGWLRydeilCnEUVgY5us/eIu3lu+itiGe+dzyMgJ9gT8Z82aNprKsgLrmFKH2+iZ4nI+wbbGtupYFyw3x52Ir1wuFKyIKkAs/tvziwq0cz2nl
lYVX796rCCAEpNMuA3qXccv1I7xvtIbWOlP5RgqRSeDZuPMoP39qJZ/75nN86utP8YunVrJ6yyGUNj39Qrb0eO/thxDNwuVTaiwc16FbWQEfvmOSaUl+kSeq
7ylfuekAy9ftJ5JpitJ2YFkWpkQpRSQcZtXmw7z4zo6MuZ/v+H98bSNPvr6R2oY42ZZvplag3/DFh8+AHNCnnFtnjiCeUJ7pn2c8mMxMqUEJwWtLt7etxHSZ
44qyACDbRGTrnuMsWVXNfTePJe2kvf2qzuzSc9cpvMl2xw0jePr1TdQ0xNr1uvuWgcCnCkNzLMW6rYdZt/UwJUURpozpw4yJA7l+ygD69y6nuCBCynVJp53M
OMCY/j61xS8uLoVFPOlw09VDuHpif5at7XgvgfMHgW1JohFDtW53JP6laY3wWqU//uIamlraN7n993JLr3VENu+dPZo+3UtoiiexMqndeaDAsm2qD9Xzxrs7
vKs5HVH88sEVpwCATD7/68t2cMesUV7BCJ31OGWoox57XUA6nWb4wG7MmTGCJ15dd9pVwjdN/SQe4ZkeTS1J3lm5l3dW7qV7eSGTx/bhxumDmTKmH/17lXql
rr2SJB7RxU80Ap8PrygpivDRO6ewZrPXS+AiOa18wZ01bTBXTxxAIumYsmrkETmPqedqRWEkxFvLd7JwZXWHVtwOlTL3woe9uhVx+w2jcFwH2R5xwoOLS9iW
vLd2P3uuwDbjV9wWALIU2pUbD7JmyyEKItJz0LXvoddegYu5M4dRVBhuQ8s99fm85pLeb3wT9kR9jDff3cXX/uctvvSdF3hv/X6vepFLVnzaMhallMRSLtdN
HsiNV515U87Ogk85LoyGePjOiRRnCrCKvELntzuxLElLLMXvX95AIpXuNOXln7Jq+hBGDKgglnKQ0qa91V8gsC2b2oYEL72zNROluJJwhSoAYwU0x1K8uHAL
Tlplij20R/GXEhJJhyljenHVuH6tEnPO9Nz+vtXfz1pSsPdQHT/6w/s0NRuqslBej9z2YupaEw5LHrprEiVn2JSzsyC80uV3Vo3mmokDaU64CMu7tnbuo1Ka
aMji7fd3s2ztvk6j2vq+lEjYYt6s0ShtQpJKuO1So5VWhEMW763bz/rtVwbx52RckQoAsivOW8v3sGVvHZGwjdbKYwjmg/DSREPcMWuU8UCf42Txvdd+Ce61
Ww7zypLtRCNhXO2nz+Y/hyEHuUwa1Zu5Nwz3HJcXDr7ZXlFawINzJ3o5AW7OiPM5AY0VVdsY59EX1+F2ItXWr/t33ZSBTBrTm2Qqnan+SzvjEQJa4kleXLQN
x+14d+bLCVewAjCx/PqmOC8v2momYjvlrQCTdCLBdeD6yYOZOLK38Wd3wqTJPeXvX1rP8domwmG7fbNYeCnKWmNZFvffNp4elUXGq32BrADfbL/npjGMGd6D
eMLxBM7KjEEASih/yCitiIYlry/dwfqTmoac01gwzzNkS+6dPY6iSNgkbAlTA1B46cimIKvxTiiliIRs1mw+xPvr92eOcaXhilUAkF0T3nh3B3sP1hAJW7jt
+X+1oe+mlEP3igLuvHF0pzre/Fp/W/ce54WF24xF0p5waDOhhRSkUmnGDO3FB28Zf8GcgD5Xv2/PEu6fOwHleKSoHP+5CfhpjxascYVLyJYcOdFsWpR34mCF
FyGYOLI3M6cNJJZIY1mW8et6+tBED4yC17jm3qUVryzZQSyRvmwr/pwOV7YC8CsGHWvkreV7TdXeU5SK1tq0kEql08y5ZijDBlRmKLGdicdeWsfR442EQjLv
/lWYeFgmUqGU4oM3j2Fwv/IsS/EC4IFbJzCsbwWJdKrNOf3ti1/9SCtJJBTihUVbT9+i/AzhC+4Hbx5PaWEER7WT6q29gizaJP1UH65j0Yq93kivTFzRCgCy
Xt+X39lGQ7Mp5plvMhgPsakwk3ahV7cS5t4wKvthJ8DPtT9wpIEnXttIcUEI12n7Pe2H2bQpnZ1yFf17lfPg7RPPuxfbdOXVjBjYjbtvGkvKdfNuO8xb0uTo
A2FbcOBoLU++ttH7QueNR2vN2KE9mHX1IBJ5k3680wmFFhKtJSELXl60jZqGmFdT8cpUAVe8AvDpwdv3nuDtFbsNldXNE3oTkJs+rLTmlhnD6NW9uE29vnOB
H4r6w6sb2LGvloKC/I04BDJTt0AKSLkuc2eNZNyIXhmn4vmAH7148I4J9O1ZQqodgctSqQ39PxSyeGrBVqoP1Xcucck7zJwZw+lVWUTKya+QzFi0l39gsfdw
A6++e/m1+jpTXPEKAMwkdVzF8wu20tSczDYSyYlnmQntla7y0nOHDajk5muGZY7RGfC3JcdqW/jdy+sJ237JrazAtC4qKpFamqaclUU8NHeiN/7OX9H81Xby
6F7MnTmSRNppJ8kGMkm/riYattm9v44/vrKhXcrv2cCPRPSoLOLma4eTSrWfa6kRoKWJREjB28v3UH2w/ooj/pyMQAGQjf2+v2E/q7YcIhKxDCOvTQfJ7PTy
V5m7Z4+mrDjSqdVj/FX2mTc3sWX3MQoKLJRWxqmFyniyMw3GPd5NynG56ZqhXD1xAFrTqb4AX3AtS/LwnZOpKCvCcfzYYx4/BTqzVZECHn95LcdqWzJNPTpt
TMCtM0YwYlAlSSft0X7zH9+QkKCmMc6LC7eaY1x5kb9WCBSABylNb/tn3trspbkqNH5eeb4Ysvn+8IHduWbigMx7nQGfZdjYnORXz67CEhZa5+QI5Fl1TQUj
TWlJhIfumGQYhXQeN8AX3JlTB3HT1cNIplJI0b7S04CroCBis2HnMZ5/u3OrFfsrd2lRhLuqRnpRCLw8jHyD0ijlEg2HeGdVNVv2XP71/jqCQAF48Cfm8vUH
2LGvhoKw6eNnYsf5Z7mrNEUFIe6sGmVKZHfiZPK3Aq8u3s7KTQcpjIZQXu+89rgKUpiiIddOGsDsqz2KcCf4AozgGlP+I3dOoLAgjHL9/Ib2Em28LDvl8tiL
62hoTnRqll2G9nvVEMYP70kiaYqmKKnyO3G1RlqCppYEr7yzNdM09UpHoAA8ZFtht/Diom3YVgi8RhPtzRMpJIl0mqsnDGDauH7mvU5yvvk5LPGkw6+eXYWj
XcQpLBLzrkRpKIzYPDh3EqXFkU6hCPsx8jnXDOPaiYOIJVOeYhHtcn6V0kQjNsvWH+L1pTs6V/gBrTQFkRD3zhmDFbLwqzy3225ca6Ihm427jvH+hgOec/LK
Xv0hUACt4M/PFxduZf/ResLhkPEFnGLFVUpSWhLlzqqRhh7ciQ4lv+LO4pXVLF1ZTWGBjaPaN+wFpo9BIu0wZVxf5t0wKpvgeJbwV//iwggfuXsKliURSoAk
E1P3RovvqtTa5E7EU2kef2kd8WTnJfyYMZlQ7eTRfZk4sq/pISC9xiOZ3Ikcx6kw2yblap5bsJlEymlVdfhKRqAAcuCvloeON/Hq0m1EvFZi7WYIYngBrqO4
btIghg3s3qnONz8kmEw7/Oa5NTTH0tjyVI9MeMW2TIWi++dOpHtFYSbUeTbwV/95N45i4qheJFJG2EztP1M4RWe+6/Xo0S6RkMXC93ezeNWeTl9tfQr2vBtH
U1IUwXVzXKKZy8xuTbTSREOS7ftqeGdltXkvkH4gUABt4MvJS4u2U9sQx7YEql0VYEzgtKPo3q2IO24YCXQuq8ynCL+3fh9vv7+LaNhC5WW6GX+FwHDxnZTL
qMGVfOjW8f5Izxi+2d69vIiP3DHxFBdmogFCmXCbJSW1TQl+99J6r+Zi5622fihyzJCezJo6kFTaaYeIlO3ToLVCSMEr7+ygpv7KJv6cjEABnARf4LbsPs67
a6spKgjj5iEGZaClV7NPMOfaoQzoXdb5qbme+fzb59ZQ22D6G7adv8Yhp1EmAUcYbsADt09gcN+zowj7Zvv828Yyakgv4kkHKfOF/LLhSKUEoZDFm+/uYPWW
Q53uafev+45ZI+lZWYyTt6ir9rj/Cq0VoVCIg8eaeXXptk4bx+WCQAHkgRBGEbywaCuxlNNuOWmNMquuhFTKZXC/Cm6+dlinj8dXSht2HOXFd7YQznQ5bjsi
AOltAVKOonePEj5+z9QzXoGzCT+lPDB3Esm0g5SQrz6BX/Fca7BtzZETzfzu5Q2d3lnHX7kH9innluuH4bjOaU0bMyaLhct3tSk7HiBQAHnhr1hLV1WzZedR
omGPjptJFPLTcLzb5xWfEAjumDWabif18OssaA2Pv7Se/UfqCYUsdJ7+hsJj3/j75HTK5fbrRzJmWM8zowh7X/vYXZPo37uUVCqNFDKvItFCZ5x/tiV4YeFW
tu05ft5qFd56/TD69yojndZYeZmIRiNpQFiS5pY4Ly0KiD/5ECiAPPCFJ5l2eer1jYRC0jDxhN8mPMs2y7jdJIYYNKiSmdMGm886cbL5+QZ7Dtbz3IKtJmlJ
Q3Z3baIDOscTJjBkpW6VhTx850RvBT39uXzBHTagkntvHkdLzDmt4tAowiHBnoMN/PGNjdkhdRL8lbuyvJA7q0Z57QXab02OMK3diiI2y9buZ9MuQ/wJQn+t
ESiAduCHzxau2Mu2vccpiIZxlUKgkTp/ZVrTXUYy74YRFERDp4wgnC2EgKff3MTOfTVEwjau9oUg/5mkFMTiaW6/fjiTx/TpWPqyd20fv3cq3coLSTuuObE4
xfVoiUbw7Jub2H+4be/Cc4WvTOdcM4QRA7qRTDunULACrQxtORZP8/LiHaQdFyk6VSddFggUQDvwnWbHalt4892dhLyQlxLaxMDzTD5jcmsmj+nLjEn9M7UH
O3NMQggOH2/iidc2ZDMUvXZcJ0OgkcKUHSsujPKJu6dmEp3aJTd56b4TRvRi3syRxONJLCm91J78UNrU4tuy6yjPvLk5W8i4s+AzEaM2d1WNQdg2nELpgW+R
2GzadZR3Vpq26W6w+rdBoABOAV9Qnn5rCyeaYoQsUxTEFA1pnaHnQ2lFcWGIebNGErKtTq/V51smz7+9lfU7jxINh3G1yiueGoESEik0iYTLDVcNYubUgael
CFuW5GP3TKG0JErK0UiZvYb8pF9BKu3w+1c2UOM17+jMMJvlbV2unzKQSaN7kUqYPg7tn8HYREppnluwxVT8uQLr/XUEgQI4BZQnbfsON/D60l0URG1wPcFv
zTrJQgjSKcWMSYOZMKJXp/HxffhWQENTgt+9sA5Xmb537VUyEt6YlHaJhCN87K7JXunxtqP39/7TxvbllhnDaYklsaXJjFRCIzVt9txaaSJhmzWbD/PauzvP
S38C5df7u3EckVAow4NotwexhmjIYmv1cd5esSfzXoC2CBTAaeBTYV94ewt1jUmkLTOLfz4HlBQmC66iLMq8KlMxqLMnn28FvL5sJ8vW7aMgare/4moAU348
mUwzfeIAbp05oo1iMum+RtA+ds9UCqK20XXC49RpUwtBZ9J/FX4LwEQqzWMvraMllur01d/vCDRueC+unTyQRNpFWOKUWxL/uby+ZDvHvZ6DAfEnPwIFcBr4
NNo1Ww4bYfNqBWhk+6a9AMdxuenqoQztX9Hpdfp8KyCeSPPb59fRFE+ewsPvRSuE6cZrS4uH5k6grDiSqTsAZAprzr56CLOvGkxL3MHKQzs2igC0J+iRqM3i
lXtZsrpjHX7OFvNvG09pcRTXdb0qv9lra3W12mxhDhxr5PWlO3NvQYA8CBRAByCEMUOffXMLibjjrZy5Pe5bfRspBGlH07tnCXfdOMp/u1PhJwq9t3YfC5ft
oSASatfr7gumaW6SYsLIvsydNSpTd8Bf/QujIT5y91Sv6egppMZoAEIWNDTEeOzF9SRTTqeb/9lwZDdmTh1EKpUtPmrO03b6aiBkWSx4bw97D9UHxJ/TIFAA
HYD2GoouW7+PVVsOEQ5Lr0BHPiivGo7GcVzmzBhB7+7F55SQk3dMGMF1XMXvX1lHbWM8W8rs5O962wDfchBoHpqXTRSS3u9uvX4408b2JZZ0aM9toYXJONRK
EQpbvPneHlZuOpBhT54P3HbdcPr1LCXpuJjmqe0xMw0R6Xhtc0D86SACBdABaIyJHE+meemd7WjlZvLP237ZeKctIXHTmuEDK5k5dTAAlmX24mf7OlmB+OSg
1VsP89qSHRREbENYOklAMgXEhfTKmiuGDajkQ7eMy3ynrCTKQ3dMMiW1TsVi9KIgliU5XhPj8ZfX5y2KKgTndK3+9qOsOMrdc8aQSPrFR/NFYDwestaELMk7
q/ayZfex86qULhcECqCD8E3it9/fxdbdJ4hGrBzT0jjFhFA50QHh9faDe24aiyUFjqNMK7CzfOVrSOo7KX/38loOH28kYpvmornuPZ8XmFEM2iiP++aMY3Df
ClxXcffsMUwc1ZtYMm2IQu3Iv/BIUCFb8vzbW9i862jeGv9ac07X6ipzr+beMJJBfcpIZ1Z/3/bxtgIoMjkQAuqa4ry0eJvXdixY/k+HK7I9+NnAz/OvbYjz
6pKdjB3eE7SpGyi8lUkpFyGyBBXpdZ8ZN7wHn7pvGu9t2E8kZJsVs6Pn9f6wLMHRmmb2HW5o9bmfKLR9bw0vLNrC5z54NUnX8VyU7fgppCadgv69y/nUB6ay
bN0BHpo3Ecdx8ZL82+UvaCAUkuw73MATr21oQ8fx/QCVZQUMG1BpBNFLmz4zToRx9N09ezRSWijSWFh5vgVoias1BRGbNaurWbv5cKZqUIBTI1AAZ4E33t3J
h+dOoFe3YtJudpK1tz+1pOArD8/g885V+PX8O54hLzLhud0H6viz771kauvncW79/uUNzJ05ml6VxaSU2655JwAsTcpxuPemMdw7ZwwCieP40QptUvzycAu0
BltKnn1rc97sOuNh0Hxh/lV87N5pNLQkMkVMzqSlutBGfVlSEk+ksURb4c/cH+EipSSZSPHy4m0kUs55S0S63BBsAc4A/l533+F6Xnt3J5Zte1tPf0+af3Yr
NGkFIcvGtiUhS2BLidXBl21LXKUZP6I3988dn3dcUggOHG3kidc2Eo1KlHLbHQ/C8rIXTcsu14W062QcfIAn/K0FSClNJGKzrfo4z7y1OXdTAWRpxOOG9eTe
m8eRSrlEbAtbCmxLELI6fs3SsrAtaaoPeZWX8kF7lkXYttmw6zjvrNpr3g9kv0MIFMAZwue5v7x4Oydqm80k9RPi25mkQhs6rvKKVChFRnF06OXVAWyJp7in
ajRjhvRok9qrvbE989Ymtu6toTASbqdyEJi1FUBmuvdKIU2yjDAU4vwBTmO5PPPmZo7WNCNk69XfJyh97J6plJdETRIR5nhaC8Of6MD14v+N9qoMkTfXwb+3
IFCO4sWF22hqSQUVf84AgQI4Q/hFLjbvOsaSNdXZWgEdKHtlfAWez0CIjFf+VC8pBHgRAOUquncr4SN3Tc7U6vOR6ShU08zvX1p/io49kFvKW2TG5eU46KzT
0E97FmQTfjbsPMKzC7a0ifn7bLurJwzg5hnDPWdi6y2R6OA1I2TmXmXSm9sJu2o0kZCxShat2OW9F6CjCBTAWcAvc/Xioq3UNcexpJ3JTz/Fr87qXNrraCu9
smOJRIrbrh/B1eP7tknt9ZXAcwu2sGnnYaKRfH0FOz4ugfED+GFEpTWPv7SBhqbWNf4NkQjCIYuP3zOJksIQjtO51YDagxmD4t3V+zha07mdh64EBArgLOB7
l1dsPMi6bUeIRkxyDTndezr5jJ55LVEKigtDfOyeqYTs1qm9vgneFEvy6+fWIoU4RyE07cmVVhSEbVZvOcwb7+5sY334Qlc1fQhV04fRHEtgWed/ammtsaXN
8doYzy/cYsZy3s96eSFQAGcBjR/ic3luwWaSjptJme30EiDC36+bPbGUknhKccOUwVRNb9v9x/e0v/7uTlZsPEhhNHwOefCuV1xHknZdHnlhDS3xVIZ7AFke
QmFBiI/fMxXLsjwfwvlfhbWGcBjeeG83uw/UdXoB0isBgQI4S/gr4JJVe9m4/QiRUAitVKffUH8PbHbmRiCV0oRDFg/dOZHCgnCrpB7/38mUwy+eWYnjqnZc
eh2DUopoJMR7a/azaMWeNmW1fGtg7g0jmTK2D/FEKm8SUWdDo7EsSU1dgpff2eZFaM77aS87BArgLOHvvxuak7y2dIefH9Pp657Qvu9dAJYhBXm05Gnj+nLz
jGFt4uvaIwctXV3NktV7KC62cV2zV9DiFCXOT75GDCU3Hk/wmxdXmw48Odfo+wG6lRXy0LzJZt33uAPtlCc4BwiP2O85JZUpv7Zs3X7WbTscrP5niUABnAN8
K+C1pTuoPlRHyLZxHBel1Hl6ZY/tapOQ/ICXJpubbOTl/pB2FL95bjWJRBpLYvIX2k1iagvlKqJRm8Wr9rFs7f425Brf+XfPnNGMGtyNlngSjWvqFLq686/d
NSFURxmqcyyR4vmFm821d9ZDvcIQMAHPAb7X/ciJZl5fso0/+8T1xG3Rqbn/7UFgYvDXThrIh++YwE+eWNHqc18hvLt2PwuW7+b2G0Z5FX50h/wUWoNt2zQ1
pfjVs6sM5TjH1+Arg+EDK/nE3VMpikawpYVlCdPFuPNNAAx/QaK06VS8eHU1qzYd8qySYPU/GwQK4JxhJt5vXljL3sMNHvf9QpzVkGVsy+bI8aa8xTj8WP0v
n1rF9VMGEwpZKN0xn4DWmnDY4qk3trJu25E2CT/+uVxX85+PvIvjqkxzVD8D4Vx8D3nHhGflKI2wBOu3Hc1xSnbqqa4YBArgHOFPvNqGOM+8tfniDuYkZDoK
7TzK8ws285G7p9LSkqJdWr0HP/fg8NFmHn1hjXEsnhTh9K97z8E69hysO2/X0BEEwn/2CBRAJ8GQ+y78TtTfh5+q6o3W8OhLa7nxmiH0rCg2kQHh19Uz/5Na
oES2OpCU8NSbG9h9oC5vum/m/F34ugOcHoEC6CRkk4K6FvxEoT0H6nnmza186aFrSDkaW4JpLSZN6rDQSBRKS0Ihyc79dTzz5qbThta66nUH6BiCKMAVAiHg
6Tc2snt/LZGwQLm+RW9Sf5UAjWXCmRr+8NoGDh1vDmrqXeYIFMAVAD+N+dDxJp54bb0JqWuNefxemzNtKL/RkMX6bUd4ZdG2jJkd4PJFoACuEPh5As8t2Ma2
3bWEo6bhqdDSYzCZjMNE2uXJ1zdR19j5HX4CdD0ECuAKgc9ZqG+M8+gLa3CUIRJpr+GnKaphsWrTQd5c5iX8XOxBBzjvCBTAFQTfCnjt3Z2sWH/Ia3KiUUIj
pCaeSPHYC2vbJPwEuHwRKIArCL4VEIunePTFtTTH00ghUUoRCYdYuLKapev2tUn4CXD5IlAAVxh8JbBkdTVLVu0lGpEIJPX1Mf7wyjrSJyX8BLi8ESiAKwx+
AZG04/Loi+uoqU9QWGDz2tLtrNx4KMiqu8IQKIArEH5YcNXmQ7yzYg91DTEefWm9x7W/2KMLcCERMAGvUPiFPh9/ZT2bdh9j1/5aIGildaUhUABXKHx23/rt
R1i//Uim416AKwvBFuAKhykLHgj/lYrAArjCoTN/BLgSEVgAAQJcwQgUQIAAVzACBRAgwBWMwAcQ4JJApoehXx2cbKqyaSp60YZ2SaPLK4D2iSnnnqoqMn+0
xqkOa0ppZZuB+115OzoJz+v1tHPsU1/POZ2yQziXyxJeezOl/M7B+b8npQlldGbxEqNvckqttzm5yBQkvVQTp7q8Amj/vp77DT8bD7jW2QLUmb+9f5wqlu5/
dqrrOdf8+7P5aVeet5YUuMoo1pBtMXJwNwb0LqOsJIqUgqaWFEdONLJtdw1NsSSQ7VJ8rtfllz0/dbnx7Hn8heFSq57U5RSALyghW/IPn7+R8SN70RJPmWaT
Gm8ySN5atpNfPLXK6z1/ZjddemWu7r5pNB+/dwot8XSmlr8lBf/72HssXbMv8z1/TOGQxd2zR9G7ewmOozLvHTzWyIsLt5lEGlorAV+oh/Sv4Btfmo1tW6ic
hp5CQDrt8rMnV7B0zf7MOTt8v0T2nvzNZ25g8pi+xOJphISQZXG0ppnv/OhtTtTFMmPxzzF1bF+++onr8PoAd2oRbw3YUtAcS/E3//EatQ0dLzAiPNPMVZre
3YuZd+MobpkxnP69SikrjRIJ2QgBKcelqTnJsZoWlq7dx7NvbmbbnhMAbZqYdBT+GJUyvQdGDu7OtZP6M2Jwd/r3KsVxFSHborY+xpbdx9m5r4bVmw9ztKY5
0zNSq0unS0GXUwDGpBakHcX7G/bz8F2TgGyjCzCr8PTxfYkl0jz24vrMSnEm5wAYPbg710wcQFNLEktKlNIUFtg8v2ALS9dwso1PRWkBX/7IDPr1KiOVdjJ9
8aIRm2nj+vC1/37La4/Vun6+EIKDxxrZd6iez8y/ivrGbPdcU9tfMnxQNz71D0+zfW/NWU3egmiIaeP6MW1cP6MABNi2RU19C8WFYaMA/Gv3/tGvZynXTxnk
tfzq5Br+GqQEV2kKC8LUNsQ79LusAtQ8MHcCn/7QdAb2KUMpTSrtkEw5JBKO+bKASMhm2MBKRg3pzn1zxvLkaxv56RMrvGd6ZvPCv+9SwLyqUXzotnFMGt2H
aCSU9UF4qlJrmH3tUASCA0cbeOu9XfzxtY3sqK41fopO2NJdCHQ5BQBZoXn5nR3067WYP/v49TS3JLEss8/TgG1Z/PnHr2dHdQ3vbzh4VkKTTDs0NidoiqWw
vCw4xwmTcvL3z9NoYsk0LbEUKcdFelVzYok0H7p1Apt3HuexF9fnHUsy5fJPP32Hfr3KuGbSABob4xkl4LqKyvJCvvWnc/jcN56lqSV15tsBDS2xNI3NCWIJ
ByE0trRoakm1aw6nHUVjS4pUKm06DHfifNVaIKVGncH+2L9vZcVR/uGLN3L37NGk0g5NLclMq3NLylaxK60hkXRQWhMJW3zh/qu4ekI/vvbfb7KjugZLSlx1
+n6IfunzXt2K+LvPzuL2G0aigXjSoTmWyp7MN7lEtu1Jr27FfOoD05hXNYpfP7OKXz29JtMgpqurgC4cBjStqH719GrefHcHFWUFpjGmJbEt81ALC8J8809v
ol+vklYWQkchhGl+aUmJZfkvcUrHmBQCKbMvSwqkgHgyzV98YibTxvVt00bLN7sTSYfv/PhtjtU2U1hgVhVLCsIhi5ZYiunj+/HXn56ZmexnCimFuQYpstck
2z+QESj/N7n3QLa6xo6+cn9vWeK05289FiOAFWUF/Nff38EHbhlLU3OSdFphe+Pxy5QprVHePl8Ic922JdFaU9cYZ9LoPvzkW/cwbkQvXKVaPYt2z601wwdW
8LPv3MsdN46mJW4Uvf+MLP86vfNZOdeddlzqmxKUFEX4m89U8f/+7BaKC8IZa7Yro8sqAO3t9x1X8c8/W8TeA7UUREOZldWSgpZ4ihGDevAPn68iFLK8JhUX
fqxCCBxHEY2G+Mcv3kj3isI2Ckl53YT3HKjnX3/+DraUreru2ZakoSnJg3dM4sF5E1BKd1h4OhtSGKV0Jq9I2D5rH4LwXuGQxXe+MoeZUwdTUxfDtmVGeLU2
lpLA1C4M2zZSClxXZeaEEIJQyKKxOUnv7sX8x1/fTv9epZkOSXnP7b3fo6KQf/ur2xk1pCf1jYmMQgNwlfH3hLxrDYVMayXHVRlr1bYkrquoa0zwwB0T+fvP
zfKbGXfpxqVdVgFAtgX3keMt/OP/vEVzLIVly4xJaYQmzpwZw/nC/dPPygroLFiWpCWeYsywXnz9izcSCZtJkjsc3zJ4ZfFOfvj4cgoLQig3a55Kz2n25x+/
jqsm9MU9yZK4EBBCkEg5HK+NcbwuZv4+xetEnXkdOtZ01n0RpTQr8OcfuJrbZ46ktjFOOJTtX6aURkgoLY7gKsXx2haOnGgkmXIoLowQDlu4OfcxbEuaYymG
9K/gH/9kNpGwfUop1FrzufunM2FkHxqa4oTsrFgopSktimJLQV19nOO1MWrrjT+jorQA27ZwMuc2iqA5lmTr3hPeW13bIdglfQC5UEpjWZL31h/gP369hG9/
+WZjmnkPVFqSWDzN5+6/ivXbj7JoxV4sS+C6F/6225akoTnBHbNGsbO6hh88ttw4onL2wL4S+OHv32fE4EpunzmKxmbjFPTj3UUFEb7+xdl84u+ePiPv+bnC
VZqSwhAvvr2F7/18cYfOa0lBMu1yx6yRfO2LszONQX2BO92wpeeomzauH5+4byoNTQlCVmsBDNkWybTDI8+t5aV3trP3YB2u0vTqVszsq4fwwNwJ9OpeTDzh
YFnCiyJZNDQlqLrKfP7b59a08c34DsdRg7sxr2o0zbEUttV6TSyMhnh96Q6eX7CVlZsOkPK2JFPG9mHauH7cO2cMvboV09CcQCAoLAjx348s5bfPrb0kyqp3
aQvAh+uafdyTr27kqdc2UlIUyWhdgV/EQvDNL93EiEHdcN32Tb7zDUtKmmIpPjv/KmZOG5h/FffM2e/9bDG79te02tpIb2szakgPvvGlm4xpfSG3NsJsV5pj
KZpakjTHUqd8NTQnGTWkO3/96Rsy+/DMZWpOa8GYNuSSz98/naKo7VUrMp8ppQmHLI7XNfPn//wy3/nxQlZvPkRtQ5yGpgTb957gJ0+s4NNfe4ZVmw9RGA21
8vpbliSZcvj4vZPp27N9P9Hsa4fSrbww0zPRP3ckbPPLp1fy5X96kdff3UltQ4LmWIr6pgRvL9/Dv/9yCR//2z/y7JubKIyGKSuJ8sPH3+PHv1+Z4SN0dVwS
CgCyK8m//XIJa7ceorgwnFnlpRQkUi59epby7S/PobgwnG0lfSHGljM+IUArjZSSr31hNgN6l7brDzh0rIlv/u8Ckimn1YSxLUljc5J5VaP4wgNXnXIPe34g
Mk0/feVz8st3ypWXRvnGn8ymrKSAVNrJjNN1FUUFYZau3suJuhZPqFsLhH/NV0/ozzWTBtAST2dWYOU5fBubE/zVv73GktXVOc5AbwxCYNuSPQfr+Or3XmHj
zqMUROyMEpBCkEy5DOhdzp03jjZXlnMb/dGMG97L26+bd1ylKSoIsWLDfv7rt8vQmoxz2L8v0nO07tpfx1/9++v8+unV/OKPK/jBo8sviZXfxyWkALzGFk0J
vvvjhTS3JAmHrAxpxrYETS1Jpo/vx1c+co1ZfS6QzFgiSwkFTyEl0wzpX8G3/vQmigpCcFK9PX8rsHz9AX78h/cpLgy3IgBZUtLYkuRTH5xG1VWDLrg/wKe3
+s7Yk19grK+vfvx6xo/oTXPMcCn8ayuIhNh7qI5/+8USkikXP3aeD3fPHk00Yre6fu2t/j947D1Wbz5EyJY4nsPPH4PSGscxJvmJuha+86O3aY6nsGTWuSql
IJV2mFc1kkLP0soUQdGakCXpWVmE8vkemd9JVm46RNpRmS1l9voNUSg3wvCvv1zMP/9scebmXSLyf+koAMgKzfptR/nez94xqwHZCWlbkqaWFA/dOYV754w5
r0Ljn1dKs+9POy62lZ3klreKz5o+lC8/fK0Xsmo9Fu2t7L9+eg3Pvrm59dbGsyQsKfmHL8xmUN/yi2AJ5Ifl7aUfvGM8D8ydQFNLMrNy+2a/47p86/8WUH24
wfAlTpIIP+zXp0cJk0b1Jpl0M8/KkIdCrNp0kGfe3IIlDTGsPTiuwrIkG7Yf5enXN1NUEM44BY0CUPTvVcbUcX3NuXPmRGZ7dbK3XuSwNU/hQczHPblEZB+4
xBQAZJXAU29s5tfPrKK4MNKK6KExMeK/+1wVk0f3bhOT70xorQmHJEdPNPOjx5fjuBopaaUEGpoTfPSeKdw7Z3Sb0J72XinH5Z9+soj1Ww+byZvjD0gk0wzq
W863v2wsiZMWqgsO32l37aT+/NnHryeedFqb1VpTGA3x/V8tYenqfUZZ5FkO/dswemh3BverIJV2s8rNo18/88ZmkimnQ+PyFczzC7ZQUx8jZFmZ5+C6irLi
KFeN6wf4dF/zd8oxoTvz3LxwovebaycPIBK2M76BLBfg4ivhzsIlpwAgux34v8eXs2xtNWXF0czKKYUx+UqLI3zrT2+iorTg/IUHPa99YUGIP76+mUeeX91K
IflnVErzl5+cyYhBlW2sEj/UWd+U4Ds/epuWWJKQLTNC41sS108dxFc+OiNDKroY8Nly/XuV8s0v3ZRZaf1767iKkqIIL7y9hUdeWIcU7VNx/XfHDO3p3Q/z
jnEKWhyrbeG99fsB4w84Hcwzhm17T7B1z3HCYQulvecgBY5SDB/UDdsynZB87gHA1t3HW80RKQWxeJopY/ryrT+9ib49itFa4ypj+vvPRgijDKQ4lY3QtXGJ
KgDz8OIJh+/+ZBGHjjUSDds5JCETBx49rBd//ZmZmRDbeRkLZixFBSF+9Pv3Wb5uH6VFOQpJGkdUt4oivvGlmygvjaJPdgr6W5vtx/iPXy/NEE18WFLS0Jzk
oTsncffsUReHH0A2SetvP3sDwwZ1I5ZItzLbiwrCbNpxhH/+2TucInMXILMXHzaw0ijMjOdfEQlZbNp1jBN1MaDjVGJ/W7F68+GMWW/eh1TaoX+vUspLC4xl
kHP/312zzzyvnFsqpSCWSHPvzWN49F/v59tfnsODd0wwiUGDumXGlWElcvqIR1fEJakAIOtJ37G3hv/304Vk02nN58YfkOQDt4zjIZ9ZZ52fB6QyVF+Xb/7f
2xw4Wp9xOIHxIDfHUlwzcQB/99kbWnmyM8fwhPr3L2/gyZfXU3qSPwCM4vvbz1YxanC387q1yQffY//J+6Zyy/UjaGhM5Oz7NbYtiSfTfOfHb1NTHz9lGCyX
w9Gzssh7Zh7jDwiFLQ4cbjDbgjO4Rv+be/bXYgmZOZEfKq4sL/Acstm+CELAqk2HWPT+HkqKIq18DVIIWmJpulcW8eC8ifzLX9zGD752Fz/91r08/u/38y9/
cRsfu2cy44b3xJJZf0BXp//m4pJVAEBmT/360l388PHlFBeFUSr3ARor4SsfvY5rJw0w/IDzJDT+ZNpRXcM3//ct4sm0JwTmcz+0d+/N43jwjgmeQ6/17dfe
Mf7lF4t5d001JUWRrDNLCFIph4qyAr755TlUeCvZhZhs/r5/1vRBfOnha036tMyOXWuIhCz+6zdLWb35SIcTs0K2pKQo0spjbqw7QV2jYdudzfXVNsRPSgAS
KAUF0TAFEdt/K/OZ4yr+6SeL2LbnOOWlUdKO2yqi4zgujU0Jjta0ELIl3SoKMySgv/9cFY/864f4v6/fzc0zhnnX0DWctR3BJa0AIGsJ/OKp1by8cBulOf4A
IQxXvCAS4rv/382ZtNLztXBqbQR98ap9PP36RooKwpl9qBmPyVz78kdnMGVMnzaJKv7kjyUcvvXDtzl0rJFIJGdrY5mtzfRx/fj7z1ddEGegL8xD+pXztS/O
xrJkZr8NxvQvK4ny3FubefSFdZl8+A4d24vjQ67H3QhQIuk7/zruU/e/mUy5pF23zb7cT3xq9RtPWA8db+Kr//IKm3cdo7KsECHMtbk59z4ckiiFUQheFmlL
PI1AMPuaYfz338/j+39zO93KCzNWYVfHJa8AvNRxUmmXf/75IvYcqPHM7+wePO550v/uszcQDsnzGqZxXMXwgZXMnDbEEHxyJoFf56C0KMq3vnwTfXoU5yUJ
WVKwe38d//rzd7zMwOznhm6c5J6bxmS2NufLCvDbhJeXRPnGn97EoD7lJBLpTCTDd4AuXrWH7/3sHa9gS8e570pr0mnznPzfaIxiyKzUZ+Be878ZiViEbKvN
OFylc3j7rcfhbyc/8w/P8PhLa3FdRUlRmKKCEJaX6JN2VOb6pJSZqABAU0uCRNLh7jlj+d+v3UmvbkWZHoxdGZe8AoDsAzx6ooXv/nghqbSLZZ2cNJTgphnD
+cyHzk/SkM+aK4jY/MPnqxg5uDvJVNtCG34W4+ghPfnaF6oI2TJDTPHhO/leXbKT3zyzipKicKtkFylMDYKvfPQ6po/rm4kknA9oYe5fSWHErIatmHRmlYvF
0jS1pM44Ppl2FE0tiVY/E8I8z8ryQnOOs2DUdCsrxGo1FhOejcVTxH3L4qTD+hyLE/Uxvv4/C/jY3z7Jz55YwdY9x2loSlBeGqWyrICiwhCRsG3IQV5UAMik
UNfWx7hqQj++9eU5FEZDmWvqqrgsFABknWiLV+3j3365mHDIbrW3lFLSEk/zxQevYe4NI9BaY0mr/QOeIaTHBPzig1dz/dTB1DXGWzkdcyey7w+4ecYIPn//
VXlXCt80/Z/HlvPq4u0UF7Xe2jiuoqgwwne+cjO9uhWdscOsI/DHcKI+xnd+tICWeNKsrH6IUkpaYiluuX44f/rw1Znw7OmPa/52XcWRmpZWNFwBpNMOA/qU
EQlbmWhBx8Zr/h42sNIkYOlsaNGSgpr6OC1ecY98aiX3OWzedYJ//9VSPvbXf+QL33yOL3zzef7rN+/y2pKdVB+s8zIRw0Ryok9gkpDqGhPcdM0w7po9ssP3
5GLhslEAkFUCv3txPU+/sZGykmhrZp03Ib7+J7Pp36vUlI2yJOfK3bI8BuLtM4fz6Q9Nb0WLBb/sl3WSQjJhps8/cDWzpg9sSxLyvptIOvzTTxay90ANhTkk
IUsK4vEUwwd35x//ZDZg8tY7e675K+ParUf5r9+8S9iraehDSEFzLM1n51/NvKpRHY5O+N/Zta/GWGuZ9yXJtGLssJ70qCz2Mgs7dlEacw+nju3rhfr89yEc
sjlwpIH6pkQrhdPmGDqbRyCloCmWYvOu47y5bBc/eOw9vvq9l7n/z3/PA3/+B/7z10vYd7jOJHPlHM/3Pd03ZxwlReGLmqZ+OlxWCgCyVZu+/5t3Wb/tSCuh
kcLkuncvL+LvP19FWUmEtHNu9fAsKWhuSTFlbG/+7vNVmcSg1mat4ERdC3ZOLQMhsnUO/+Hzs+nXq9Tk05/kD5BScOREC//vp4tIpRzDc88lCTUluOnaYXzu
gekkkk4ObbXzJpzvl/jdi+t56s1NlJdGcZws2cmwL+HvPzeLEYMqO0RZziXhOG7WqSiEcbJ1Ly/kuskDPJ/A6cfoR1zGDuvJqCHdPf+LF6b0krN2VNd4maXt
+4H87Zjy+P5+0pHlJT+5StMST7PnYB0/eWIlX/jmc2zYfoRIKJeHIognHcYM78nwgd0y19UVcRkqACNEtfVxvvG/b9HckvBWraw/oCmWYubUwcydNZJE0jlr
b63wKtcWF4X560/Pont5EcmkkyXHeBlxa7Yc4ovfeo6tu49REA1lQlSG6uswqF8F3/5Tk8UI+fkB76ys5oe/e4+iwnArk1N4RKOP3DmZYQMrc/wOnevq9E/5
H79cwooN+01xjpNClN0qivjaF26kMENZbv+++sfbsvsEe/bXGgHKYdhp4L6bx1IQtTtEf/YV3703j6GitMCj75rPLEvQ0BTn/Q0HgFP7FbIK3OMleElHpjx5
NpFIeBGMfYcb+a/fvtuW1+FRoocPrDj1wC8yLjsFAFmh2bD9KP/xqyWEw7KVPEgBjuvSvbzorM/hT8p02qVfz1IG9C7PpPX6Y4h6GXHf/uHbbNtbw//7ySIa
mxOEchSS5WUxVl09hK985Nq8e0Z/L/7rZ9bw8qKtlJUUtKqHoL2iKSdP/M6E1hohBXWNCb75vws4VtvcKhvTsiTNLUlmTB7En3/sugyn4VTHk1JwrKaZdVsP
m710Tnp3LJ5m8pg+3H+7iXScXKgjF36NyOnj+nHPnLGmcpSVzUwMh2z2HW5g7dbDmffaQzhkURgNeT6ithfgKwitNa5rntW+Q/UcrWn2tnnZYytFRql3VVyW
CgCySuCJVzfxi6d8T3rrfVq+kNDZwFEax81uJTRmZdZovvezRew9WE/Itli79Qg/eGQZ0bDdSiH5lYQeunMyc2eNyFNU1Hw97Sq+/cOFrNly0Esa8sbvx+Td
UwvducL3U2zbU8M//3RRGwGRHgX7oTsnZZKfOuIPeHbBVmKJFDLHaSqlIJl0+OKDVzNj8kAvLTdbHNTPybctkybct2cpX/vijUTDVmalBrMSh8MWL7y91Vh7
7YzHf/+rH7+OX373Pgb1Lc9EY9rj+gthbr1lWcZSyXU8YMqiJzqYzHSxcNkqAMhuB37wyHu8u2Zfm3BaZwmLMQtz9u5KUVwQ5hd/XMmC9/Zk0mOlFDz20gZ+
8+yaVqm/2d9p/uFzN+al+vorZm1DnG/939s0t7T2yHfm9ZwKrqcEXn5nB4+9tI7y4uhJlGWTo//3n7+RCSN7ndIf4PtAVm8+xJJV1RQXhFsdy1WagmiIf/mL
27jlumGZAqCmToHZozuuYszQHvzX393ByEHdSOSkFfvNPfbsr+Old7a1qtmQCz+9+R6vUczU8f34ybfuYc61QzPJPz7XP7dCsP/Z7KsHUVla2Mr6EkDacdm1
r75T739n4zJXAOZBJFLGk360ppnwSWGbzobjGqLPa0u286Pfv5/JhffNRo3mP3+zlOXr91F6MtU3bfbR3/7KzVSURtuShDylsGnnMf7rt0tNmOx8spragR8u
+59H3mPB8l2tKMtCCNKuorjQlGzvXlFwylCYEMZX8tMnV9LYnGzl5DQ0XEVZSYR//cvb+d5Xb+X6qQPp27OEXt2KmTS6D1/9xPX87Nv3MnZ4T2JJp1Xo1VUK
27b45dOrOFbTkrdSj+/YGzWkO3/xyZk4rqauIc6A3mX859/ewbe+PIcxw7p7WYQ6ww40Wzyb+24ew588dK1xwIrWimfvwXqqD9UBp6+NeLHQ5YuCnisyLK/q
Wr7744X859/egSP8fPDOPZerjNNv+97jfOdHb2cccv7D19oIejzp8J0fLeRn376XirJC0l6TEcurKDt1bF/+6tM38I//85bZY+dk1mlPCTz+8kZGDenBw3dN
oi4nMedCwFwHNMdSfOMHC/j1P3+Avr3KMg5QQ3ZKM3Fkb/7ikzP5u++/keFJnIxskZcj/OyPK/nrT8+ktiFByDYPx1hPCikE9908lrmzRtLcksJViuLCCIUF
Nqm0SyLpZLYkAkg6isrSAl5ZsoOn39icNz/BVwgD+5Txb395O5XlhSSSDpGQldkuPHjHBObNGsnqTQdZsemQl6Go6duzhOunDGLCqN5oRastoNKaUNji9aU7
OFrT0uHciIuBy9oC8OFPsteX7jSe9ILWcdvOgHEamYy4f/rJQo7VxvJmxPkKabvnFLSsbLdhyLIWP3TreB68Y3zbrQBZQfr3Xy3xtjaRVlubC4FMXcPjTfy/
nyzCdVxETjGUTPLTnLE8MLftdbQ6lvfZL59axbNvbaGyrICU42Y+l54SbWpJ4rqK4qIwZcUFCAHNLSkcR7XyR6Qcl9KiMJt3H+e7P3y7VXJPLvwFYOSgSsYN
70ky5WSehR9WbGpOYdsWN1w1hL/9bBXf/9s7+P7fzuOrn5jJ5DF9SafdVsLvOEYx7dpXwyPPrwPOjs14oSC1ZhuAbUsd8fjXXTVmeS7wy2/95IkVLHhvV949
+LlAaVMT4H9++y7L1h7I7Cvzfteb8K8t3cmjz62htCh6Un8ASdyj+k4e3TtvEREhoKklxbd/uIATtS2mAMYFXmX861i4Yi//+7vlbaozIUyOxl98ciZXT+x3
Sn+A1mbP/63/W8DrS3fS3avSm02xxavrYEg2rnLRZN8zx9Ck0y7lpQXsPVjPX/zLKxyrbWk3NdmP87+9opp/+slCCqMhImHL4/z75zTPMRZPU9sQ40RtCyfq
WqhtiBNPpDMOSTDCXxC1iSVSfPdHb1NTH8sor4sN/7ZHIja2LTWA1myTQtBgviB0LnvtcoOXM4Tjar7zo4Xs2neCIs/p5Bd18F+ngp9Q4novx1Wk0i7lJVGe
e2tLJiPudMfx98X//ch7vLFsB8VFEVJp13N0KRIph2gkxNe/ONsUrWzHH7BzXx3f/fHCDHPNVa2v5XSrz8nXfqaWUTZEuZo3lm6noqwgc08FRgEURMN880um
sk57CTK+576pJcVf/usrPPLcOooKwoTDpvGGH4cHMkInyBbodLzS8RWlBby7eh+f/8Zz7KyuOaUiNuc1PohfPr2av/43ozC6lRdm7qWxrMy9DtmSUEiavz3F
o5QJByqlKS2O0BxP8Rf/8rLp9NyBeXChYZmOVBpACBqk1mRU9uW48ufC96QfOt7EP/14IS2xJCWFEQoiNoXREIXREAURO5NIcvLtEAhKiyJUlBZQXhqlvDRK
WXGU3t2LWb5+P9/98cJMP/vTPXffQRlLpPn2/73N3oO19OxWRGmJOW638gLCIcn1UwfyH39zOyVF4TaxdV8JvLpkB798aiVFBWb8BZFQ5noikfbdPH7yUkE0
RKH/m0jojFqSZUKUjuJb//c2qzcdoqwkSjRsE42ETBxcayaMNExJ0/EnP7/fVw6xRJpv/t9b/PW/v8reA/UUF4QpLgybVGStcRzzcj2LojAaoqQoQmNziu//
Zilf+NZz7DtcnxHijkBKwQsLt/PJv3+KR55bTTyRorQoTElxBNvLLEylFWn/5RiFE43YlBSHKSwI8dZ7u/jE3z7Fwvf3dtl9f+780Rolpk8Y+B9Siq8KIdzq
Q7XWkWONeb2llxOyHWG6M3Oa3x47W+l3wfu7OXAkex/8v0uKwvzVp29gQO8y8xuyhT+//+ulrX7T4bF4E2Xq2N584r5pFEY9pl8rKjF8/1dL2LL7RLuebNDM
vnooQwdUGOcjpuFGTX0Lry3dlZNfny3vVVIUZu4NIygqyPoQbEuyaOVedu2vbTdslg/+MYsLw1RdNYRelUWZMltam4Ih+4808OayXacVSvMszDOqKC3g9pkj
uHXmcAb3raCyvJBoxEIIQSrlUt8U59DRJhavrua5BVvYd6i+1X09E+T+ZnC/Mu6sGs30Cf0Z2KeMyrICKssKM89Ga83RE83UNsTZuuc4T7++mWVr92W2a11N
+P1507tnKYP6Vrpaa0sp/X0xfcKAb0spvy6EcA8fa7D2Haq77BUAcEaT+3wf83K53519T3MFSQCD+1fQt0cppcURpDRRiGO1LezeX+v1HsiWLjvbceT6E3wM
6VdOr+4l9OpWlMnXUEqz/3ADh483ctyrXQjZxaWrIRPx6FtBn55lngJQ37FxWamFRoAsiJj85cthMp4OPt87nymqaX8C5du/+qvf2d4338o4FYO/I8dul3DT
zm99Tnurk4os1fVM4TvO2hzT/5wzO67vpPMFbs+BOvYcqMv7Xd9rf64rb242IJh7t+dgPXsO1rf7m1b+iC4qO/51FURCoLXUWoPLShuld2tNQgsRDYftLmm+
nC+cSfWa3N+0ee8ijeVknLkDL8/1nOMgzlZ5dOR40t+nkVW6hiOhO33Onpzem3Pq7NhyxncpSIyUgnDYRoPQWidQerfURe5urTkMEA7bKhy67LlBAS5R+Cm6
PiMvQ9M9z9KXbQXW+uXTki8VhEM24bCtALTmsC5yd8tVqw7HhBBbBGBLoaOXQBmjAAECdBy+LEejIWwptJe7smXVqsMxr2ICy73Nli4pivg/uyiDDRAgQGfD
yHJJUQSEMI4VzXLwcgG0Fu9oY8vIkgKjAC4l0yZAgADtw5flkoIIWmtp3hLvgJcLkJJ6nXJVo9ZaFhSGdcSLBgQIEODyQCQSoqAwrLXWUrmqMSX1OgA5H6wN
G/bVIVgqhMCWUvnbgK5ayDBAgAAdgy/DJUURbCmVMOGMpRs27KubD5Y8VlXl513+0dRi01SUFADBNiBAgEsdvgxXlBSgvf6ZSPlHgGNVVUIuWrRIATjCWeK6
Kq61liXFUX1yh9oAAQJcmgiFLEqKo1prLV1XxR3hLAFYtGiRkoAC5Nq1B3eg9AIhBKGQpSq9gpnBNiBAgEsTvuxWlhcRClnG/Fd6wdq1B3dg/H9KAlRVVUkA
Zcs/CiGEUpru5UUetzvYBgQIcCnCzx7tXp5JJxfKNua/L/MSYNGiRS6AEqGXXMc9prWWRYVhXVwUBQJSUIAAlxp8mS0uilLkef9dxz2mROglyMq8XwFEV1VV
2WvX7jyO0I9alhQg3B4Vft38QAMECHBpwciskWHhWpYUCP3o2rU7j1dVVdl4qRSZEkA33rhIAcK1rZ8rpRJKKauyvEhHI6HTNnkIECBA14G/dY9GQlSWF2ml
lKWUSri29XNAeLIO5CiAb30LNX/+fLlmTfUWrfQzUgphWdLt06P0YlxDgAABzhF9epRiWdKVUgit9DNr1lRvmT9/vvzWt2irAAyeBBDakj8FcBwlulUUEYmE
zksZ7QABAnQu/KIskUiIbhVFOI4y7VqMTAtPxrPfz3MMCajp4we+Ji1xK+DW1LVYu/adOC9VdAIECNB58GV02MDudKsocgFLufr1lRv33YYn27nfb1MG+Bvf
8I8kv6K1TrquEt0rinRxUTSwAgIE6MLwhb+4KEr3iiLtukporZMI+RXIke0ctFEAxheAtXLD3m1K8XvbtqTSuAP7lAekoAABujiEEAzsU47SuLZtSaX4/coN
e7fNn4+Vu/fPfL+d40hAXzV2UC9svVlrymxLiupDteLwFVA1OECASw2+TPYxVX+14yotBA04YuyKzdVHMbLeRgG01wlEzZ+PXLG5+ojWfN22pEy7rtu3ZxmR
sB2EBQME6ELww36RsE3fnmWkXde1LSm15usrNlcfmT+/7d4/89tTHXj+fKwnn8SdPn7Am9KSc9C4TS1Ja8vuI5ka+gECBLi48Iswjxnam5KiiIvAUq56a+XG
/Tf7Mtzeb0/ZC2zsWDQgtObzWukWpTVlJVE9oHdF4BAMEKALwHf8DehdQVlJVCut0Uq3aM3nAeHJcLs4pQLwHIJy1ab9u7RWX7YtaaUd1+3bs5SKssJMbf0A
AQJcePit5yvKCunbs5S047q2JS2t1ZdXbdq/a/58ZD7HX6tjdOREVVXYixbhTJsw4Jchy/qk4ypHK21v3nXE65AabAcCBLiQ8GWuIBpi7LDeCCkc25J22nV/
tWrD/k/5Mnva43T0fPPnI7dt6xWNEFkmEBMAN5ZIWVt2Hb3gvekDBAhg+lKOGdaLwmjYBSyN3pAkOWPUqKOJJ5/EtDU+DTraD1yPHYtev/5oi9LqYQ21SmtR
VBBWo4b0xLIu37biAQJ0RViWZNSQnhQVhJXSWhiZVA+vX3+0xdv3d8gmP6MNvO9RnDJ+0IyQZKmrlA7Zljhe1yx2VefvXBsgQIDOgy9jwwZ1p0dFsU47rrak
FGnF9Ws2Vi87ndf/ZJzR0v3kk7hVVdhrNlYvc7T+vG1ZMu24qnt5sR7cvzIQ/gABzjO01gzuX0n38mKddlxlW5Z0tP78mo3Vy6qqsM9E+OEsK334DoapEwZ+
NiTFTx1Xu7Yt5Ym6ZrH3QC2uqwLHYIAAnQRflixLGuGvKNaOo5RtCSut9OdWb9j3s446/doc+2wH1VYJKDdkW7KxJSG27T4WKIEAAToBucI/amhPSoui3sov
z1n44RxrfeWxBLRlCR2Lp+Tu/TXE4qlACQQIcJbwZaewIMzQAd0oLAgr19XCtoToDOGHTij2l6sEbCF+qLS2pRCu4ypr74Eaahti53qKAAGuWFSWFTK4fzds
S7pKa0sK4Tha/0lnCD90UrXPDFFo3MDrpSVeEIIKpbRjSWkfPt7A/sN1GdZg4CgMEKB9+DIiBAzoU0GfHmW4SjlSCltr6pSr71q1ad/SzhB+6MRyv/6Apk8c
NEUK/Qsp5JS047oh25INTQmx58AJEkkz3mBbECBAa+TKRDRiM6R/d8pKzH4/ZFuW0mqN0uLTK9dXr+ks4YdOrvftxyBHjepWUhYp/r6Q4jOuo5DSbAmOHG/k
8PGGQPgDBMgDIaBPjzJ69yg1Jr/SlmVLtNI/b0g2f3XbtpqmM43zn/acnXUgH7kDvGrCwM8Iwb8jRJnraidkS6uxOSEOHKmnsTlhBhBYAwGuUOTO/dLiKP17
l1NaHNVpR7mWJWy0btCav1yxYd/PobVsddoYOvNgucedD/JJcK+a2Hek0Pb/CEveZkKDwpEC60Rdizh0rIF4Im1+IADdQf5igACXKIT3hy/4BdEQfXuW0b2i
SCuNq7W2LUuiXfWaFs5XVqw/tH0+WE/SMW7/WY3nfKGVNTBx4JcRfE0K2dN1zbZAKW3V1Ldw5HhjRhFAYBUEuPxw8pwuiIbo3aOUbuVFGVmwLInS6hia765Y
v+8HcH5W/VbjOl8HzoFPN1aTJvXvF9byO8DDQoiwUlpZUmhXaVlbHxM19c00NicyN+pkbRkgwKWEk61aIYyp3628mMryQm1JoVylhZRCaq1TwGMpob6+bt2B
g+TIzXkd4/k8eC5yNdn0if3HC+S/CiHmCgSuUlhSOFpjxRIpcaKuhdr6GKl0a0enX3skUAgBuiLam5/hkE1leSHdK4oojIa1ELiu0rYlJRqN1voVjfrrlesP
bITzv+q3GvOFOEnu+ebPR/oXN23ygFuklh9F6weklGHPR+BKKUinXdnUkhD1jXGaY8lWW4RWB/TNBF/PBn6EAOcJmamW+S/d7mJUEA1RXBihvLSAkqKoDoUs
pZRGa8/UVyqFEH9QQj2yau3+NyAj+Odlr98eLlY9LwnZnOXpE/uPF9r6uBb6o5aUvbTWHhlCuJ6FIGPxlGiOJWlqSZJIpkmmHJQKRD3AxYeUgkjYJhoJUVIU
obgwQmFBWFtSKm+Ft4QQCCFwlToqtHhEC/c3/oqPkcO8ZbvPNy5qQb/5YDHfpBkDXDN+SC/XUncIre/RWt9uSSuiPS0rBEqA0iCU0iKVdkQy5YpYIoXjKFpi
SQBcV5FIdQpHIkCAVoiG7Uzxm6LCCLYtKYyGiYQtHQ7ZWkqhPZeV1BopBJgFzE0KIV7VQjxnufLl5Rv3HAWz4vMkPMmFMffzoatU9JRVVchcdtO08YNG2xYz
lNb3as1MKUVlhkqc8aqghRAKQGttmiAqLRxXdZXrCnAZwbakFlJoACHM31prifbkSGSpvErpWiFYIoV41nFZtmpj9Vb/OB6TT3ERVvyT0dUERVRVYZ18c64d
278yHbImCVffgGAGWo9C0FcIGcnveNF0vUsLcGmj9ZzKnXdaqySaQwixDc0ybYnFobS77r3NB2pzDuAvci5dyE3VlaVEVlUhey5Cn2wiTZvWp1CkraGWtAa6
jpqBEIVofR1C2FrrEiHEqIs16ACXL7TW24QQTWjtIMS7aB2zbLnMVe4+HXJ3r1p1uFXq63ywjlUhuspqnw//P/SqSKMIbVbKAAAAAElFTkSuQmCC
)"
}

LogoB64() {
    return "
(Join
iVBORw0KGgoAAAANSUhEUgAABQAAAACQCAYAAABXusYTAABByElEQVR42u3dZ5Rd1Xn/8e/e57bpI426UEO9gVChCInejenF3ZhiHCfucf8nbiFxHMfBThwb
3HCJbUAUU2wQoghTVSjqAjXUUJ8+t51z9v/FufdqRnUkBNYMv89as1jce8o+ZzRvfuvZz2N4G02dONghIiIiIiIiIiIiB7Rg8Xrzdl37iF5YgZ+IiIiIiIiI
iMhbdyQDwSNyIQV/IiIiIiIiIiIiR96RCALf0gUU/ImIiIiIiIiIiLz93koQeFgnHkrwt2Dxev2GRERERERERERE9mPqxMGdPvZwgkBzGAtyB1mEfmsiIiIi
IiIiIiKH6WCB4KGGgOYQb+4OcGP9dkRERERERERERI6QAwWBhxICmk7eTMGfiIiIiIiIiIjI38BbDQJNJ27g9nNxvX0REREREREREZF3yP6CwIOFgPYgF1X4
JyIiIiIiIiIichTYXyZ3sJkd9kjdSERERERERERERN5eh5PN7TcA3FdyqPBPRERERERERETkb2tfGd2BqgD3GQAq/BMRERERERERETl6HUoIaDtzoMI/ERER
ERERERGRo0tnQ0B7OBcSERERERERERGRv73OZHcdAsCDTQwRERERERERERGRo9ueGd8BKwBV/SciIiIiIiIiInJ0O1iGVwoAVf0nIiIiIiIiIiLSPbTP+vZb
AajqPxERERERERERka7hQFmeBVX/iYiIiIiIiIiIdDfFzG+fFYCq/hMREREREREREela9pfpWb0aERERERERERGR7ivWlRdvjME5x/gRfbji3PFksj7WmtL3
YehIxizrtzbxmz+9/DdZYzIRIwhC/CB8x99LXW051102mUTMEoYhWAshhIQkYh7b61v45b0vv6NrExERERERERGRd1asO/T/21HfxjknjWDwgFpyOR9jdoeA
GIMLA15bt4MXXt2AtYYwfPsfuRjCffn6GSxY+iZ//uvKd/De4BzceOVUPvXBk2luzeO1C0aDMKCmqowf/u45/CB8x9YlIiIiIiIiIiLvrKkTB7u9tgB3pf5/
zjk8a9i6s4Uf/t9z5PM+ja1pWtqytLTlaGnL0dScIcTxyWtPJBazOAfmbV6XtYXKxOF9+NAlJ/DRyyaRTMSie5u3/95h6BgxuI6rzpvAjl2ttGVypffR3JIm
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
zEP16VkBBgyGhuY02VyAMVGoVltdxrCBtfhBSMzzWLl2O22ZfOn7vV5G4XPPM4wb3gdbqJCLxzy27mxh09amDltxnXNUVyYpT8VxDtoyOZpbcx2u2bOmjHjM
A6C+KU0uHxz0mcpTcaorkwShw5poe3JrOreP9e4O9E4Y258TJx5D/95VhM6xbmMDz73yBqvW79rr2D0VnxOgpjLJ8WP6M3lsf3rXVQLQ2JRm8etbee7l9TRq
26+IiIiIiIiIyFFrzwBwweL1pssHgCIiIiIiIiIiIhLZVwBo9VpERERERERERES6r30GgPvaKywiIiIiIiIiIiJHr/1lehaiUkC9IhERERERERERke6jmPnt
dwuwqgBFRERERERERES6hgNleaUAUFWAIiIiIiIiIiIi3UP7rO+AQ0BUBSgiIiIiIiIiInJ0O1iG1yEAVBWgiIiIiIiIiIhI17ZnxmcPdoKqAEVERERERERE
RI5Oncnu9goA91UFqBBQRERERERERETk6LKvzG5f2d4+KwAVAoqIiIiIiIiIiBy9Ohv+wQG2ACsEFBEREREREREROfocSvgHnegB2JkbiIiIiIiIiIiIyNvv
cLK5AwaA+0sOFQKKiIiIiIiIiIi8s/aXyR2o+g/AdPLibn/fLVi8Xm9fRERERERERETkbXKgYryDhX/QyQCw3c0UBIqIiIiIiIiIiLwD3mrwV2QO48buQN8r
CBQRERERERERETl8B2u/dyjhHxxGAFhYhOvssQoERURERERERERE9u9Q5m0cavgHhxkAtluc069IRERERERERETk7XU4wV+RORILUBAoIiIiIiIiIiJy5L2V
4K/IHMkFKQgUERERERERERF5645E8Fdk3s6FKhAUERERERERERE5uCMZ+O3p/wP5oIgs0kz7LQAAAABJRU5ErkJggg==
)"
}

; ============ dark mode ============
AddHint(g, opts, text) {
    c := g.AddText(opts, text)
    Roles[c.Hwnd] := "hint"
    return c
}

OnDarkToggle(*) {
    global DarkOn
    DarkOn := !DarkOn
    swPic.Value := DarkOn ? SwOnFile : SwOffFile
    Save()
    ApplyTheme(Main)
}

SetTheme(hwnd, name := "", sub := "") {
    if (name = "")
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Ptr", 0, "Ptr", 0)      ; back to the default theme
    else
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", name, "Ptr", sub = "" ? 0 : StrPtr(sub))
}

RoleColors(role, hover := false) {
    d := DarkOn
    switch role {
        case "btnprimary":
            return hover ? ["E3C486", "141414"] : ["D0AE6B", "141414"]
        case "btndanger":
            if d
                return hover ? ["55292F", "FFB4B4"] : ["3B2226", "FF9C9C"]
            return hover ? ["F1CBCB", "B3261E"] : ["F8E1E1", "B3261E"]
        case "btnghost":
            if d
                return hover ? ["1F2127", "ECECEF"] : ["15161A", "A9ADB8"]
            return hover ? ["E9E9EE", "1B1B1F"] : ["F5F5F7", "6A6A74"]
        case "btnbanner":
            return hover ? ["3A3E49", "E3C486"] : ["22242B", "D0AE6B"]
        case "btnupd0":
            return hover ? ["3A3E49", "B8BCC8"] : ["22242B", "6E7380"]
        case "btnupd1":
            return hover ? ["2E8A4F", "FFFFFF"] : ["1F5C34", "7DF0A0"]
        case "hdr":
            return d ? ["1F2127", "A9ADB8"] : ["E9E9EE", "5A5A66"]
        default:    ; plain button
            if d
                return hover ? ["3A3E49", "FFFFFF"] : ["2A2D35", "ECECEF"]
            return hover ? ["D6D6DE", "1B1B1F"] : ["E4E4EA", "1B1B1F"]
    }
}

; flat "button" = a clickable text control with its own colours (no system border)
AddBtn(g, opts, text, handler, role := "btn") {
    c := g.AddText(opts " +0x200" (InStr(opts, "Left") ? "" : " Center"), text)
    c.OnEvent("Click", handler)
    Roles[c.Hwnd] := role
    return c
}

PaintBtn(hwnd, hover) {
    try {
        c := GuiCtrlFromHwnd(hwnd)
        if !c
            return
        col := RoleColors(Roles[hwnd], hover)
        c.Opt("Background" col[1])
        c.SetFont("c" col[2])
        c.Redraw()
    }
}

; hover effect for the flat buttons
HoverTick() {
    global HoverHwnd
    h := 0
    try MouseGetPos(, , , &h, 2)
    nh := (h && Roles.Has(h) && SubStr(Roles[h], 1, 3) = "btn") ? h : 0
    if (nh = HoverHwnd)
        return
    old := HoverHwnd
    HoverHwnd := nh
    if old
        PaintBtn(old, false)
    if nh
        PaintBtn(nh, true)
    try {
        if (nh && nh = bUpd.Hwnd)
            ToolTip(UpdAvail ? "New version " UpdInfo["ver"] " available - click to update" : "Up to date (v" AppVersion ") - click to check again")
        else if (old && old = bUpd.Hwnd)
            ToolTip()
    }
}

ApplyTheme(g) {
    dark := DarkOn
    win := dark ? "15161A" : "F5F5F7"
    box := dark ? "1F2127" : "FFFFFF"
    txt := dark ? "ECECEF" : "1B1B1F"
    hint := dark ? "A9ADB8" : "6A6A74"
    g.BackColor := win
    flag := Buffer(4)
    NumPut("Int", dark ? 1 : 0, flag)
    for attr in [20, 19]                       ; dark title bar (Win10 1809+ / Win11)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", attr, "Ptr", flag, "Int", 4)
    for hwnd, c in g {
        role := Roles.Has(hwnd) ? Roles[hwnd] : ""
        if (role = "skip")
            continue
        try {
            switch c.Type {
                case "Text":
                    if (role = "hdr") {
                        col := RoleColors(role)
                        c.Opt("Background" col[1])
                        c.SetFont("s9 bold c" col[2])
                    } else if (SubStr(role, 1, 3) = "btn") {
                        col := RoleColors(role)
                        c.Opt("Background" col[1])
                        c.SetFont("s9 c" col[2])
                    } else
                        c.SetFont("c" (role = "hint" ? hint : txt))
                case "Edit":
                    c.Opt("Background" box)
                    SetTheme(hwnd, dark ? "DarkMode_CFD" : "", dark ? "Edit" : "")
                    if (role = "code")
                        c.SetFont("c" txt, "Consolas")
                    else
                        c.SetFont("c" txt)
                case "Button":
                    SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                case "CheckBox", "Radio":
                    if dark
                        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "", "Str", "")   ; classic look so the text colour is honoured
                    else
                        SetTheme(hwnd, "")
                    c.SetFont("c" txt)
                case "DDL":
                    SetTheme(hwnd, dark ? "DarkMode_CFD" : "", dark ? "Combobox" : "")
                case "ListView":
                    c.Opt("Background" box " c" txt)
                    SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                    SetCheckImages(c)
            }
            c.Redraw()
        }
    }
}


; ============ window placement / list look ============
; show a window centred over `anchor` (default: the main window), on the same monitor
ShowOver(g, opts, anchor := 0) {
    try {
        if !anchor
            anchor := Main
        ah := IsObject(anchor) ? anchor.Hwnd : anchor
        if (!ah || !DllCall("IsWindowVisible", "Ptr", ah) || DllCall("IsIconic", "Ptr", ah)) {
            g.Show(opts)
            return
        }
        g.Show(opts " Hide")
        WinGetPos(&ax, &ay, &aw, &ah2, ah)
        WinGetPos(, , &gw, &gh, g.Hwnd)
        x := ax + (aw - gw) // 2
        y := ay + (ah2 - gh) // 2
        cx := ax + aw // 2
        cy := ay + ah2 // 2
        L := 0, T := 0, R := A_ScreenWidth, B := A_ScreenHeight
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
                L := ml, T := mt, R := mr, B := mb
                break
            }
        }
        x := Max(L, Min(x, R - gw))
        y := Max(T, Min(y, B - gh))
        g.Show("x" x " y" y)
    } catch
        g.Show(opts)
}

; MsgBox that opens over the visible app window (not on the primary monitor)
Mb(text, title := "", opts := "") {
    try {
        h := WinExist("A")
        if (!h || WinGetPID(h) != ProcessExist())
            h := Main.Hwnd
        if (h && DllCall("IsWindowVisible", "Ptr", h))
            opts .= " Owner" h
    }
    return MsgBox(text, title, opts)
}

; themed check boxes for the list (state image list: 1 = off, 2 = on)
SetCheckImages(c) {
    static gdip := 0
    try {
        if !gdip {
            si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", 1, si)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
            gdip := tok
        }
        file := DarkOn ? CbDarkFile : CbLightFile
        sz := Round(28 * A_ScreenDPI / 96)
        DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", file, "Ptr*", &src := 0)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", sz * 3, "Int", sz, "Int", 0, "Int", 0xE200B, "Ptr", 0, "Ptr*", &dst := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &gr := 0)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 2)
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", src, "Int", 0, "Int", 0, "Int", sz * 3, "Int", sz)
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm := 0, "UInt", 0)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
        il := DllCall("comctl32\ImageList_Create", "Int", sz, "Int", sz, "UInt", 0x20, "Int", 3, "Int", 0, "Ptr")
        DllCall("comctl32\ImageList_Add", "Ptr", il, "Ptr", hbm, "Ptr", 0)
        global CbIL, CbSz, CbDC
        if !CbDC
            CbDC := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        DllCall("SelectObject", "Ptr", CbDC, "Ptr", hbm, "Ptr")   ; kept for AlphaBlend (the image list can't blend it cleanly)
        oldBmp := 0
        CbIL := il, CbSz := sz
        old := SendMessage(0x1003, 2, il, c.Hwnd)          ; LVM_SETIMAGELIST, LVSIL_STATE
        if old
            DllCall("comctl32\ImageList_Destroy", "Ptr", old)
    }
}

; NM_CUSTOMDRAW of the list: every cell is painted here (own selection colours, check boxes, no focus rectangle)
OnLvDraw(ctrl, lp) {
    static ps := A_PtrSize
    stage := NumGet(lp, 24 - (ps = 8 ? 0 : 12), "UInt")
    if (stage = 1)
        return 0x30                                           ; CDRF_NOTIFYITEMDRAW | CDRF_NOTIFYPOSTPAINT
    if (stage = 2) {                                          ; post-paint: wipe whatever the theme drew below the last row
        hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
        cl := Buffer(16)
        DllCall("GetClientRect", "Ptr", ctrl.Hwnd, "Ptr", cl)
        n := SendMessage(0x1004, 0, 0, ctrl.Hwnd)             ; LVM_GETITEMCOUNT
        y0 := 0
        if n {
            ir := Buffer(16, 0)
            SendMessage(0x100E, n - 1, ir, ctrl.Hwnd)
            y0 := NumGet(ir, 12, "Int")
        }
        NumPut("Int", 0, "Int", y0, cl)
        br := DllCall("CreateSolidBrush", "UInt", DarkOn ? 0x27211F : 0xFFFFFF, "Ptr")
        DllCall("FillRect", "Ptr", hdc, "Ptr", cl, "Ptr", br)
        DllCall("DeleteObject", "Ptr", br)
        return 0
    }
    if (stage = 0x10001)
        return 0x20                                           ; CDRF_NOTIFYSUBITEMDRAW
    if (stage != 0x30001)
        return 0
    hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
    row := NumGet(lp, ps = 8 ? 56 : 36, "UPtr")               ; 0-based
    sub := NumGet(lp, ps = 8 ? 88 : 56, "Int")
    h := ctrl.Hwnd
    rc := Buffer(16, 0)
    SendMessage(0x100E, row, rc, h)                           ; LVM_GETITEMRECT (bounds of the row)
    top := NumGet(rc, 4, "Int"), bot := NumGet(rc, 12, "Int")
    cl := Buffer(16)
    DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
    cw := NumGet(cl, 8, "Int")
    x0 := 0
    loop sub
        x0 += SendMessage(0x101D, A_Index - 1, 0, h)          ; LVM_GETCOLUMNWIDTH
    w := SendMessage(0x101D, sub, 0, h)
    x1 := (sub = 3) ? Max(x0 + w, cw) : x0 + w
    st := SendMessage(0x102C, row, 0xF002, h)                 ; LVM_GETITEMSTATE
    sel := (st & 2) != 0
    if sel {
        bg := DarkOn ? 0x3A3626 : 0xF3E7C9
        fg := DarkOn ? 0xFFFFFF : 0x1B1B1F
    } else {
        bg := DarkOn ? 0x1F2127 : 0xFFFFFF
        fg := DarkOn ? 0xECECEF : 0x1B1B1F
    }
    bgr := ((bg & 0xFF) << 16) | (bg & 0xFF00) | (bg >> 16)
    fgr := ((fg & 0xFF) << 16) | (fg & 0xFF00) | (fg >> 16)
    r := Buffer(16)
    NumPut("Int", x0, "Int", top, "Int", x1, "Int", bot, r)
    br := DllCall("CreateSolidBrush", "UInt", bgr, "Ptr")
    DllCall("FillRect", "Ptr", hdc, "Ptr", r, "Ptr", br)
    DllCall("DeleteObject", "Ptr", br)
    tx := x0 + 8
    if (sub = 0) {
        if CbIL {
            idx := ((st >> 12) = 2) ? 2 : 1
            DllCall("msimg32\AlphaBlend", "Ptr", hdc, "Int", x0 + 2, "Int", top + (bot - top - CbSz) // 2, "Int", CbSz, "Int", CbSz
                , "Ptr", CbDC, "Int", idx * CbSz, "Int", 0, "Int", CbSz, "Int", CbSz, "UInt", 0x01FF0000)
        }
        tx := x0 + CbSz + 8
    }
    txt := ctrl.GetText(row + 1, sub + 1)
    font := SendMessage(0x31, 0, 0, h)
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    DllCall("SetTextColor", "Ptr", hdc, "UInt", fgr)
    NumPut("Int", tx, "Int", top, "Int", x1 - 6, "Int", bot, r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", txt, "Int", -1, "Ptr", r, "UInt", 0x8824)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    return 4                                                  ; CDRF_SKIPDEFAULT
}

LogoWideB64() {
    return "
(Join
iVBORw0KGgoAAAANSUhEUgAABqQAAACQCAYAAABu6wq5AABD0klEQVR4nO3dd7xdVZ3//9da+7Tb0ytppJICIYXeSygiLaGJbRTEcazjOLbvjGV0dNSxjONP
AcU6KkkoUhRCR2oKENIICUkICaTn1tP3Wr8/9jkn96beGxIg4f18PO7D4ey911p7Z/57Pz6fj+EgmjJhsD+Y64uIiIiIiIiIiIiIiMiBMX/RWnOw1j6gCyuA
EhEREREREREREREROTwcyIDqgCykIEpEREREREREREREROTwdCCCqTe1gIIoERERERERERERERGRd4c3E0zt14NdCaLmL1q7P1uIiIiIiIiIiIiIiIjIW2TK
hMGdvnd/gqkuP7CvMEoBlIiIiIiIiIiIiIiIyKFtXwFVV0OpLt28tzBKQZSIiIiIiIiIiIiIiMjhZW/BVFdCqU7dqCBKRERERERERERERETk3evNBlP7vGFP
YZSCKBERERERERERERERkXeXPQVT+wql7D4WVRglIiIiIiIiIiIiIiIiwJ4zor1124N9BFJd2UhEREREREREREREREQOf/uTFe0xkNpdkqUwSkRERERERERE
RERERHaXGe2tSmq3gZTCKBEREREREREREREREdmbroRSuwRSCqNERERERERERERERESkMzobSu1zhpTCKBEREREREREREREREdmTzmRJHQKpvfX2ExERERER
EREREREREemMnTOnvVZIqTpKRERERERERERERERE9mVfmVIlkFJ1lIiIiIiIiIiIiIiIiBwo7bOnPVZIqTpKREREREREREREREREOmtv2ZIFVUeJiIiIiIiI
iIiIiIjIgVfOoHZbIaXqKBEREREREREREREREemqPWVMe2zZJyIiIiIiIiIiIiIiInIgxN7uA7wZxhi894wb0YfLzx1HNlfEWlO57pwnGbOs3djM7/7y/Nty
xmQiRhg6iqF7y/Ysf5ee3ar58KWTSMQszjmwFhw4HIlYwObtrdxy+/Nv6dlEREREREREREREROTdJ3Y4zI/asj3NOcePYPCAbuTzRYzZEUphDN6FvLxmC88s
fA1rDc4d/Fcuh0Jf/MgpzF/yBn/9+/K3cG/wHq6bPoVPXXsCLW0FgnZBXehCGuqq+MkfnqIYurfsXCIiIiIiIiIiIiIi8u4zZcJgv0vLvkNpfpT3nsAaNm5t
5Sf/9xSFQpGmtgyt6Ryt6Tyt6TzNLVkcnk9cdRyxmMV7MPte+k2xtlS5NbwP77/4WD506USSiVi090HevBwujRjckxnTxrNlWxvpbL7yPVpaMxSKjiUrNnLj
rXOB6DuKiIiIiIiIiIiIiIgcCLvLmg75GVLOe4wx3PvYcl5csZG66hTeeKw1WGuIxSyZTMjxxwzivJNH4b3H2IObCpXznRuunEroPEeP7Md7Thsd7X2wE6nS
3tdNn0L3+hShg8DayvfAWKpTcf5wzws0tmQJrEF5lIiIiIiIiIiIiIiIHEyHfCBVrjrK5YvcNGsuMWsw3lBJZkr3FIvw0csnUVOVKD1zcIKhcnXUSccO4azj
h5NJ5wgdfPjyY6mvTR7UUMpag/OeSUf154LTRtKSzhEEO75F6DypZJylqzYze84SjInuFxEREREREREREREROZgO+UAKwLso5Hnw6Vd46vm1VFclCNvNRIoF
kM0XmDCiL5eefVQpFDpIZ/EQi1luuHIqQWDxxpArFDhqaB+uPH/8QW3b5z1YY7jhquNJxROEDqIGheVQyhOPG265fQFtmXxl1pSIiIiIiIiIiIiIiMjBdHgE
UkQhj3Oen8+ai/euQxWSx2CAbDHkAxdPpEdDFc4d+EqlcnXUBaeM4oSjB5HJFQhsgDWGTL7ItRcdS79edQdl76C092lThnLqpCG0ZfPEbPmf1xN6T3UqzvPL
Xuevjy2PqqOc0igRERERERERERERETn4DotACqIwyhrDMwtf46GnV1FXkyQMdwQu1hry+SLDj+jJtRdNBA5spVK52qg6Fef6GVMJi+W9o/CpUAg5om89H7p0
0gHfGwPOQyIWcP0VUzAmCqc63FKqCvvl7AXki+HBn2UlIiIiIiIiIiIiIiJSctgEUkDUmQ74+cy5ZLJ5bBC1qSvPULImIJ0rcPX5ExjUv6ESYh0IthQCzZg2
nrFH9iaTL2CNpdwyzxpLW6bA9HPGMWJwj2hve2D3vvD00UwdN5BMtkBgd/zThs5RU5Xkyede5aFnX8Eag3PugOwtIiIiIiIiIiIiIiKyL4dVIFUOeZas3Mi9
j79MXXWKsBK8GIyBYtHTt1ct118+5YDta0sVSj0bqvjwZZPI5AuYnT6tMeBCT/eGKj4247joxwPQMa9cmVVbneD6GVPJF/0uy1pryRdDbpw1r9Qu8M3vKyIi
IiIiIiIiIiIi0lmHVSAFVEKeG2fOZUtTG0HQMX2x1tCSzvHeM49i3Ig+OH8AKpVKFUofunQSQ/t3J1cIsbv5stYaWttyXHDaKCaNHXBA9rbG4r3nqgvGM2ZY
L3K5Yoc1i85Rk0rwwJMrmbtoHdYYQs2OEhERERERERERERGRt9BhF0iVQ54167cz677F1FYlOwQwBgidp6Y6wcevmvqm97PW4JxnUN8Grr7gGFrSOexePmvo
PYlYwMevPD4Kjt5ENmRM9L49u1XzgfdOoi2bx1hDJY7ynlhgaG7LcvNt80oP7f9+IiIiIiIiIiIiIiIi++OwC6QgamFnDPz2L8+z9o1GEvEAVwmlPDEb0JbO
cfbxIzn52ME45wneZKXSR2dMpme3aopFt9eqp5g1tGXznDZlCKdPHobz+793eXbUP1w6icH9ulHIu9JMLAN4Qu+prUrwl0deYtmqzZXwTERERERERERERERE
5K10mAZSHmsMW7a38fu7F1KVjNGxRqpUSWUMH7tiKoG1UYjVxX2siQKeMcN6c8mZY2lOZ7G769XXQRQieQfXz5hCPBbgSgFal/a2Ueu9wf0buPL88TSnsxiz
Y28PxGOWNza38Js7FnTxzURERERERERERERERA6cwzKQgihwMsYw6/7FvLR6C6lErF3rPo+1lnS2wAlHD+bsE4dH9+9npdINV02hriZBGPpdgiXvPR7X/hcC
a8nkikweP5DzTx2JL511f1w3fTI9u9UQFl2HuVXOeapTcf5832Je29Ck6igREREREREREREREXnbHLaBVLltX2s6xy9vm0csBsZ4wAEGg8GX2tpdN30SiXhQ
eaYzrDU47zl+whFMO2kkzW1ZYh0CLY/3niCwpTZ6vvQXtdTzeMKi56OXTqY6Fe/a3qXKrNHDenHxmWNpactigx0POweJhGXlq1v5070vUNleRERERERERERE
RETkbXDYBlIQVQkZY7jn0eU8+8J6qlNxQr8jmQmsJZstMHH0AC46fXSXKpW8j0KpG644jpiNwqz2Tf9CB6lUjB/+9gkefOYValIJQrejUiqwlky+yLiRfZl+
7rj9qpK6fsZUaquTFJzD0DEMS8bj/Pau59nWlMGYKDwTERERERERERERERF5OxzWgRREVUfF0HHTbfMIQ4/d6ZU9kC86PnL5JOpqEp2qVLI2mgN19gnDOWnS
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
)"
}

CbDarkB64() {
    return "
(Join
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
)"
}

CbLightB64() {
    return "
(Join
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
YII=
)"
}

SwOffB64() {
    return "
(Join
iVBORw0KGgoAAAANSUhEUgAAADgAAAAcCAIAAAC72etpAAAEpElEQVR42r2YO0/cShTH5+Vde7DZB49lg6BAilZoC6QFCkRDQQ0NXyDfBCFF+RJp+Q50BClK
GkAICIhHAQUrZMBe2LE9sedxi8ldodwbBMhkyh3r7E//mfM/5wwEf1gQwnK5XK1WXde1bZsQAgDQWoO8l5SSc84YC4Kg0+n86S/gb3Dmu+Hh4Xfv3nmehzFW
SgkhpJQAAIQQxhhCqJTKCxr+u7TWjLF2u+37/mOY30HNhuM479+/r1QqAADOeRzHGGPXdSml5hfGWJZljuMUi8UccbXWEEKEEEKo0+mcnZ0lSfKYFT6mrFQq
jUajWCymacoYq9frc3NzrVZrbGzMdV0IYRRF7XZ7b2/v+/fvl5eXlFJCiFIqx5ugtSaEZFl2cnIShmGPFT6mbDabEELOOcZ4ZWVleXm5Vqv9dvSEEEJIEAQb
Gxvr6+tRFFFKzW6OrAghCOGPHz96rNjsOY7TbDYxxlEUDQwMrK2tLS0tIYTiOM6yTEqplFJKSSnTNOWcW5Y1MzMzOzu7v7/v+75t2znmmSGDEFar1bu7uyzL
AADYXOTJyUnXdZMkGRgY+PTpU7PZDMPQSAj/sxBCWus4jmu12vz8/Pb29u3tbaFQyJ3Vsqy+vj7f9yGEGAAwNDQ0Pj6epimEcG1trdlsdjodQgiE8IlACCHO
eblcbrVam5ubaZoihHK8AMZbXNeNoiiKIgQhHB0dBQAwxlZWVqanpw3lc2IRQhhjExMTHz58iOM4X1DDKqUcHR2FEKJSqWQOvV6vLy8vR1GEMX5+LELIw8PD
4uJio9EwhpJ7OXBdt1QqoWq1SghJkmRubq5Wq5kL8NJYnuctLCz8/Pkzd1GNrtVqFXmep5TCGLdaLaXUKyRBCKVpOjU1RSnN11N7WeV5HrJtWwjhuu7Y2FiW
Za87uyzLRkZGKpWKECL309da27aNCCFSSkqp67qv08Okp4mQr/P3QDHG+V+pN1pICIExTpLk1f5iKp7pYN4omaSUiHNu7LDdbluW9brqQgjxfT8MQ0JI7j2r
aT9Qt9tFCAkh9vb2TPf50kBKqWKxeHh4+FIPfn771+12URAEUkrbtr99+xYEgWVZr7CnJEm2trbeQk7DGgQBur+/73a7lNLLy8uNjQ3P84QQz48ihPA87+vX
rwcHB2/hoxhjxtj9/T3SWl9dXQEAKKXr6+unp6fPZ5VSOo5zc3Pz+fPnfLunx8Z0dXWltcYQwjiO+/v7Pc9jjO3v78/Pz5fLZc750ykshHAcJ03T1dXV8/Pz
3OU0rX6n07m4uPjV5gEAHh4eBgcHHce5vr7e2dlptVr1ej1N056Bm3pjNDOVtlQqhWG4urq6u7vred5bNPlCiKOjo1+Ns4HIsiyKoqGhIdu2fd/f3Ny0bXti
YqJUKhldDSLGuFgs9vX1KaW+fPny8ePH8/PzN6KEEB4fH3e7XaPR/w93nPMkSRqNxsLCwtTU1MjIiOM4xs983z88PNza2jo4OCgUCoVC4e8Nd38al6Mo4pxT
Ss0zhJlCwzBkjFmWRSnVWv/tcfmJBwghhJnvelMoxlhrnZeQL36AeOJJx3Gcnpnn7kHPfNL5B+pyE2LAlyJyAAAAAElFTkSuQmCC
)"
}

SwOnB64() {
    return "
(Join
iVBORw0KGgoAAAANSUhEUgAAADgAAAAcCAIAAAC72etpAAAFkklEQVR42r1YW2wUVRg+/3/mzM7sLNvSlrbaUhaKxUIoSMELKEUFLzEQmvhATExMNDEaA14S
E6MvaozEoInG+GZCIg9KTEAhYkCNBZRrq7blVmIppTdaatnt7M7szDnn92EVKzGWNhP+l8lkLvn++/cdYP82BNBEjDGOsGrZnNXLUw11FVUVyUTcJGLRGhEB
QDYX9A9n2rsuHzzZ81PbRaVpIoxrBhNvOELhvY0P1j+5fml97SxhcClVqLTWFBE4pomAMc4BERkjxgABOAel6Gz3yGd7ft39/ZmJYK4HWngwt3rmO5vXrryj
xg+k54dEDIABQCQolSLT5HHLUIrcXJD1Q0bMtoyEbXIOfqAQIG6JI7/1vv7hdxf6xiZihYkoVzemtr36yMyknXZ9BECEqLKsiRAg6Zj9w25L66XjnYM9/enx
XEDEEnExuyK5fFFFU2NNqiqZcQMnbqbH/Vfe+/ZQa881rMAYQwSt6d5lcz59uzmUKh9IzjHCWlSaLJMrTTv2ntq5/+zASJYjCAM5AmOgtJZKS6XLiuMb1sx/
prnBinGpyLbE02/sOtx2sQAPCpc5VcVffrDJtkQ+VDy6QBZQxi1xZSz32kctR9sHZzjCFAYRETHGCmmFQnVJqTJuUD+vdOuLTXOrivKBCqV6/KXPL/ZfRQQO
AAjw8Rvra+eU5rwg2lhqIsvko1e9F9490N41UlZsM8a0pusGCBEjIgRIOObgFffHk5dWLamambTitlk/b9ZXhd4iYo+tXvDcphV/XPUMA6MdQIUufHnbD+1d
IyVFVij1JI5psmNibNw/3jn46H21pHVdqux87+i5C1dQGPyp5mVeXiKHaFEqRUnH3LH31NH2wRtBWTCpdNIxz/eOffJFWyJu5vzwqY3LhMHxrobqhbWzPF8i
QKTDnJkm7x92d+4/O8MxpdI3/m0odVEi9s3B7jMXRolY/bxZdzVUY9OKlDA4Rb12NFE8ZrS0XhoYycYETvX3nEMmlz9wpMcUyDk0rUjh4rpKqTSLOO0MGNNE
JzoHOcI0lhppZgreenrIy0utaXFdJc6uTIZSQdRIEWE8F/QMpIWBbBpAGQkD+y+7Y2mfMaquSGLCNrWmSOuTETHOMeuFGTfgCDR1pESMI2b9MJMNgIFji4jn
UeR2zUV0vQARou0lgMJENJy4UETTqKtrf0jYghjLeiFeGsoIg08jO5NtTj3DMWdXzgjldDoVGIRSVZY5JUUWMNY3lMGOriGDI4ucFGsmODYurFSKpsEdAFk+
1EsXlDu2AISO80PYcqInlAog+q738rKpsaas2Aqlhin7SXbMWHd3SiotFbWc6MFj7X2nfx+xLUNHWqcAzA9UbXXRhjW3pbPBlFiEwTHtBg/cWbNkQTkRO9s9
cqy9D0Optu9qs2OGVhGnHwHcXPh0c8PCuaVpN2/cGC/jCDk/rCiNb36i0c9L2xLbd7eFUiEi7DvUdbittyhpqals5BsJqlQ6ERdbX2wqL3HGc4GYLK4GRy8v
YybfuqWpotSxYuLnX3r3Hez6i49qTa2nBzasud2KiVDpCNkJAAShvqUscXfDrcc7B/suj1umwQvMHP7xBwGQI2OUHs+XFdvvv3L/8kWVfqC8fPjsm1+PZXwA
4EQMEa5m/DPdI81rFwKwUKoI1RIC+IGqKHEeXjXXz8vzvWNp19eaCoS9wEHzoXK9EAEeWpnauqVpfs1MP1C2JZ5/a09H1+W/pMhNEneahIFxS5zqHt1/5ELr
6aGBYTfnh0TMjhmVZc7SBeXr7kktqSv3A2mZIu3+l7i7OXK5oOjjMSMW4zlPjqa9jBsQo4RtlhRZji2k0kTMiomj/yOXb9oBhCYizZCD4MgR6G8QgCCVPtd9
ZfIDiJt8pFMQdACQ9YL+4UzHZEc6fwI4fCxGzy9JxQAAAABJRU5ErkJggg==
)"
}

; ============ key recorder (trigger key + "Record" buttons) ============
; "name" of a pressed key; falls back to a scan code when the name is ambiguous
KeyToken(vk, sc) {
    if !sc {                               ; keys injected by mouse / keyboard software often come without a scan code
        n := GetKeyName(Format("vk{:x}", vk))
        return n != "" ? n : Format("vk{:02x}", vk)
    }
    code := Format("sc{:03x}", sc)
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "" || (StrLen(name) = 1 && InStr(",+&|", name)))
        return code
    if (GetKeySC(name) != sc)
        return code
    return name
}

HasTok(arr, v) {
    for k in arr
        if (k = v)
            return true
    return false
}

RecStart(mode, cb) {
    global Recording
    RecStop()
    Rec.mode := mode
    Rec.cb := cb
    Rec.down := []
    Rec.chord := []
    Rec.toks := []
    Rec.mpend := []
    Recording := true
    Apply()                          ; macro hotkeys are off while recording
    HotIf()
    if (mode = "single") {
        for b in MouseToks
            try Hotkey("*" b, RecMouse.Bind(b), "On")
    }
    ih := InputHook("L1023")
    ih.KeyOpt("{All}", "NS")         ; notify + suppress: nothing is typed into the window
    ih.OnKeyDown := RecDown
    ih.OnKeyUp := RecUp
    Rec.ih := ih
    ih.Start()
}

RecStop() {
    global Recording
    if !Rec.ih
        return
    try Rec.ih.Stop()
    Rec.ih := 0
    for b in MouseToks
        try Hotkey("*" b, "Off")
    Recording := false
    Apply()
}

RecMouse(name, *) {
    if (Rec.ih && Rec.mode = "single") {
        cb := Rec.cb
        mods := HeldMods()
        RecStop()
        cb(ComboTok(mods, name))
    }
}

RecDown(ih, vk, sc) {
    if (!sc && !vk)
        return
    tok := KeyToken(vk, sc)
    if (Rec.mode = "single") {
        if IsModTok(tok) {                  ; modifier: wait - it's either the key itself or the start of a combination
            if !HasTok(Rec.mpend, tok)
                Rec.mpend.Push(tok)
            return
        }
        cb := Rec.cb
        mods := (tok = "Escape" || tok = "Backspace" || tok = "Delete") ? [] : HeldMods()
        RecStop()
        cb(ComboTok(mods, tok))
        return
    }
    if HasTok(Rec.down, tok)         ; auto-repeat
        return
    Rec.down.Push(tok)
    if !HasTok(Rec.chord, tok)
        Rec.chord.Push(tok)
    RecShow()
}

RecUp(ih, vk, sc) {
    if (!sc && !vk)
        return
    tok := KeyToken(vk, sc)
    if (Rec.mode = "single") {
        if (IsModTok(tok) && Rec.mpend.Length && HeldMods().Length = 0) {   ; only modifiers were pressed -> the first one is the key
            cb := Rec.cb
            first := NormMod(Rec.mpend[1])
            RecStop()
            cb(first)
        }
        return
    }
    if (Rec.mode != "list")
        return
    for i, k in Rec.down {
        if (k = tok) {
            Rec.down.RemoveAt(i)
            break
        }
    }
    if (Rec.down.Length = 0 && Rec.chord.Length) {
        Rec.toks.Push(JoinPlus(Rec.chord))     ; all keys of the chord are released -> one entry
        Rec.chord := []
    }
    RecShow()
}

RecShow() {
    s := ""
    for t in Rec.toks
        s .= (s = "" ? "" : ",") t
    if Rec.chord.Length
        s .= (s = "" ? "" : ",") JoinPlus(Rec.chord)
    cb := Rec.cb                     ; copy first: Rec.cb(s) would pass Rec as an extra first argument
    if cb
        cb(s)
}

; ends any running recording and restores the buttons
FinishRec() {
    if (Rec.ih && Rec.mode = "list" && Rec.chord.Length) {
        Rec.toks.Push(JoinPlus(Rec.chord))
        Rec.chord := []
        RecShow()
    }
    RecStop()
    if Rec.btn {
        try {
            Rec.btn.Text := "Record"
            Roles[Rec.btn.Hwnd] := "btn"
            PaintBtn(Rec.btn.Hwnd, false)
        }
        Rec.btn := 0
    }
    if Rec.undo {
        undo := Rec.undo
        Rec.undo := 0
        undo()
    }
}

StartListRec(edit, btn) {
    same := (Rec.btn == btn)
    FinishRec()
    if same
        return
    Rec.btn := btn
    btn.Text := "Done"
    Roles[btn.Hwnd] := "btnprimary"
    PaintBtn(btn.Hwnd, false)
    edit.Value := ""
    RecStart("list", (txt) => edit.Value := txt)
}

KeyLabel(prefix, v) => prefix (v = "" ? "none" : v)

; click-to-capture a key into st[field]; Esc cancels, Backspace/Delete clear (when allowClear)
CaptureKey(btn, st, field, allowClear, prefix := "", onDone := 0) {
    FinishRec()
    btn.Text := "Press a key or mouse button...   (Esc = cancel" (allowClear ? ", Backspace = none" : "") ")"
    Rec.undo := (*) => btn.Text := KeyLabel(prefix, st[field])
    RecStart("single", (tok) => KeyCaptured(btn, st, field, allowClear, prefix, onDone, tok))
}

KeyCaptured(btn, st, field, allowClear, prefix, onDone, tok) {
    Rec.undo := 0
    if (tok != "Escape") {
        if (allowClear && (tok = "Backspace" || tok = "Delete"))
            st[field] := ""
        else
            st[field] := tok
    }
    btn.Text := KeyLabel(prefix, st[field])
    if (onDone && tok != "Escape")
        onDone()
}

; ============ profiles ============
JoinProfs(arr) {
    out := ""
    for p in arr
        out .= (out = "" ? "" : "|") p
    return out
}

HasProf(list, name) {
    for p in StrSplit(list, "|")
        if (p = name)             ; case-insensitive
            return true
    return false
}

InProfile(m) => HasProf(m["profiles"], CurProfile)

IndexOf(m) {
    for i, x in Macros
        if (x == m)
            return i
    return 0
}

CleanName(t) => Trim(StrReplace(StrReplace(t, "|", ""), "&", ""))

ProfBtnText() => "Profile: " CurProfile "  ▾"

ProfLabel(v) {
    t := StrReplace(v, "|", ", ")
    return StrLen(t) > 24 ? StrSplit(v, "|").Length " profiles" : t
}

; themed drop-down under the banner button (replaces the native menu)
ProfileMenu(*) {
    global ProfPop
    if ProfPop {
        ClosePop()
        return
    }
    if (A_TickCount - ProfClosed < 300)         ; the click that just closed it
        return
    W := 220
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" Main.Hwnd)
    g.SetFont("s9", "Segoe UI")
    y := 1
    for pn in Profiles {
        cur := (pn = CurProfile)
        AddBtn(g, "x1 y" y " w" W " h32 Left", (cur ? "  ✓   " : "       ") pn, ProfPick.Bind(pn), cur ? "btnprimary" : "btn")
        y += 32
    }
    y += 1                                       ; 1px separator (the window colour shows through)
    AddBtn(g, "x1 y" y " w" W " h32 Left", "  +   New profile...", (*) => (ClosePop(), NewProfile()))
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       Rename current...", (*) => (ClosePop(), RenameProfile()))
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       Delete current", (*) => (ClosePop(), DeleteProfile()), "btndanger")
    y += 32
    ApplyTheme(g)
    g.BackColor := DarkOn ? "3A3E49" : "C9C9D2"   ; becomes the 1px frame
    pt := Buffer(8)
    bProf.GetPos(&bx, &by, , &bh)
    NumPut("Int", bx, "Int", by + bh + 2, pt)
    DllCall("ClientToScreen", "Ptr", Main.Hwnd, "Ptr", pt)
    g.OnEvent("Escape", ClosePop)
    ProfPop := g
    g.Show("x" NumGet(pt, 0, "Int") " y" NumGet(pt, 4, "Int") " w" (W + 2) " h" (y + 1))
    SetTimer(PopWatch, 100)
}

PopWatch() {
    if !ProfPop {
        SetTimer(PopWatch, 0)
        return
    }
    if !WinActive("ahk_id " ProfPop.Hwnd)
        ClosePop()
}

ClosePop(*) {
    global ProfPop, ProfClosed
    SetTimer(PopWatch, 0)
    if ProfPop {
        try ProfPop.Destroy()
        ProfPop := 0
    }
    ProfClosed := A_TickCount
}

ProfPick(pn, *) {
    ClosePop()
    SwitchProfile(pn)
}

SwitchProfile(p, *) {
    global CurProfile
    CurProfile := p
    bProf.Text := ProfBtnText()
    Save()
    Apply()
    Refresh()
}

NewProfile(*) {
    ib := InputBox("Name of the new profile:", "New profile", "w300 h130")
    if (ib.Result != "OK")
        return
    nm := CleanName(ib.Value)
    if (nm = "")
        return
    if HasProf(JoinProfs(Profiles), nm) {
        MsgBox "A profile with this name already exists.", "Macro Manager", 48
        return
    }
    Profiles.Push(nm)
    SwitchProfile(nm)
}

RenameProfile(*) {
    global CurProfile
    ib := InputBox("New name for profile `"" CurProfile "`":", "Rename profile", "w300 h130", CurProfile)
    if (ib.Result != "OK")
        return
    nm := CleanName(ib.Value)
    if (nm = "" || nm = CurProfile)
        return
    if HasProf(JoinProfs(Profiles), nm) {
        MsgBox "A profile with this name already exists.", "Macro Manager", 48
        return
    }
    for i, p in Profiles
        if (p = CurProfile)
            Profiles[i] := nm
    for m in Macros {
        arr := []
        for p in StrSplit(m["profiles"], "|")
            arr.Push(p = CurProfile ? nm : p)
        m["profiles"] := JoinProfs(arr)
    }
    CurProfile := nm
    bProf.Text := ProfBtnText()
    Save()
    Refresh()
}

DeleteProfile(*) {
    global CurProfile, Profiles
    if (Profiles.Length < 2) {
        MsgBox "You can't delete the last profile.", "Macro Manager", 48
        return
    }
    if (Mb("Delete profile `"" CurProfile "`"?`n`nMacros that belong only to this profile are moved to the first remaining profile.", "Macro Manager", "YesNo 32") != "Yes")
        return
    old := CurProfile
    rest := []
    for p in Profiles
        if (p != old)
            rest.Push(p)
    for m in Macros {
        arr := []
        for p in StrSplit(m["profiles"], "|")
            if (p != old && p != "")
                arr.Push(p)
        if !arr.Length
            arr.Push(rest[1])
        m["profiles"] := JoinProfs(arr)
    }
    Profiles := rest
    SwitchProfile(rest[1])
}

; flat toggle list of the profiles; returns "a|b" (at least one) or `cur` when cancelled
PickProfiles(owner, cur) {
    res := cur
    done := false
    sel := Map(), btns := Map()
    p := Gui("+Owner" owner.Hwnd " +ToolWindow", "Profiles of this macro")
    p.SetFont("s9", "Segoe UI")
    p.AddText("x14 y12 w300", "The macro is active in the selected profiles:")
    y := 40
    for pn in Profiles {
        sel[pn] := HasProf(cur, pn)
        btns[pn] := AddBtn(p, "x14 y" y " w292 h30 Left", ProfMark(pn, sel[pn]), Tog.Bind(pn), sel[pn] ? "btnprimary" : "btn")
        y += 36
    }
    Tog(pn, *) {
        sel[pn] := !sel[pn]
        b := btns[pn]
        b.Text := ProfMark(pn, sel[pn])
        Roles[b.Hwnd] := sel[pn] ? "btnprimary" : "btn"
        PaintBtn(b.Hwnd, true)
    }
    Ok(*) {
        arr := []
        for pn in Profiles
            if sel[pn]
                arr.Push(pn)
        if !arr.Length {
            MsgBox "Select at least one profile.", "Macro Manager", 48
            return
        }
        res := JoinProfs(arr)
        Close()
    }
    Close(*) {
        done := true
        owner.Opt("-Disabled")
        p.Destroy()
    }
    AddBtn(p, "x116 y" (y + 10) " w90 h32", "OK", Ok, "btnprimary")
    AddBtn(p, "x216 y" (y + 10) " w90 h32", "Cancel", Close)
    p.OnEvent("Close", Close)
    ApplyTheme(p)
    owner.Opt("+Disabled")
    ShowOver(p, "w320 h" (y + 58), owner)
    while !done
        Sleep 50
    return res
}

ProfMark(pn, on) => (on ? "  ✓   " : "       ") pn

; ============ application picker ============
; returns the chosen exe name (or `cur` when cancelled)
PickApp(owner, cur) {
    r := Mb("Use one of the currently running applications?`n`nYes = choose from a list`nNo = browse for the .exe file", "Select application", "YesNoCancel Icon?")
    if (r = "Cancel")
        return cur
    if (r = "No")
        return BrowseApp(cur)
    seen := Map(), items := []
    for hwnd in WinGetList() {
        try {
            if (!(WinGetStyle("ahk_id " hwnd) & 0x10000000))     ; WS_VISIBLE
                continue
            if (WinGetExStyle("ahk_id " hwnd) & 0x80)            ; tool window
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (title = "")
                continue
            if (WinGetPID("ahk_id " hwnd) = ProcessExist())      ; this app
                continue
            exe := WinGetProcessName("ahk_id " hwnd)
        } catch
            continue
        if (exe = "" || seen.Has(StrLower(exe)))
            continue
        seen[StrLower(exe)] := true
        items.Push([exe, title])
    }
    if !items.Length {
        MsgBox "No running applications found - choose the file instead.", "Select application", 64
        return BrowseApp(cur)
    }
    res := ""
    done := false
    p := Gui("+Owner" owner.Hwnd " +ToolWindow", "Running applications")
    p.SetFont("s9", "Segoe UI")
    p.AddText("x10 y10 w380", "Double-click an application:")
    lv := p.AddListView("x10 y32 w380 r11 -Hdr -E0x200 -Multi", ["Application"])
    for it in items
        lv.Add("", it[1] "   -   " (StrLen(it[2]) > 45 ? SubStr(it[2], 1, 45) "..." : it[2]))
    lv.ModifyCol(1, 355)
    Choose(*) {
        n := lv.GetNext()
        if !n
            return
        res := items[n][1]
        Close()
    }
    Close(*) {
        done := true
        owner.Opt("-Disabled")
        p.Destroy()
    }
    lv.OnEvent("DoubleClick", Choose)
    Browse(*) {
        res := BrowseApp("")
        if (res != "")
            Close()
    }
    AddBtn(p, "x10 y230 w95 h30", "Browse...", Browse)
    AddBtn(p, "x205 y230 w90 h30", "Select", Choose, "btnprimary")
    AddBtn(p, "x300 y230 w90 h30", "Cancel", Close)
    p.OnEvent("Close", Close)
    ApplyTheme(p)
    owner.Opt("+Disabled")
    ShowOver(p, "w400 h272", owner)
    while !done
        Sleep 50
    return res != "" ? res : cur
}

BrowseApp(cur) {
    f := FileSelect(1, , "Select the application", "Applications (*.exe)")
    if (f = "")
        return cur
    SplitPath f, &name
    return name
}

; ============ updates (GitHub) ============
ToggleAutoUpd(*) {
    global AutoUpd
    AutoUpd := !AutoUpd
    A_TrayMenu.ToggleCheck("Check for updates at start")
    Save()
}

HttpGet(url) {
    try {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(2000, 2000, 3000, 3000)
        r.Open("GET", url, false)
        r.SetRequestHeader("Cache-Control", "no-cache")
        r.SetRequestHeader("User-Agent", "MacroManager")
        r.Send()
        if (r.Status = 200)
            return r.ResponseText
    }
    return ""
}

; GET with extra headers; returns the text (200) or "" ; status / ETag are returned through the by-ref parameters
HttpReq(url, hdrs, &status, &etag) {
    status := 0, etag := ""
    try {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(2000, 2000, 3000, 3000)
        r.Open("GET", url, false)
        r.SetRequestHeader("User-Agent", "MacroManager")
        for k, v in hdrs
            r.SetRequestHeader(k, v)
        r.Send()
        status := r.Status
        try etag := r.GetResponseHeader("ETag")
        if (status = 200)
            return r.ResponseText
    }
    return ""
}

; download a repository file through the GitHub API (always fresh, not cached like raw.githubusercontent.com)
GhDownload(file, dest) {
    try {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(3000, 3000, 8000, 15000)
        r.Open("GET", "https://api.github.com/repos/" UpdRepo "/contents/" file "?ref=" UpdBranch, false)
        r.SetRequestHeader("User-Agent", "MacroManager")
        r.SetRequestHeader("Accept", "application/vnd.github.raw+json")
        r.Send()
        if (r.Status != 200)
            return false
        body := r.ResponseBody
        sa := ComObjValue(body)
        pData := NumGet(sa, 8 + A_PtrSize, "Ptr")
        size := NumGet(sa, 8 + 2 * A_PtrSize, "UInt")
        f := FileOpen(dest, "w")
        f.RawWrite(pData, size)
        f.Close()
        return size > 0
    }
    return false
}

; is version a newer than version b?  (1.10 > 1.9)
VerNewer(a, b) {
    pa := StrSplit(Trim(a), "."), pb := StrSplit(Trim(b), ".")
    loop Max(pa.Length, pb.Length) {
        x := A_Index <= pa.Length ? Integer("0" RegExReplace(pa[A_Index], "\D")) : 0
        y := A_Index <= pb.Length ? Integer("0" RegExReplace(pb[A_Index], "\D")) : 0
        if (x != y)
            return x > y
    }
    return false
}

Sha256(f) {
    hProv := 0, hHash := 0, res := ""
    try {
        data := FileRead(f, "RAW")
        DllCall("advapi32\CryptAcquireContextW", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 24, "UInt", 0xF0000000)     ; PROV_RSA_AES, VERIFYCONTEXT
        DllCall("advapi32\CryptCreateHash", "Ptr", hProv, "UInt", 0x800C, "Ptr", 0, "UInt", 0, "Ptr*", &hHash)         ; CALG_SHA_256
        DllCall("advapi32\CryptHashData", "Ptr", hHash, "Ptr", data, "UInt", data.Size, "UInt", 0)
        len := 32
        buf := Buffer(32)
        DllCall("advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 2, "Ptr", buf, "UInt*", &len, "UInt", 0)         ; HP_HASHVAL
        loop 32
            res .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    }
    if hHash
        DllCall("advapi32\CryptDestroyHash", "Ptr", hHash)
    if hProv
        DllCall("advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
    return res
}

; silent background check: keeps the banner arrow up to date while the app keeps running
AutoCheck(minAge := 120000) {
    static last := -10000000
    if (!AutoUpd || Rec.mode != "" || A_TickCount - last < minAge)
        return
    last := A_TickCount
    QueryUpdate()
}

; ask GitHub for the newest version; sets the banner icon.  returns "new", "latest" or "error"
QueryUpdate() {
    global UpdAvail, UpdInfo
    global UpdEtag, UpdBody
    hdr := Map("Accept", "application/vnd.github.raw+json")
    if (UpdEtag != "")
        hdr["If-None-Match"] := UpdEtag
    info := HttpReq("https://api.github.com/repos/" UpdRepo "/contents/version.json?ref=" UpdBranch, hdr, &st, &et)
    if (st = 304)
        info := UpdBody
    else if (st = 200 && info != "")
        UpdEtag := et, UpdBody := info
    else
        info := HttpGet(UpdateUrl "?t=" A_TickCount)      ; API unavailable or rate limited: use the (cached) raw file
    if (!RegExMatch(info, '"version"\s*:\s*"([^"]+)"', &mv)
        || !RegExMatch(info, '"url"\s*:\s*"([^"]+)"', &mu)
        || !RegExMatch(info, '"sha256"\s*:\s*"([0-9a-fA-F]{64})"', &ms))
        return "error"
    notes := RegExMatch(info, '"notes"\s*:\s*"((?:[^"\\]|\\.)*)"', &mn) ? StrReplace(mn[1], "\n", "`n") : ""
    UpdInfo := Map("ver", mv[1], "url", mu[1], "sha", StrLower(ms[1]), "notes", notes)
    UpdAvail := VerNewer(mv[1], AppVersion) && RegExMatch(mu[1], "^https://raw\.githubusercontent\.com/vavr0s/")
    SetUpdIcon()
    return UpdAvail ? "new" : "latest"
}

SetUpdIcon() {
    try {
        Roles[bUpd.Hwnd] := UpdAvail ? "btnupd1" : "btnupd0"
        PaintBtn(bUpd.Hwnd, false)
    }
}

; click on the banner icon / tray item: check, and when there is a new version ask whether to install it
OnUpdIcon(*) {
    static busy := false
    if (busy || Rec.mode != "")
        return
    busy := true
    try {
        if !UpdAvail {
            r := QueryUpdate()
            if (r = "error") {
                Mb("Could not check for updates. Check your internet connection and try again.", "Updates", "Iconx")
                return
            }
            if (r = "latest") {
                Mb("You have the latest version (v" AppVersion ").", "Updates", "Iconi")
                return
            }
        }
        msg := "Version " UpdInfo["ver"] " is available (you have v" AppVersion ")."
        if (UpdInfo["notes"] != "")
            msg .= "`n`n" UpdInfo["notes"]
        msg .= "`n`nUpdate now? The app restarts. Your macros, profiles and settings are not changed."
        if (Mb(msg, "Macro Manager update", "YesNo Iconi") = "Yes")
            InstallUpdate()
    } finally {
        busy := false
    }
}

InstallUpdate() {
    url := UpdInfo["url"], sha := UpdInfo["sha"]
    tmp := A_Temp "\MacroManager-update.ahk"
    try FileDelete tmp
    if !GhDownload("Macro%20Manager.ahk", tmp)
        try Download(url "?t=" A_TickCount, tmp)
    if !FileExist(tmp) {
        Mb("The download failed. Try again later.", "Updates", "Iconx")
        return
    }
    got := Sha256(tmp)
    if (got != sha) {
        sz := 0
        try sz := FileGetSize(tmp)
        try FileDelete tmp
        Mb("The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: " SubStr(sha, 1, 16) "...`nReceived: " (got = "" ? "(could not compute)" : SubStr(got, 1, 16) "...") "  (" sz " bytes)", "Updates", "Iconx")
        return
    }
    txt := ""
    try txt := FileRead(tmp, "UTF-8")
    if (!InStr(txt, "#Requires AutoHotkey v2") || !InStr(txt, "AppVersion")) {
        try FileDelete tmp
        Mb("The downloaded file is not a valid Macro Manager script. Nothing was changed.", "Updates", "Iconx")
        return
    }
    try {
        FileCopy(A_ScriptFullPath, A_ScriptFullPath ".bak", 1)     ; macros live in the config folder and are not touched
        FileCopy(tmp, A_ScriptFullPath, 1)
        FileDelete tmp
    } catch as e {
        Mb("Could not replace the app file: " e.Message, "Updates", "Iconx")
        return
    }
    Reload()
}

; ============ help window ============
HelpTopics() {
    t := Map()
    order := []
    order.Push("Release notes")
    t["Release notes"] := "Version " AppVersion "`n`n" ReleaseNotes
    order.Push("Getting started")
    t["Getting started"] := "Macro Manager runs hotkey macros for you. Each macro has a trigger key; while you hold it (inside the chosen application) the macro plays.`n`n- Tick a macro in the list to turn it on, untick to turn it off.`n- The switch All macros in the banner turns every macro on or off at once.`n- Dark mode switches the look of the app.`n- Double-click a row (or press Edit) to change a macro. Add creates a new one, Copy duplicates it, Delete removes it.`n- To select several macros drag the mouse over the rows (or Ctrl / Shift + click). Copy, Delete, Export, Move up / down and dragging out of the window work on all selected rows.`n- Closing the window keeps the app running in the tray. Right-click the tray icon for Open window / Uninstall / Exit.`n- The app always runs as administrator, so macros also work in games that run elevated."
    order.Push("Add / edit a macro")
    t["Add / edit a macro"] := "Name - any text, shown in the list.`nProfiles - which profiles the macro belongs to (can be several).`nTrigger key - click the box, then press the key or a mouse button (right, middle, side buttons X1 / X2, mouse wheel). Hold Ctrl / Shift / Alt while pressing to make a combination, for example Ctrl+XButton1. Esc cancels.`nToggle - optional key that turns this macro on/off without opening the window. Backspace clears it.`nOnly in app (exe) - the macro works only while that program is in front. Press Select to pick a running application or browse for the .exe. Empty = works everywhere.`nType - Move + actions, Sequence or Script (.ahk). See the next topics.`nRun - Once per key press: plays one pass and waits until you release the key. Repeat while key is held: plays again and again until you release the key (it stops immediately).`n`nSave stores the macro, Cancel throws changes away."
    order.Push("Move + actions")
    t["Move + actions"] := "Made for games where you keep moving (for example A and D) and cast spells in between.`n`nDirections - the movement keys, in order, for example: a,d`nActions in order - the keys to press, one per cycle, for example: 1,ě,1,F7,1,F8`n`nEvery cycle does this, with the delays you set:`n  1. direction down`n  2. (delay 1) action down`n  3. (delay 2) direction up`n  4. (delay 3) action up`n  5. (delay 4) pause, then the next direction + next action`n`nThe lists repeat from the start when they end. If Directions is empty, only the actions are pressed: hold time = delay 2, pause = delay 4.`nIf a game ignores the macro, raise the delays (20-30 ms is common)."
    order.Push("Sequence")
    t["Sequence"] := "A free list of steps. Write one step per line:`n`n  down KEY PAUSE   - press and hold the key`n  up KEY PAUSE     - release the key`n  tap KEY PAUSE    - press and release at once`n`nPAUSE is the wait after the step in milliseconds (empty = 0).`n`nExample - quick A / D change:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nExample - attack and spells:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nExample - two keys together:`n  tap Shift+4 50`n`nWith Run = Repeat the lines play in a loop while the trigger key is held; with Once they play one time.`nKeys that are still held when you release the trigger are released automatically."
    order.Push("Script (.ahk)")
    t["Script (.ahk)"] := "For anything the other types can not do. Paste or write your own AutoHotkey v2 script.`n`n- The script runs as its own process while the macro is ticked, and is stopped when you untick it.`n- It must be AutoHotkey v2 code (v1 scripts will not work).`n- Trigger key and application filter are not used, your script does that itself.`n- Imported .ahk files that were not made by Macro Manager become Script macros."
    order.Push("Keys and recording")
    t["Keys and recording"] := "Key names are the AutoHotkey names: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nA key can also be written as a scan code, for example sc002 - this is the physical key, regardless of layout. Keys like comma, plus, & and | are saved this way automatically.`n`nMouse: the trigger, toggle and All macros keys can also be a mouse button: RButton, MButton (wheel click), XButton1 / XButton2 (the two side buttons), or the wheel itself (WheelUp / WheelDown / WheelLeft / WheelRight). A wheel has no hold, so wheel macros always play once. The left button is not offered.`nGaming / MMO mice: windows only knows five mouse buttons, the extra side buttons are handled by the mouse software (G HUB, Synapse, iCUE, ...). Set them there to keys, best F13 - F24 (or Ctrl+Alt+number); Macro Manager then sees them as ordinary keys, so click the trigger box and press the side button.`n`nRecord (next to Directions and Actions): press Record, press the keys in the order you want, then press Done. The field fills in live. Macros are paused while recording.`n`nKeys at the same time: keys that you hold together are saved as one step joined with +, for example Shift+4. When the macro plays, all of them go down together and are released together (not Shift first and 4 afterwards).`nThe same works by typing it in the fields: a,Shift+4,d"
    order.Push("Profiles")
    t["Profiles"] := "Profiles keep different sets of macros apart (for example one per game).`n`n- The profile button in the banner shows the current profile. Click it to switch, or to create / rename / delete a profile.`n- The list shows only the macros of the current profile, and only those are active.`n- In the editor, Profiles lets you choose one or more profiles for the macro. When you change a macro that belongs to several profiles, the app asks: apply the change to all of them, or only to the current profile (the other profiles keep the old version).`n- Tick state of a macro stays the same in every profile; switching profile just changes which macros are in play.`n- Deleting a profile moves macros that belonged only to it to the first remaining profile."
    order.Push("Toggle keys")
    t["Toggle keys"] := "Toggle (in the editor) - a key that switches that single macro on / off, same as ticking it in the list. A small tooltip shows ON / OFF.`nAll macros toggle key (button under the list) - switches the master switch. Works in every profile.`n`nClick the button, press the key. Esc cancels, Backspace removes the key.`nMacros of other profiles do not react to their toggle keys."
    order.Push("Order, export, backup")
    t["Order, export, backup"] := "Move up / Move down change the order in the list. Clicking a column header sorts the list (click again to reverse).`n`nExport... saves the selected macro as a standalone AutoHotkey v2 .ahk file that also runs by itself (it asks for admin rights).`nImport... loads one or more .ahk files (or just drag them onto the main window). You can also drag a macro from the list onto the desktop / a folder / a chat window to export it as an .ahk file. The macro is named after the file; files made by Macro Manager come back as editable macros, other scripts become Script macros. Imports go to the current profile and start switched off.`nExport all... writes every macro to a folder, one file each.`n`nUninstall deletes the whole app folder including all macros and settings. It offers to export all macros first."
    order.Push("Updates")
    t["Updates"] := "The arrow icon in the banner (next to the profile button) shows whether a new version exists: grey = you are up to date, green = a new version is available. Hover it for details.`n`nThe app checks a few seconds after it starts (can be turned off in the tray menu: Check for updates at start). Click the icon at any time to check again. Nothing is installed until you click the green icon and confirm.`n`nWhen you update, the app downloads the new file, checks its checksum, keeps the old one as Macro Manager.ahk.bak and restarts. Your macros, profiles and settings are stored separately in the config folder and stay exactly as they are.`n`nIf something goes wrong, close the app, delete Macro Manager.ahk and rename Macro Manager.ahk.bak back to Macro Manager.ahk.`n`nThe update needs internet access to github.com."
    order.Push("Support")
    t["Support"] := "If you need support, add me on Discord - vavr0s"
    order.Push("Tips and problems")
    t["Tips and problems"] := "- The game does nothing: try raising the delays, make sure Only in app matches the game (use Select), and keep the app as administrator.`n- Character runs in one direction: keep direction pairs in Directions (a,d) and the delay between cycles small but not 0.`n- A macro does not start: check that it is ticked, All macros is on, it is in the current profile and the trigger key is set (not undefined).`n- Two macros with the same trigger key: only one of them works - use different keys or different profiles.`n- Stuck key after an abort: press and release it once; the app releases keys it pressed when the macro stops.`n- Settings and scripts live in the config folder next to the app."
    return [order, t]
}

OpenHelp(*) {
    global HelpGui
    if (IsSet(HelpGui) && HelpGui) {
        try {
            HelpGui.Show()
            return
        }
    }
    ht := HelpTopics()
    order := ht[1], texts := ht[2]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", "Help")
    HelpGui := g
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", "Help")
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }
    nav := Map()
    y := 94
    for nm in order {
        nav[nm] := AddBtn(g, "x10 y" y " w158 h30 Left", "  " nm, HelpShow.Bind(nm), "btn")
        y += 34
    }
    unseen := (SeenVer != AppVersion)
    HelpBadge := 0
    if unseen {
        HelpBadge := g.AddPicture("x172 y101 w16 h16", DarkOn ? BadgeDkFile : BadgeLtFile)
        Roles[HelpBadge.Hwnd] := "skip"
    }
    g.SetFont("s10", "Segoe UI")
    ed := g.AddEdit("x190 y94 w460 h" (y - 94 + 4) " Multi ReadOnly", "")
    g.SetFont("s9", "Segoe UI")
    HelpShow(nm, *) {
        global SeenVer
        for k, b in nav {
            Roles[b.Hwnd] := (k = nm) ? "btnprimary" : "btn"
            PaintBtn(b.Hwnd, false)
        }
        ed.Value := StrReplace(texts[nm], "`n", "`r`n")
        if (nm = "Release notes" && SeenVer != AppVersion) {        ; read: both ! disappear
            SeenVer := AppVersion
            Save()
            try HelpBadge.Visible := false
            try bBadge.Visible := false
        }
    }
    HelpClose(*) {
        global HelpGui
        HelpGui := 0
        g.Destroy()
    }
    AddBtn(g, "x560 y" (y + 14) " w90 h32", "Close", HelpClose)
    g.OnEvent("Close", HelpClose)
    g.OnEvent("Escape", HelpClose)
    ApplyTheme(g)
    ShowOver(g, "w660 h" (y + 62), Main)
    HelpShow("Getting started")
}

; ============ list: drag over rows = select, drag out of the list = export ============

OnLvLDown(wParam, lParam, msg, hwnd) {
    if (hwnd != LV.Hwnd)
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    hit := LvHit(x, y)
    if (hit[1] >= 1 && x < Round(34 * A_ScreenDPI / 96)) {              ; on the check box: toggle it ourselves (every click, also fast ones)
        st := SendMessage(0x102C, hit[1] - 1, 0xF000, LV)       ; LVM_GETITEMSTATE
        on := (st >> 12) != 2
        LV.Modify(hit[1], on ? "Check" : "-Check")
        if (hit[1] <= View.Length && View[hit[1]]["enabled"] != (on ? 1 : 0))   ; Modify does not raise ItemCheck: apply it here
            OnCheck(LV, hit[1], on)
        return 0                                         ; swallow: no native toggle, no double-click -> no editor
    }
    if (msg = 0x203 || hit[1] < 1)                    ; double click elsewhere / empty space: default handling
        return
    DragStart["row"] := hit[1]
    pt := Buffer(8)
    DllCall("GetCursorPos", "Ptr", pt)
    DragStart["x"] := NumGet(pt, 0, "Int"), DragStart["y"] := NumGet(pt, 4, "Int")
    DragStart["last"] := ""
    SetTimer(DragTick, 15)
}

; [row (1-based, 0 = none), hit flags] for a point in list client coordinates
LvHit(x, y) {
    hti := Buffer(24, 0)
    NumPut("Int", x, "Int", y, hti)
    SendMessage(0x1039, 0, hti, LV)                    ; LVM_SUBITEMHITTEST (finds the row over any column)
    return [NumGet(hti, 12, "Int") + 1, NumGet(hti, 8, "UInt")]
}

DragTick() {
    global DragOut, DragEnd
    if !GetKeyState("LButton", "P") {
        SetTimer(DragTick, 0)
        return
    }
    pt := Buffer(8)
    DllCall("GetCursorPos", "Ptr", pt)
    mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
    if (Abs(mx - DragStart["x"]) < 5 && Abs(my - DragStart["y"]) < 5)
        return
    rc := Buffer(16)
    DllCall("GetClientRect", "Ptr", LV.Hwnd, "Ptr", rc)
    cp := Buffer(8)
    NumPut("Int", mx, "Int", my, cp)
    DllCall("ScreenToClient", "Ptr", LV.Hwnd, "Ptr", cp)
    cx := NumGet(cp, 0, "Int"), cy := NumGet(cp, 4, "Int")
    inside := (cx >= 0 && cy >= 0 && cx < NumGet(rc, 8, "Int") && cy < NumGet(rc, 12, "Int"))
    if inside {
        cur := LvHit(Max(cx, 1), cy)[1]
        if (cur < 1)                                     ; below the last row / above the first one
            cur := (cy > 0 && View.Length) ? View.Length : 1
        lo := Min(DragStart["row"], cur), hi := Max(DragStart["row"], cur)
        key := lo "-" hi
        if (key != DragStart["last"]) {
            DragStart["last"] := key
            LV.Modify(0, "-Select")
            loop hi - lo + 1
                LV.Modify(lo + A_Index - 1, "Select")
        }
        return
    }
    ; the pointer left the list: export the selected macros as files
    SetTimer(DragTick, 0)
    sel := SelMacros()
    if (!sel.Length && DragStart["row"] >= 1 && DragStart["row"] <= View.Length)
        sel := [View[DragStart["row"]]]
    paths := []
    dir := A_Temp "\MacroManager-drag"
    DirCreate(dir)
    for m in sel {
        if (m["type"] != "script") {
            k := Trim(m["hotkey"])
            if (k = "" || k = "undefined") {
                Toast("Set a trigger key first: " m["name"])
                continue
            }
        }
        code := ExportCode(m)
        if (code = "")
            continue
        path := dir "\" RegExReplace(m["name"], '[\\/:*?"<>|]', "_") ".ahk"
        WriteText(path, code)
        paths.Push(path)
    }
    if !paths.Length
        return
    DragOut := true
    DllCall("ReleaseCapture")
    try {
        DragFile(paths)
    } catch as e {
        DragOut := false
        MsgBox "Dragging the macro out failed:`n" e.Message, "Macro Manager", 48
    }
    DragOut := false
    DragEnd := A_TickCount
}

; starts a normal Explorer-style file drag (CF_HDROP) of files that live in one folder
DragFile(paths) {
    pidls := [], kids := Buffer(A_PtrSize * paths.Length, 0)
    parent := 0
    for i, path in paths {
        pidl := 0
        if DllCall("shell32\SHParseDisplayName", "WStr", path, "Ptr", 0, "Ptr*", &pidl, "UInt", 0, "Ptr", 0)
            continue
        pidls.Push(pidl)
        if !parent {
            parent := DllCall("shell32\ILClone", "Ptr", pidl, "Ptr")
            DllCall("shell32\ILRemoveLastID", "Ptr", parent)
        }
        NumPut("Ptr", DllCall("shell32\ILFindLastID", "Ptr", pidl, "Ptr"), kids, (pidls.Length - 1) * A_PtrSize)
    }
    if (!pidls.Length || !parent)
        throw Error("could not resolve the exported file")
    iid := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{0000010e-0000-0000-C000-000000000046}", "Ptr", iid)   ; IDataObject
    pdo := 0
    hr := DllCall("shell32\SHCreateDataObject", "Ptr", parent, "UInt", pidls.Length, "Ptr", kids, "Ptr", 0, "Ptr", iid, "Ptr*", &pdo, "Int")
    if (hr != 0 || !pdo)
        throw Error("SHCreateDataObject failed (0x" Format("{:X}", hr & 0xFFFFFFFF) ")")
    eff := 0
    ; the shell's own drop source (NULL) handles the mouse button / Esc / cursors
    hr := DllCall("shell32\SHDoDragDrop", "Ptr", Main.Hwnd, "Ptr", pdo, "Ptr", 0, "UInt", 1, "UInt*", &eff, "Int")
    ObjRelease(pdo)
    DllCall("shell32\ILFree", "Ptr", parent)
    for pidl in pidls
        DllCall("ole32\CoTaskMemFree", "Ptr", pidl)
    if (hr < 0 && hr != 0x80270001 - 0x100000000)
        throw Error("SHDoDragDrop failed (0x" Format("{:X}", hr & 0xFFFFFFFF) ")")
}

BadgeMainB64() {
    return "
(Join
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
YII=
)"
}

BadgeDkB64() {
    return "
(Join
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
)"
}

BadgeLtB64() {
    return "
(Join
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
mvrv8/r9/wNv5WChYRKmeQAAAABJRU5ErkJggg==
)"
}
