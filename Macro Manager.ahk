; Macro Manager - built from src/*.ahk by tools/build.py (edit those files, not this one)
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
#HotIfTimeout 150      ; the keyboard hook waits at most this long for "only in app" checks (default 1000 ms stalls all keys)

; ============ language ============
; English text is the key: _T("English text") returns the translation when one exists, else the English text itself.
; {1}, {2} ... are placeholders filled from the extra arguments. _TL(id, English) is used for long help texts.
Lang := "en"                                   ; en (default) | cs | pl | de, chosen by the user (macros.ini, [main] language)
LangTable := Map()
LangNames := Map("en", "English", "cs", "Čeština", "pl", "Polski", "de", "Deutsch")
LangOrder := ["en", "cs", "pl", "de"]

InitLang(iniPath) {
    global Lang, LangTable
    l := "en"
    try l := IniRead(iniPath, "main", "language", "en")
    if !LangNames.Has(l)
        l := "en"
    Lang := l
    LangTable := (l = "cs") ? TrCs() : (l = "pl") ? TrPl() : (l = "de") ? TrDe() : Map()
}

_T(s, args*) {
    if (Lang != "en" && LangTable.Has(s))
        s := LangTable[s]
    for i, a in args
        s := StrReplace(s, "{" i "}", a)
    return s
}

_TL(id, s) => (Lang != "en" && LangTable.Has(id)) ? LangTable[id] : s

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

Roles := Map()         ; control hwnd -> role (hint / skip / code) used by the theme (also by the setup dialogs)
DarkOn := false

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
CbBmp := 0             ; check box bitmap selected into CbDC
CbSz := 28
CbDarkFile := AssetsDir "\cb_dark.png"
CbLightFile := AssetsDir "\cb_light.png"
BadgeMainFile := AssetsDir "\badge_main.png"     ; yellow ! with glow (banner / dark window / light window)
BadgeDkFile := AssetsDir "\badge_dk.png"
BadgeLtFile := AssetsDir "\badge_lt.png"
DiscordFile := AssetsDir "\discord.png"
DiscordHovFile := AssetsDir "\discord_hov.png"           ; Discord symbol (help banner)
DiscordId := "271697935627059202"
SwOffFile := AssetsDir "\switch_off.png"
SwOnFile := AssetsDir "\switch_on.png"
AssetVersion := "b10"    ; bump when the embedded logo/icon change
AppVersion := "1.18.1"     ; bump on every release (must match version.json in the GitHub repo)
UpdAvail := false       ; a newer version exists (icon in the banner turns green)
UpdInfo := Map()
UpdRepo := "vavr0s/macro-manager"
UpdBranch := "beta"      ; the test (beta) build uses "beta"
UpdateUrl := "https://raw.githubusercontent.com/" UpdRepo "/" UpdBranch "/version.json"      ; fallback (cached by GitHub for ~5 min)
UpdEtag := ""            ; GitHub API answers "not modified" for free when nothing changed
UpdBody := ""
; release notes of THIS version (shown in Help; also used as the text of the update prompt). No double quotes here.
ReleaseNotes := "BETA build - for testing.`n- Minor fixes"
SeenVer := AppVersion   ; last version whose release notes the user has opened (! shown while different)
AutoUpd := true         ; check for updates when the app starts
Macros := []
MasterOn := true
Registered := []
Populating := false
HoverHwnd := 0
BtnAlias := Map()       ; picture hwnd -> button hwnd (a flag lying on a button hovers the button)
Recording := false
DragOut := false
DragEnd := 0
DragStart := Map("row", 0, "x", 0, "y", 0, "last", "", "lock", false)
MasterKey := ""        ; optional hotkey that toggles "All macros"
HeldKeys := Map()      ; keys a macro holds down right now
MacroBusy := 0         ; number of macros playing right now (background update checks wait)
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
Procs := Map()          ; macro -> PID of running imported script
EnsureAssets()          ; logo + icon are embedded in this file

; started from Windows "Apps & features" (or manually) with /uninstall
if (!FileExist(IniFile) && FileExist(IniFile ".bak"))
    try FileCopy(IniFile ".bak", IniFile)           ; saving was interrupted: take the last good copy
InitLang(IniFile)
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
    Main.SetFont("s10 bold cD0AE6B", "Segoe UI")
    btl := Main.AddText("x102 y56 w200 BackgroundTrans", "(beta)")
    Roles[btl.Hwnd] := "skip"
    Main.SetFont("s9 norm cC9B27C", "Segoe UI")
    lbl := Main.AddText("x600 y50 w105 Right BackgroundTrans", _T("Dark mode"))
    Roles[lbl.Hwnd] := "skip"
    swPic := Main.AddPicture("x712 y44", DarkOn ? SwOnFile : SwOffFile)
    swPic.OnEvent("Click", OnDarkToggle)
    swPic.OnEvent("DoubleClick", OnDarkToggle)
    lbl2 := Main.AddText("x600 y18 w105 Right BackgroundTrans", _T("All macros"))
    Roles[lbl2.Hwnd] := "skip"
    swMaster := Main.AddPicture("x712 y12", MasterOn ? SwOnFile : SwOffFile)
    swMaster.OnEvent("Click", OnMaster)
    swMaster.OnEvent("DoubleClick", OnMaster)
    bProf := AddBtn(Main, "x330 y27 w150 h28", ProfBtnText(), ProfileMenu, "btnbanner")
    bLang := AddBtn(Main, "x490 y27 w108 h28 Left", "            " LangNames[Lang] "  ▾", LangMenu, "btnbanner")
    flB := Main.AddPicture("x498 y33 w24 h16", FlagFile(Lang))              ; flag of the current language
    flB.OnEvent("Click", LangMenu)
    Roles[flB.Hwnd] := "skip"
    BtnAlias[flB.Hwnd] := bLang.Hwnd
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
; search box above the list: shows only the macros whose name, key or application contains the text
eSearch := Main.AddEdit("x10 y92 w300 h26")
eSearch.OnEvent("Change", (*) => Refresh())
SendMessage(0x1501, 1, StrPtr(_T("Search (name, key or application)")), eSearch)     ; EM_SETCUEBANNER: grey hint text
bClear := AddBtn(Main, "x314 y92 w28 h26", Chr(0xD7), (*) => ClearSearch(), "btn")
hdrNames := [_T("Name"), _T("Key"), _T("Application"), _T("Type")]
hdrW := [300, 130, 240, 150]
hdrCtl := []
hx := 10
for i, nm in hdrNames {
    h := Main.AddText("x" hx " y126 w" hdrW[i] " h28 +0x200", "  " nm)
    Roles[h.Hwnd] := "hdr"
    h.OnEvent("Click", SortBy.Bind(i))
    hdrCtl.Push(h)
    hx += hdrW[i]
}
LV := Main.AddListView("x10 y154 w820 r13 -Hdr -E0x200 Checked Multi", [_T("Name"), _T("Key"), _T("Application"), _T("Type")])
LV.SetFont("s10")
LV.Opt("+LV0x10020")                          ; LVS_EX_DOUBLEBUFFER (no flicker on repaint) + full-row select                             ; full-row select: the whole row can be picked / dragged, not only the Name cell
LV.ModifyCol(1, 300)
LV.ModifyCol(2, 130)
LV.ModifyCol(3, 240)
LV.ModifyCol(4, 130)
LV.OnNotify(-12, OnLvDraw)                   ; custom draw: themed selection, no dotted focus rectangle
SendMessage(0x127, 0x10001, 0, LV.Hwnd)      ; WM_CHANGEUISTATE: hide focus rectangles
bAdd := AddBtn(Main, "x10 y+14 w130 h36", _T("Add"), (*) => EditMacro(0), "btnprimary")
bCopy := AddBtn(Main, "x+8 yp w130 h36", _T("Copy"), OnCopyBtn)
bEdit := AddBtn(Main, "x+8 yp w130 h36", _T("Edit"), OnEditBtn)
bDel := AddBtn(Main, "x+8 yp w130 h36", _T("Delete"), OnDelBtn, "btndanger")
bExport := AddBtn(Main, "x+8 yp w130 h36", _T("Export..."), OnExportBtn)
bImport := AddBtn(Main, "x+8 yp w130 h36", _T("Import..."), OnImportBtn)
bUp := AddBtn(Main, "x10 y+8 w130 h36", _T("Move up"), (*) => MoveRow(-1))
bDown := AddBtn(Main, "x+8 yp w130 h36", _T("Move down"), (*) => MoveRow(1))
bExpAll := AddBtn(Main, "x+8 yp w150 h36", _T("Export all..."), OnExportAll)
MKst := Map("key", MasterKey)
bMKey := AddBtn(Main, "x+8 yp w386 h36", KeyLabel(_T("All macros toggle key:") "  ", MKst["key"]), (*) => CaptureKey(bMKey, MKst, "key", true, _T("All macros toggle key:") "  ", OnMasterKey))
AddHint(Main, "x10 y+16 w620", _T("Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."))
bBackup := AddBtn(Main, "x645 yp w90 h28", _T("Backup..."), OnBackupBtn, "btnghost")
bUninst := AddBtn(Main, "x740 yp w90 h28", _T("Uninstall"), (*) => UninstallApp(), "btnghost")
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
A_TrayMenu.Add(_T("Open window"), (*) => (Main.Show(), AutoCheck(120000)))
A_TrayMenu.Add(_T("Check for updates..."), OnUpdIcon)
A_TrayMenu.Add(_T("Check for updates at start"), ToggleAutoUpd)
if AutoUpd
    A_TrayMenu.Check(_T("Check for updates at start"))
A_TrayMenu.Add(_T("Uninstall..."), (*) => UninstallApp())
A_TrayMenu.Add(_T("Exit"), (*) => ExitApp())
A_TrayMenu.Default := _T("Open window")
OnExit(ExitHandler)

Refresh()
Apply()
ApplyTheme(Main)
SetTimer(HoverTick, 40)
SetTimer(ModWatch, 250)              ; un-sticks Ctrl / Alt / Shift / Win that Windows still thinks are held
try Hotkey("~*RAlt up", AltGrUp)     ; AltGr released: make sure its Ctrl is released too
Main.Show()
SetTimer(() => AutoCheck(), -4000)
SetTimer(AutoCheck, 60000)         ; background check (at most every 2 minutes, see AutoCheck)
return

; ============ window handlers ============
OnMainClose(*) {
    Main.Hide()
    return 1
}

ExitHandler(*) {
    ReleaseHeld()                                  ; keys a macro was holding when the app was closed
    for k in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]     ; and modifiers Windows still thinks are down
        if (GetKeyState(k) && !GetKeyState(k, "P"))
            try Send "{Blind}{" k " up}"
    for m, pid in Procs
        try ProcessClose(pid)
    try DirDelete(A_Temp "\MacroManager-drag", 1)
}

OnCheck(ctrl, item, checked) {
    if Populating
        return
    m := View[item]
    if (checked && (NeedsTrust(m) || KeyClash(m))) {   ; imported script / same key as an active macro: ask first
        LV.Modify(item, "-Check")                       ; (after this handler has returned)
        SetTimer(EnableMacro.Bind(m, false), -10)
        return
    }
    m["enabled"] := checked ? 1 : 0
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
    msg := list.Length = 1 ? _T("Delete macro `"{1}`"?", list[1]["name"]) : _T("Delete {1} selected macros?", list.Length)
    if (ThemedAsk("Macro Manager", "", msg, [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
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
    Toast(_T("All macros: {1}", MasterOn ? _T("ON") : _T("OFF")))
}

ToggleMacro(m, *) {
    if !m["enabled"] {
        EnableMacro(m, true)
        return
    }
    m["enabled"] := m["enabled"] ? 0 : 1
    Save()
    Apply()
    Refresh()
    Toast(m["name"] ": " (m["enabled"] ? _T("ON") : _T("OFF")))
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

TypeLabel(t) => t = "move" ? _T("Move + actions") : (t = "seq" ? _T("Sequence") : _T("Script (.ahk)"))

ClearSearch() {
    eSearch.Value := ""
    Refresh()
}

Refresh() {
    global Populating
    Populating := true
    LV.Delete()
    global View
    View := []
    q := Trim(eSearch.Value)                      ; search box: name, key or application contains the text
    for m in Macros
        if (InProfile(m) && (q = "" || InStr(m["name"], q) || InStr(m["hotkey"], q) || InStr(m["app"], q)))
            View.Push(m)
    for m in View
        LV.Add(m["enabled"] ? "Check" : "", m["name"], m["hotkey"], (m["app"] = "" || m["type"] = "script") ? _T("(everywhere)") : m["app"], TypeLabel(m["type"]))
    LV.ModifyCol(4, "AutoHdr")                    ; last column fills the rest, so nothing stale is left on the right
    Populating := false
}

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
    for f in files {
        if RegExMatch(f, "i)\.mmbackup$") {          ; a backup file: offer to restore it
            Main.Show()
            RestoreBackup(f)
            return
        }
        if RegExMatch(f, "i)\.ahk$")
            list.Push(f)
    }
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
    if (eSearch.Value != "")
        eSearch.Value := ""                       ; the new macros must be visible
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

; ============ installer ============
; Installs "Macro Manager.ahk" + "Macro Manager.exe" (a copy of the AutoHotkey interpreter with our icon and name,
; so Explorer, the taskbar and Task Manager show Macro Manager instead of AutoHotkey).
Bootstrap() {
    reg := "HKCU\Software\MacroManagerBeta"
    prev := RegRead(reg, "InstallDir", "")
    if (prev != "")
        InitLang(prev "\config\macros.ini")             ; an existing install keeps its language
    if (prev != "" && FileExist(prev "\config\.installed") && FindInstalled(prev) != "") {
        r := ThemedAsk(_T("Macro Manager setup"), _T("Macro Manager is already installed"), _T("Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?", prev)
            , [[_T("Just start"), "start", "btn"], [_T("Update and start"), "update", "btnprimary"]], false)
        if (r = "")
            return
        if (r = "update") {
            try {
                InstallProgram(prev)
            } catch as e {
                ThemedNote(_T("Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}", e.Message), _T("Macro Manager setup"), true)
            }
        }
        LaunchInstalled(prev)
        return
    }

    dir := DirSelect("*" A_ProgramFiles, 1, _T("Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there."))
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
        ThemedNote(_T("Installation failed:`n{1}", e.Message), _T("Macro Manager setup"), true)
        return
    }

    icon := target "\config\assets\app.ico"
    if (ThemedAsk(_T("Macro Manager setup"), "", _T("Create a Start Menu shortcut?"), [[_T("Skip"), "", "btn"], [_T("Create"), "yes", "btnprimary"]], false) = "yes")
        MakeShortcut(A_Programs "\Macro Manager Beta.lnk", target, icon)
    if (ThemedAsk(_T("Macro Manager setup"), "", _T("Create a Desktop shortcut?"), [[_T("Skip"), "", "btn"], [_T("Create"), "yes", "btnprimary"]], false) = "yes")
        MakeShortcut(A_Desktop "\Macro Manager Beta.lnk", target, icon)
    ThemedNote(_T("Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config", target), _T("Macro Manager setup"))
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
        ThemedNote(_T("This doesn't look like an installed copy, nothing was removed."), _T("Uninstall Macro Manager"), true)
        return false
    }
    if (ThemedAsk(_T("Uninstall Macro Manager"), "", _T("Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}", dir), [[_T("Uninstall"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes") {
        if fromArg
            LaunchInstalled(dir)
        return false
    }
    ; offer a backup of the macros before everything is deleted
    if (!Macros.Length && FileExist(IniFile))
        try Load()
    if Macros.Length {
        r := ThemedAsk(_T("Uninstall Macro Manager"), "", _T("Export all your macros to a folder before uninstalling?"), [[_T("Cancel"), "", "btn"], [_T("Don't export"), "no", "btn"], [_T("Export first"), "yes", "btnprimary"]], false)
        if (r = "") {
            if fromArg
                LaunchInstalled(dir)
            return false
        }
        if (r = "yes") {
            bdir := DirSelect("*" A_Desktop, 3, _T("Choose a folder for the backup"))
            if (bdir = "") {
                if fromArg
                    LaunchInstalled(dir)
                return false
            }
            ThemedNote(_T("{1} macro(s) exported to:`n{2}", ExportAllTo(bdir), bdir), _T("Uninstall Macro Manager"))
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
    ThemedNote(_T("Macro Manager has been uninstalled.`nThe folder will be removed in a moment."), _T("Uninstall Macro Manager"))
    ; a separate hidden process deletes the folder after this app has exited
    Run(A_ComSpec ' /c ping -n 3 127.0.0.1 >nul & rmdir /s /q "' dir '"', A_Temp, "Hide")
    ExitApp
}

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

; ============ macro editor ============
EditMacro(idx) {
    isNew := !idx
    m := isNew ? Defaults() : View[idx]
    if isNew
        m["profiles"] := CurProfile
    pv := Map("v", m["profiles"])
    origProfs := m["profiles"]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", isNew ? _T("New macro") : _T("Edit macro"))
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)             ; same banner as the main window
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", isNew ? _T("New macro") : _T("Edit macro"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }

    g.AddText("x10 y100 w136 +0x200 h26", _T("Name"))
    eName := g.AddEdit("x150 y100 w250 h26", m["name"])
    g.AddText("x405 y100 w85 +0x200 h26", _T("Profiles"))
    bProfs := AddBtn(g, "x495 y100 w155 h26", ProfLabel(pv["v"]), (*) => (pv["v"] := PickProfiles(g, pv["v"]), bProfs.Text := ProfLabel(pv["v"])))
    g.AddText("x10 y136 w136 +0x200 h26", _T("Trigger key"))
    st := Map("key", m["hotkey"], "tkey", m["tkey"])
    bKey := AddBtn(g, "x150 y136 w250 h26", st["key"], (*) => CaptureKey(bKey, st, "key", false))
    g.AddText("x405 y136 w85 +0x200 h26", _T("Toggle"))
    bTog := AddBtn(g, "x495 y136 w155 h26", KeyLabel("", st["tkey"]), (*) => CaptureKey(bTog, st, "tkey", true))
    g.AddText("x10 y172 w136 +0x200 h26", _T("Only in app (exe)"))
    eApp := g.AddEdit("x150 y172 w420 h26", m["app"])
    bApp := AddBtn(g, "x580 y172 w70 h26", _T("Select"), (*) => (eApp.Value := PickApp(g, eApp.Value)))

    ; type + run mode: flat segmented buttons instead of native controls
    tsel := m["type"] = "move" ? 1 : (m["type"] = "seq" ? 2 : 3)
    rsel := m["repeat"] ? 2 : 1
    g.AddText("x10 y208 w136 +0x200 h26", _T("Type"))
    tb := []
    for i, nm in [_T("Move + actions"), _T("Sequence"), _T("Script (.ahk)")]
        tb.Push(AddBtn(g, "x" (150 + (i - 1) * 170) " y208 w160 h26", nm, SetType.Bind(i), i = tsel ? "btnprimary" : "btn"))
    rl := g.AddText("x10 y244 w136 +0x200 h26", _T("Run"))
    rb := []
    for i, nm in [_T("Once per key press"), _T("Repeat while key is held")]
        rb.Push(AddBtn(g, "x" (150 + (i - 1) * 255) " y244 w245 h26", nm, SetRun.Bind(i), i = rsel ? "btnprimary" : "btn"))

    ; --- group: move + actions ---
    mv := []
    mv.Push(g.AddText("x10 y292 w136 +0x200 h26", _T("Directions (optional)")))
    eDirs := g.AddEdit("x150 y292 w420 h26", m["dirs"])
    rb1 := AddBtn(g, "x580 y292 w70 h26", _T("Record"), (*) => StartListRec(eDirs, rb1))
    mv.Push(eDirs, rb1)
    mv.Push(g.AddText("x10 y328 w136 +0x200 h26", _T("Actions in order")))
    eActs := g.AddEdit("x150 y328 w420 h26", m["actions"])
    rb2 := AddBtn(g, "x580 y328 w70 h26", _T("Record"), (*) => StartListRec(eActs, rb2))
    mv.Push(eActs, rb2)
    mv.Push(g.AddText("x10 y364 w136 +0x200 h26", _T("Delays (ms)")))
    e1 := g.AddEdit("x150 y364 w110 h26 Number", m["g1"])
    e2 := g.AddEdit("x275 y364 w110 h26 Number", m["g2"])
    e3 := g.AddEdit("x400 y364 w110 h26 Number", m["g3"])
    e4 := g.AddEdit("x525 y364 w110 h26 Number", m["ge"])
    mv.Push(e1, e2, e3, e4)
    mv.Push(AddHint(g, "x150 y394 w120 h32", _T("dir↓ → action↓")))
    mv.Push(AddHint(g, "x275 y394 w120 h32", _T("action↓ → dir↑")))
    mv.Push(AddHint(g, "x400 y394 w120 h32", _T("dir↑ → action↑")))
    mv.Push(AddHint(g, "x525 y394 w120 h32", _T("between cycles")))
    mv.Push(AddHint(g, "x10 y434 w640", _T("Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4).")))

    ; --- group: sequence ---
    eSeq := g.AddEdit("x10 y292 w640 h120 Multi WantReturn", StrReplace(m["seq"], "|", "`n"))
    sq := [eSeq, AddHint(g, "x10 y418 w640", _T("One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"))]

    ; --- group: script ---
    code := ""
    if (m["type"] = "script" && m["file"] != "" && FileExist(ScriptPath(m)))
        code := FileRead(ScriptPath(m), "UTF-8")
    eCode := g.AddEdit("x10 y292 w640 h150 Multi WantReturn -Wrap HScroll", code)
    eCode.SetFont("s9", "Consolas")
    Roles[eCode.Hwnd] := "code"
    sc := [eCode, AddHint(g, "x10 y448 w640", _T("Runs as its own process while this macro is checked (AutoHotkey v2)."))]

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
        r := ThemedAsk("Macro Manager", _T("This macro is in several profiles ({1}).", ProfLabel(pv["v"]))
            , _T("Apply the change to all of them, or only to the current profile ({1})? The other profiles then keep the old, unchanged version.", CurProfile)
            , [[_T("Cancel"), "", "btn"], [_T("Only in `"{1}`"", CurProfile), "one", "btn"], [_T("All profiles"), "all", "btnprimary"]], false)
        if (r = "")
            return false
        if (r = "all")
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
                ThemedNote(_T("Paste or write a script first."), , true)
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
            m["trusted"] := 1                       ; written / pasted here, the code was in front of the user
        } else {
            key := Trim(st["key"])
            if (key = "") {
                ThemedNote(_T("Enter a trigger key."), , true)
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
        if isNew {
            Macros.Push(m)
            if (eSearch.Value != "")
                eSearch.Value := ""               ; the new macro must be visible
        }
        g.Destroy()
        Save()
        Apply()
        Refresh()
    }

    AddBtn(g, "x450 y482 w95 h34", _T("Save"), Commit, "btnprimary")
    AddBtn(g, "x555 y482 w95 h34", _T("Cancel"), (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Close", (*) => (FinishRec(), g.Destroy()))
    Toggle()
    ApplyTheme(g)
    ShowOver(g, "w660 h532", Main)
}

Num(v) => IsInteger(v) ? Integer(v) : 0

; ============ saving / loading ============
Defaults() {
    return Map("name", _T("New macro"), "hotkey", "LCtrl", "app", "", "type", "move", "enabled", 0,
        "dirs", "A,D", "actions", "1,2,3,4", "g1", 25, "g2", 30, "g3", 20, "ge", 10,
        "seq", "down A 25|tap 4 20|up A 5", "repeat", 1, "file", "", "tkey", "", "profiles", "", "trusted", 1)
}

Load() {
    global MasterOn, DarkOn, MasterKey, Profiles, CurProfile, AutoUpd, SeenVer
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
        for k in ["enabled", "g1", "g2", "g3", "ge", "repeat", "trusted"]
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
        try {
            SetCrit(m["app"])
            Hotkey(TrigHot(trig), MakeRun(m, trig), "On")
            Registered.Push([TrigHot(trig), m["app"]])
        } catch as e {
            HotIf()
            ThemedNote(_T("Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}", m["name"], trig, e.Message), , true)
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
        if (ThemedAsk("Macro Manager", _T("Same trigger key"), _T("Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work.", m["name"], m["hotkey"], other["name"])
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

; "only in app": a plain window criterion that the keyboard hook checks by itself. A script function as the
; criterion would make the hook wait for the app on every press (and every auto-repeat) of a trigger key - when
; the app is busy that stalls the whole keyboard, and Windows may drop the hook so a held macro never stops.
SetCrit(app) {
    if (app = "")
        HotIf()
    else
        HotIfWinActive("ahk_exe " app)
}
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

; {Blind}: Send leaves the user's held Shift / Ctrl / Alt / Win alone. Without it, every Send briefly releases
; them and presses them again afterwards - when the key is let go in that moment, Windows keeps it "held" (stuck).
DownStr(parts) {
    s := "{Blind}"
    for k in parts
        s .= "{" k " down}"
    return s
}

UpStr(parts) {
    s := "{Blind}"
    for k in parts
        s .= "{" k " up}"
    return s
}

ReleaseAll(arr) {
    for parts in arr
        KeyUp(parts)
}

; keys the macros are holding down right now (HeldKeys, released when the app exits in the middle of a macro)
KeyDown(parts) {
    Send DownStr(parts)
    for k in parts
        HeldKeys[k] := true
}
KeyUp(parts) {
    Send UpStr(parts)
    for k in parts
        if HeldKeys.Has(k)
            HeldKeys.Delete(k)
}
ReleaseHeld() {
    for k in HeldKeys.Clone()
        try Send "{Blind}{" k " up}"
    HeldKeys.Clear()
}

; a pause between steps: 0 still lets Windows and the app breathe (Sleep -1 = handle messages, no wait)
StepWait(ms) {
    if (ms > 0)
        Sleep ms
    else
        Sleep -1
}

; repeated macros: one cycle takes at least this long, so a macro with 0 ms delays can't flood
; Windows with thousands of key events per second (that blocks the whole keyboard, even after the app is closed)
CycleFloor(t0) {
    rest := 10 - (A_TickCount - t0)
    if (rest > 0)
        Sleep rest
}

; ============ type: move + actions ============
RunMove(m, trig) {
    global MacroBusy
    MacroBusy++
    try RunMove2(m, trig)
    finally MacroBusy--
}

RunMove2(m, trig) {
    dirs := SplitKeys(m["dirs"])
    acts := SplitKeys(m["actions"])
    if !acts.Length
        return
    g1 := m["g1"], g2 := m["g2"], g3 := m["g3"], ge := m["ge"]
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    rep := m["repeat"] && !IsWheel(trig)          ; a wheel can't be held
    while (rep ? Active(m, trig) : n < acts.Length) {      ; once = every action one time
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            KeyDown(dir)      ; 1. direction down (all keys of a chord together)
            StepWait(g1)
            KeyDown(key)      ; 2. action down
            StepWait(g2)
            KeyUp(dir)        ; 3. direction up
            StepWait(g3)
            KeyUp(key)        ; 4. action up
            di := di >= dirs.Length ? 1 : di + 1
        } else {                   ; no movement: action only
            KeyDown(key)
            StepWait(g2)
            KeyUp(key)
        }
        StepWait(ge)
        ai := ai >= acts.Length ? 1 : ai + 1
        if rep
            CycleFloor(t0)
    }
    ReleaseAll(dirs)
    ReleaseAll(acts)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))          ; "once": don't restart until the key is released
}

; ============ type: custom sequence ============
RunSeq(m, trig) {
    global MacroBusy
    MacroBusy++
    try RunSeq2(m, trig)
    finally MacroBusy--
}

RunSeq2(m, trig) {
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
        t0 := A_TickCount
        for s in steps {
            if (rep && !Active(m, trig)) {
                stop := true
                break
            }
            if (s[1] = "down")
                KeyDown(s[2])
            else if (s[1] = "up")
                KeyUp(s[2])
            else {
                KeyDown(s[2])
                KeyUp(s[2])
            }
            StepWait(s[3])
        }
        if !rep
            stop := true
        else if !stop
            CycleFloor(t0)
    }
    ReleaseAll(used)
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))
}

; ============ stuck modifier keys ============
; AltGr = a fake Left Ctrl + Right Alt. A macro on Left Ctrl swallows the real Left Ctrl key, and the "up" of
; AltGr's fake Ctrl could get swallowed with it: Windows then keeps Ctrl pressed - every key and mouse click
; becomes Ctrl+..., so keyboard and mouse seem dead, and pressing Left Ctrl can't fix it while the macro is on.
AltGrUp(*) {
    Sleep 30
    for k in ["LCtrl", "RAlt"]
        if (GetKeyState(k) && !GetKeyState(k, "P"))
            Send "{Blind}{" k " up}"
}

; every 250 ms: Ctrl / Alt / Shift / Win down for Windows but not held on the keyboard for over a second -> released
ModWatch() {
    static mods := ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"], since := Map()
    if (MacroBusy > 0 || Rec.ih || GetKeyState("RAlt", "P")) {      ; a macro is playing, recording, or AltGr is held
        since.Clear()
        return
    }
    for k in mods {
        if (GetKeyState(k) && !GetKeyState(k, "P")) {
            if !since.Has(k)
                since[k] := A_TickCount
            else if (A_TickCount - since[k] >= 1000) {
                Send "{Blind}{" k " up}"
                since.Delete(k)
            }
        } else if since.Has(k)
            since.Delete(k)
    }
}

; ============ embedded logo / icon ============
EnsureAssets() {
    try {
        DirCreate(AssetsDir)
        verFile := AssetsDir "\version.txt"
        cur := FileExist(verFile) ? Trim(FileRead(verFile)) : ""
        if (cur != AssetVersion || !FileExist(IconFile) || !FileExist(LogoFile) || !FileExist(SwOnFile) || !FileExist(LogoWideFile) || !FileExist(CbDarkFile) || !FileExist(BadgeMainFile) || !FileExist(DiscordFile) || !FileExist(DiscordHovFile) || !FileExist(FlagFile("de"))) {
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
            B64ToFile(DiscordB64(), DiscordFile)
            B64ToFile(DiscordHovB64(), DiscordHovFile)
            for c in LangOrder
                B64ToFile(FlagB64(c), FlagFile(c))
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
    if (!HoverHwnd && !DllCall("IsWindowVisible", "Ptr", Main.Hwnd))
        return                                      ; window hidden in the tray: nothing to hover
    h := 0
    try MouseGetPos(, , , &h, 2)
    if (h && BtnAlias.Has(h))
        h := BtnAlias[h]
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
            ToolTip(UpdAvail ? _T("New version {1} available - click to update", UpdInfo["ver"]) : _T("Up to date (v{1}) - click to check again", AppVersion))
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
        global CbIL, CbSz, CbDC, CbBmp
        if !CbDC
            CbDC := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        DllCall("SelectObject", "Ptr", CbDC, "Ptr", hbm, "Ptr")   ; kept for AlphaBlend (the image list can't blend it cleanly)
        if CbBmp
            DllCall("DeleteObject", "Ptr", CbBmp)                  ; the previous theme's bitmap is not used any more
        CbBmp := hbm
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
    Rec.mode := ""                   ; not recording any more (update checks wait while this is set)
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
            Rec.btn.Text := _T("Record")
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
    btn.Text := _T("Done")
    Roles[btn.Hwnd] := "btnprimary"
    PaintBtn(btn.Hwnd, false)
    edit.Value := ""
    RecStart("list", (txt) => edit.Value := txt)
}

KeyLabel(prefix, v) => prefix (v = "" ? _T("none") : v)

; click-to-capture a key into st[field]; Esc cancels, Backspace/Delete clear (when allowClear)
CaptureKey(btn, st, field, allowClear, prefix := "", onDone := 0) {
    FinishRec()
    btn.Text := allowClear ? _T("Press a key or mouse button...   (Esc = cancel, Backspace = none)") : _T("Press a key or mouse button...   (Esc = cancel)")
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

ProfBtnText() => _T("Profile: {1}", CurProfile) "  ▾"

ProfLabel(v) {
    t := StrReplace(v, "|", ", ")
    return StrLen(t) > 24 ? _T("{1} profiles", StrSplit(v, "|").Length) : t
}

; themed drop-down for the language (same look as the profile menu); the app restarts to apply it
LangMenu(*) {
    global ProfPop
    if ProfPop {
        ClosePop()
        return
    }
    if (A_TickCount - ProfClosed < 300)         ; the click that just closed it
        return
    W := 150
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" Main.Hwnd)
    g.SetFont("s9", "Segoe UI")
    y := 1
    for code in LangOrder {
        cur := (code = Lang)
        b := AddBtn(g, "x1 y" y " w" W " h32 Left", "             " LangNames[code], SetLang.Bind(code), cur ? "btnprimary" : "btn")
        fl := g.AddPicture("x10 y" (y + 8) " w24 h16", FlagFile(code))
        fl.OnEvent("Click", SetLang.Bind(code))
        Roles[fl.Hwnd] := "skip"
        BtnAlias[fl.Hwnd] := b.Hwnd
        y += 32
    }
    ApplyTheme(g)
    g.BackColor := DarkOn ? "3A3E49" : "C9C9D2"   ; becomes the 1px frame
    pt := Buffer(8)
    bLang.GetPos(&bx, &by, , &bh)
    NumPut("Int", bx, "Int", by + bh + 2, pt)
    DllCall("ClientToScreen", "Ptr", Main.Hwnd, "Ptr", pt)
    g.OnEvent("Escape", ClosePop)
    ProfPop := g
    g.Show("x" NumGet(pt, 0, "Int") " y" NumGet(pt, 4, "Int") " w" (W + 2) " h" (y + 1))
    SetTimer(PopWatch, 100)
}

SetLang(code, *) {
    global Lang
    ClosePop()
    if (code = Lang)
        return
    Lang := code
    Save()
    Reload()
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
    AddBtn(g, "x1 y" y " w" W " h32 Left", "  +   " _T("New profile..."), (*) => (ClosePop(), NewProfile()))
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       " _T("Rename current..."), (*) => (ClosePop(), RenameProfile()))
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       " _T("Delete current"), (*) => (ClosePop(), DeleteProfile()), "btndanger")
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
    v := ThemedInput(_T("New profile"), _T("Name of the new profile:"))
    if (v = false)
        return
    nm := CleanName(v)
    if (nm = "")
        return
    if HasProf(JoinProfs(Profiles), nm) {
        ThemedNote(_T("A profile with this name already exists."), , true)
        return
    }
    Profiles.Push(nm)
    SwitchProfile(nm)
}

RenameProfile(*) {
    global CurProfile
    v := ThemedInput(_T("Rename profile"), _T("New name for profile `"{1}`":", CurProfile), CurProfile)
    if (v = false)
        return
    nm := CleanName(v)
    if (nm = "" || nm = CurProfile)
        return
    if HasProf(JoinProfs(Profiles), nm) {
        ThemedNote(_T("A profile with this name already exists."), , true)
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
        ThemedNote(_T("You can't delete the last profile."), , true)
        return
    }
    if (ThemedAsk("Macro Manager", "", _T("Delete profile `"{1}`"?`n`nMacros that belong only to this profile are moved to the first remaining profile.", CurProfile), [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
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
    p := Gui("+Owner" owner.Hwnd " +ToolWindow", _T("Profiles of this macro"))
    p.SetFont("s9", "Segoe UI")
    p.AddText("x14 y12 w300", _T("The macro is active in the selected profiles:"))
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
            ThemedNote(_T("Select at least one profile."), , true)
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
    AddBtn(p, "x116 y" (y + 10) " w90 h32", _T("OK"), Ok, "btnprimary")
    AddBtn(p, "x216 y" (y + 10) " w90 h32", _T("Cancel"), Close)
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
    r := ThemedAsk(_T("Select application"), "", _T("Use one of the currently running applications, or browse for the .exe file?")
        , [[_T("Cancel"), "", "btn"], [_T("Browse for the .exe"), "browse", "btn"], [_T("Running applications"), "list", "btnprimary"]], false)
    if (r = "")
        return cur
    if (r = "browse")
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
        ThemedNote(_T("No running applications found - choose the file instead."), _T("Select application"))
        return BrowseApp(cur)
    }
    res := ""
    done := false
    p := Gui("+Owner" owner.Hwnd " +ToolWindow", _T("Running applications"))
    p.SetFont("s9", "Segoe UI")
    p.AddText("x10 y10 w380", _T("Double-click an application:"))
    lv := p.AddListView("x10 y32 w380 r11 -Hdr -E0x200 -Multi", [_T("Application")])
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
    AddBtn(p, "x10 y230 w95 h30", _T("Browse..."), Browse)
    AddBtn(p, "x205 y230 w90 h30", _T("Select"), Choose, "btnprimary")
    AddBtn(p, "x300 y230 w90 h30", _T("Cancel"), Close)
    p.OnEvent("Close", Close)
    ApplyTheme(p)
    owner.Opt("+Disabled")
    ShowOver(p, "w400 h272", owner)
    while !done
        Sleep 50
    return res != "" ? res : cur
}

BrowseApp(cur) {
    f := FileSelect(1, , _T("Select the application"), _T("Applications (*.exe)"))
    if (f = "")
        return cur
    SplitPath f, &name
    return name
}

; ============ updates (GitHub) ============
ToggleAutoUpd(*) {
    global AutoUpd
    AutoUpd := !AutoUpd
    A_TrayMenu.ToggleCheck(_T("Check for updates at start"))
    Save()
}

; HTTP GET that waits with Sleep instead of blocking: hotkeys and running macros keep working meanwhile.
; returns Map(status, text, etag[, body]) or 0 (error / timeout)
HttpSend(url, hdrs, timeoutMs := 8000, wantBody := false) {
    r := 0
    try {
        r := ComObject("Msxml2.ServerXMLHTTP.6.0")          ; WinHTTP based, asynchronous, no browser cache
        r.setTimeouts(3000, 3000, 8000, 15000)
        r.open("GET", url, true)
    } catch {
        r := 0
    }
    if !r
        return HttpSendSync(url, hdrs, wantBody)
    try {
        r.setRequestHeader("User-Agent", "MacroManager")
        for k, v in hdrs
            r.setRequestHeader(k, v)
        r.send()
        t0 := A_TickCount
        while (r.readyState != 4) {
            if (A_TickCount - t0 > timeoutMs) {
                try r.abort()
                return 0
            }
            Sleep 20
        }
        res := Map("status", r.status, "text", "", "etag", "")
        try res["etag"] := r.getResponseHeader("ETag")
        if wantBody
            res["body"] := r.responseBody
        else
            try res["text"] := r.responseText
        return res
    }
    return 0
}

; fallback when MSXML is missing: the old blocking WinHttp request
HttpSendSync(url, hdrs, wantBody) {
    try {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(3000, 3000, 8000, 15000)
        r.Open("GET", url, false)
        r.SetRequestHeader("User-Agent", "MacroManager")
        for k, v in hdrs
            r.SetRequestHeader(k, v)
        r.Send()
        res := Map("status", r.Status, "text", "", "etag", "")
        try res["etag"] := r.GetResponseHeader("ETag")
        if wantBody
            res["body"] := r.ResponseBody
        else
            try res["text"] := r.ResponseText
        return res
    }
    return 0
}

HttpGet(url) {
    r := HttpSend(url, Map("Cache-Control", "no-cache"))
    return (r && r["status"] = 200) ? r["text"] : ""
}

; GET with extra headers; returns the text (200) or "" ; status / ETag are returned through the by-ref parameters
HttpReq(url, hdrs, &status, &etag) {
    status := 0, etag := ""
    r := HttpSend(url, hdrs)
    if !r
        return ""
    status := r["status"], etag := r["etag"]
    return status = 200 ? r["text"] : ""
}

; download a repository file through the GitHub API (always fresh, not cached like raw.githubusercontent.com)
GhDownload(file, dest) {
    try {
        r := HttpSend("https://api.github.com/repos/" UpdRepo "/contents/" file "?ref=" UpdBranch, Map("Accept", "application/vnd.github.raw+json"), 30000, true)
        if (!r || r["status"] != 200)
            return false
        sa := ComObjValue(r["body"])
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
    if (!AutoUpd || Rec.ih || MacroBusy > 0 || A_TickCount - last < minAge)
        return                       ; recording, or a macro is playing: try again at the next tick
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
    if (busy || Rec.ih)
        return
    busy := true
    try {
        if !UpdAvail {
            r := QueryUpdate()
            if (r = "error") {
                ThemedNote(_T("Could not check for updates. Check your internet connection and try again."), _T("Updates"), true)
                return
            }
            if (r = "latest") {
                ThemedNote(_T("You have the latest version (v{1}).", AppVersion), _T("Updates"))
                return
            }
        }
        msg := (UpdInfo["notes"] != "" ? UpdInfo["notes"] "`n`n" : "") Trim(_T("`n`nUpdate now? The app restarts. Your macros, profiles and settings are not changed."), "`n")
        if (ThemedAsk(_T("Macro Manager update"), _T("Version {1} is available (you have v{2}).", UpdInfo["ver"], AppVersion), msg
            , [[_T("Later"), "", "btn"], [_T("Update now"), "yes", "btnprimary"]], false) = "yes")
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
        ThemedNote(_T("The download failed. Try again later."), _T("Updates"), true)
        return
    }
    got := Sha256(tmp)
    if (got != sha) {
        sz := 0
        try sz := FileGetSize(tmp)
        try FileDelete tmp
        ThemedNote(_T("The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)", SubStr(sha, 1, 16), (got = "" ? _T("(could not compute)") : SubStr(got, 1, 16) "..."), sz), _T("Updates"), true)
        return
    }
    txt := ""
    try txt := FileRead(tmp, "UTF-8")
    if (!InStr(txt, "#Requires AutoHotkey v2") || !InStr(txt, "AppVersion")) {
        try FileDelete tmp
        ThemedNote(_T("The downloaded file is not a valid Macro Manager script. Nothing was changed."), _T("Updates"), true)
        return
    }
    if A_IsCompiled {
        UpdateCompiled(tmp)
        return
    }
    try {
        FileCopy(A_ScriptFullPath, A_ScriptFullPath ".bak", 1)     ; macros live in the config folder and are not touched
        FileCopy(tmp, A_ScriptFullPath, 1)
        FileDelete tmp
    } catch as e {
        ThemedNote(_T("Could not replace the app file: {1}", e.Message), _T("Updates"), true)
        return
    }
    Reload()
}

; an install made by an older version where the app was compiled into "Macro Manager.exe":
; the new version goes to "Macro Manager.ahk" and the .exe becomes the branded AutoHotkey interpreter that runs it
; (Windows lets a running .exe be renamed, so the old one is moved aside to "Macro Manager.exe.bak")
UpdateCompiled(tmp) {
    dir := A_ScriptDir
    exe := A_ScriptFullPath
    src := dir "\Macro Manager.ahk"
    ahk := AhkExe()
    if (ahk = "" || ahk = exe) {
        try FileDelete tmp
        ThemedNote(_T("Could not replace the app file: {1}", "AutoHotkey v2 not found"), _T("Updates"), true)
        return
    }
    try {
        FileCopy(tmp, src, 1)
        FileMove(exe, exe ".bak", 1)
        try {
            FileCopy(ahk, exe, 1)
        } catch as e {
            FileMove(exe ".bak", exe, 1)            ; put the old program back
            throw e
        }
        PatchExe(exe, IconFile)                     ; icon + name (if it fails the copy still works, just looks like AutoHotkey)
        FileDelete tmp
    } catch as e {
        try FileDelete(src)
        ThemedNote(_T("Could not replace the app file: {1}", e.Message), _T("Updates"), true)
        return
    }
    Run('"' exe '" "' src '"', dir)
    ExitApp
}

; ============ help window ============
HelpTopics() {
    t := Map()
    order := []
    order.Push("Release notes")
    t["Release notes"] := _T("Version {1}", AppVersion) "`n`n" ReleaseNotes
    order.Push("Getting started")
    t["Getting started"] := _TL("hlp_start", "Macro Manager runs hotkey macros for you. Each macro has a trigger key; while you hold it (inside the chosen application) the macro plays.`n`n- Tick a macro in the list to turn it on, untick to turn it off.`n- The switch All macros in the banner turns every macro on or off at once.`n- Dark mode switches the look of the app.`n- The language button in the banner switches the app language (English, Čeština, Polski, Deutsch). The app restarts to apply it.`n- Double-click a row (or press Edit) to change a macro. Add creates a new one, Copy duplicates it, Delete removes it.`n- To select several macros drag the mouse over the rows (or Ctrl / Shift + click). Copy, Delete, Export, Move up / down and dragging out of the window work on all selected rows.`n- Closing the window keeps the app running in the tray. Right-click the tray icon for Open window / Uninstall / Exit.`n- The app always runs as administrator, so macros also work in games that run elevated.`n- The search box above the list shows only the macros whose name, key or application contains the text. The cross next to it clears it.")
    order.Push("Add / edit a macro")
    t["Add / edit a macro"] := _TL("hlp_edit", "Name - any text, shown in the list.`nProfiles - which profiles the macro belongs to (can be several).`nTrigger key - click the box, then press the key or a mouse button (right, middle, side buttons X1 / X2, mouse wheel). Hold Ctrl / Shift / Alt while pressing to make a combination, for example Ctrl+XButton1. Esc cancels.`nToggle - optional key that turns this macro on/off without opening the window. Backspace clears it.`nOnly in app (exe) - the macro works only while that program is in front. Press Select to pick a running application or browse for the .exe. Empty = works everywhere.`nType - Move + actions, Sequence or Script (.ahk). See the next topics.`nRun - Once per key press: plays one pass and waits until you release the key. Repeat while key is held: plays again and again until you release the key (it stops immediately).`n`nSave stores the macro, Cancel throws changes away.")
    order.Push("Move + actions")
    t["Move + actions"] := _TL("hlp_move", "Made for games where you keep moving (for example A and D) and cast spells in between.`n`nDirections - the movement keys, in order, for example: a,d`nActions in order - the keys to press, one per cycle, for example: 1,2,1,F7,1,F8`n`nEvery cycle does this, with the delays you set:`n  1. direction down`n  2. (delay 1) action down`n  3. (delay 2) direction up`n  4. (delay 3) action up`n  5. (delay 4) pause, then the next direction + next action`n`nThe lists repeat from the start when they end. If Directions is empty, only the actions are pressed: hold time = delay 2, pause = delay 4.`nIf a game ignores the macro, raise the delays (20-30 ms is common).")
    order.Push("Sequence")
    t["Sequence"] := _TL("hlp_seq", "A free list of steps. Write one step per line:`n`n  down KEY PAUSE   - press and hold the key`n  up KEY PAUSE     - release the key`n  tap KEY PAUSE    - press and release at once`n`nPAUSE is the wait after the step in milliseconds (empty = 0).`n`nExample - quick A / D change:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nExample - attack and spells:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nExample - two keys together:`n  tap Shift+4 50`n`nWith Run = Repeat the lines play in a loop while the trigger key is held; with Once they play one time.`nKeys that are still held when you release the trigger are released automatically.")
    order.Push("Script (.ahk)")
    t["Script (.ahk)"] := _TL("hlp_script", "For anything the other types can not do. Paste or write your own AutoHotkey v2 script.`n`n- The script runs as its own process while the macro is ticked, and is stopped when you untick it.`n- It must be AutoHotkey v2 code (v1 scripts will not work).`n- Trigger key and application filter are not used, your script does that itself.`n- Imported .ahk files that were not made by Macro Manager become Script macros.`n- An imported script asks before it runs for the first time: it runs with administrator rights, so only turn it on if you trust where it came from. The window shows what the script does (for example starts programs or deletes files) and offers to show the code.")
    order.Push("Keys and recording")
    t["Keys and recording"] := _TL("hlp_keys", "Key names are the AutoHotkey names: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nA key can also be written as a scan code, for example sc002 - this is the physical key, regardless of layout. Keys like comma, plus, & and | are saved this way automatically.`n`nMouse: the trigger, toggle and All macros keys can also be a mouse button: RButton, MButton (wheel click), XButton1 / XButton2 (the two side buttons), or the wheel itself (WheelUp / WheelDown / WheelLeft / WheelRight). A wheel has no hold, so wheel macros always play once. The left button is not offered.`nGaming / MMO mice: windows only knows five mouse buttons, the extra side buttons are handled by the mouse software (G HUB, Synapse, iCUE, ...). Set them there to keys, best F13 - F24 (or Ctrl+Alt+number); Macro Manager then sees them as ordinary keys, so click the trigger box and press the side button.`n`nRecord (next to Directions and Actions): press Record, press the keys in the order you want, then press Done. The field fills in live. Macros are paused while recording.`n`nKeys at the same time: keys that you hold together are saved as one step joined with +, for example Shift+4. When the macro plays, all of them go down together and are released together (not Shift first and 4 afterwards).`nThe same works by typing it in the fields: a,Shift+4,d")
    order.Push("Profiles")
    t["Profiles"] := _TL("hlp_profiles", "Profiles keep different sets of macros apart (for example one per game).`n`n- The profile button in the banner shows the current profile. Click it to switch, or to create / rename / delete a profile.`n- The list shows only the macros of the current profile, and only those are active.`n- In the editor, Profiles lets you choose one or more profiles for the macro. When you change a macro that belongs to several profiles, the app asks: apply the change to all of them, or only to the current profile (the other profiles keep the old version).`n- Tick state of a macro stays the same in every profile; switching profile just changes which macros are in play.`n- Deleting a profile moves macros that belonged only to it to the first remaining profile.")
    order.Push("Toggle keys")
    t["Toggle keys"] := _TL("hlp_toggle", "Toggle (in the editor) - a key that switches that single macro on / off, same as ticking it in the list. A small tooltip shows ON / OFF.`nAll macros toggle key (button under the list) - switches the master switch. Works in every profile.`n`nClick the button, press the key. Esc cancels, Backspace removes the key.`nMacros of other profiles do not react to their toggle keys.")
    order.Push("Order, export, backup")
    t["Order, export, backup"] := _TL("hlp_order", "Move up / Move down change the order in the list. Clicking a column header sorts the list (click again to reverse).`n`nExport... saves the selected macro as a standalone AutoHotkey v2 .ahk file that also runs by itself (it asks for admin rights).`nImport... loads one or more .ahk files (or just drag them onto the main window). You can also drag a macro from the list onto the desktop / a folder / a chat window to export it as an .ahk file. The macro is named after the file; files made by Macro Manager come back as editable macros, other scripts become Script macros. Imports go to the current profile and start switched off.`nExport all... writes every macro to a folder, one file each.`n`nBackup... (next to Uninstall) saves everything - macros, profiles, settings and script files - into one .mmbackup file, and restores it on a new PC or after a reinstall. You can also drop the backup file onto the window. Before restoring, the current state is saved as config\backup-before-restore.mmbackup.`n`nUninstall deletes the whole app folder including all macros and settings. It offers to export all macros first.")
    order.Push("Updates")
    t["Updates"] := _TL("hlp_updates", "The arrow icon in the banner (next to the profile button) shows whether a new version exists: grey = you are up to date, green = a new version is available. Hover it for details.`n`nThe app checks a few seconds after it starts (can be turned off in the tray menu: Check for updates at start). Click the icon at any time to check again. Nothing is installed until you click the green icon and confirm.`n`nWhen you update, the app downloads the new file, checks its checksum, keeps the old one as Macro Manager.ahk.bak and restarts. Your macros, profiles and settings are stored separately in the config folder and stay exactly as they are.`n`nIf something goes wrong, close the app, delete Macro Manager.ahk and rename Macro Manager.ahk.bak back to Macro Manager.ahk.`n`nThe update needs internet access to github.com.")
    order.Push("Tips and problems")
    t["Tips and problems"] := _TL("hlp_tips", "- The game does nothing: try raising the delays, make sure Only in app matches the game (use Select), and keep the app as administrator.`n- Character runs in one direction: keep direction pairs in Directions (a,d) and the delay between cycles small but not 0.`n- A macro does not start: check that it is ticked, All macros is on, it is in the current profile and the trigger key is set (not undefined).`n- Two macros with the same trigger key: only one of them works - use different keys or different profiles.`n- Stuck key after an abort: press and release it once; the app releases keys it pressed when the macro stops.`n- Settings and scripts live in the config folder next to the app.")
    return [order, t]
}

OpenDiscord(*) {
    static last := 0
    if (A_TickCount - last < 800)                 ; click event + mouse polling may both fire
        return
    last := A_TickCount
    try {
        Run("discord://-/users/" DiscordId)
        return
    }
    try {
        Run("https://discord.com/users/" DiscordId)
        return
    }
    A_Clipboard := "https://discord.com/users/" DiscordId
    ThemedNote(_T("Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}", "https://discord.com/users/" DiscordId))
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
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", _T("Help"))
    HelpGui := g
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", _T("Help"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s10 norm cD8D8DC", "Segoe UI")
        sup := g.AddText("x330 y36 w250 h24 Right BackgroundTrans", _T("For support click here") " " Chr(0x2192))
        Roles[sup.Hwnd] := "skip"
        sup.OnEvent("Click", OpenDiscord)
        dc := g.AddPicture("x590 y27 w44 h33", DiscordFile)
        Roles[dc.Hwnd] := "skip"
        dc.OnEvent("Click", OpenDiscord)
        hov := false, wasDown := false
        SetTimer(DcHover, 40)
        g.SetFont("s9 norm c000000", "Segoe UI")
    }
    nav := Map()
    y := 94
    for nm in order {
        nav[nm] := AddBtn(g, "x10 y" y " w158 h30 Left", "  " _T(nm), HelpShow.Bind(nm), "btn")
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
    ; hover feedback for the support link: hand cursor, gold underlined text, lighter icon
    DcHover() {
        if !IsSet(g) || !WinExist("ahk_id " g.Hwnd) {
            SetTimer(DcHover, 0)
            return
        }
        MouseGetPos(&mx, &my)
        on := false
        if true {
            WinGetClientPos(&cx, &cy, , , "ahk_id " g.Hwnd)
            for c in [sup, dc] {
                c.GetPos(&px, &py, &pw, &ph)
                if (mx - cx >= px && mx - cx < px + pw && my - cy >= py && my - cy < py + ph)
                    on := true
            }
        }
        if on
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr"))     ; IDC_HAND
        down := GetKeyState("LButton", "P")
        if (on && down && !wasDown)               ; own click detection (works even if the control sends no click event)
            SetTimer(OpenDiscord, -1)
        wasDown := down
        if (on = hov)
            return
        hov := on
        sup.SetFont(on ? "s10 Underline cD0AE6B" : "s10 norm cD8D8DC")
        dc.Value := on ? DiscordHovFile : DiscordFile
    }
    HelpClose(*) {
        global HelpGui
        SetTimer(DcHover, 0)
        HelpGui := 0
        g.Destroy()
    }
    AddBtn(g, "x560 y" (y + 14) " w90 h32", _T("Close"), HelpClose)
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
    ; pressing a row that is already selected (without Ctrl / Shift) = grab the selection: it stays as it is while dragging
    DragStart["lock"] := (SendMessage(0x102C, hit[1] - 1, 0x0002, LV) & 0x0002) != 0       ; LVM_GETITEMSTATE, LVIS_SELECTED
        && !GetKeyState("Ctrl", "P") && !GetKeyState("Shift", "P")
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
        if DragStart["lock"]                              ; dragging a selected row: the selection is locked, nothing else gets selected
            return
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
    used := Map()
    dir := A_Temp "\MacroManager-drag"
    try DirDelete(dir, 1)                              ; files of an earlier drag
    DirCreate(dir)
    for m in sel {
        if (m["type"] != "script") {
            k := Trim(m["hotkey"])
            if (k = "" || k = "undefined") {
                Toast(_T("Set a trigger key first: {1}", m["name"]))
                continue
            }
        }
        code := ExportCode(m)
        if (code = "")
            continue
        base := RegExReplace(m["name"], '[\\/:*?"<>|]', "_"), nm := base, k := 1
        while used.Has(StrLower(nm))                    ; two macros with the same name: "name (1).ahk"
            nm := base " (" k++ ")"
        used[StrLower(nm)] := true
        path := dir "\" nm ".ahk"
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
        ThemedNote(_T("Dragging the macro out failed:`n{1}", e.Message), , true)
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

FlagFile(c) => AssetsDir "\flag_" c ".png"

; ============ dialogs in the app's own look (instead of the grey system MsgBox / InputBox) ============
; the app window in front: the dialog belongs to it and blocks it while open (0 = none, e.g. hidden in the tray)
DlgOwner() {
    try {
        h := WinExist("A")
        if (h && WinGetPID("ahk_id " h) = ProcessExist() && DllCall("IsWindowVisible", "Ptr", h))
            return h
        if DllCall("IsWindowVisible", "Ptr", Main.Hwnd)
            return Main.Hwnd
    }
    return 0
}

; long words (paths) get line breaks after a "\" so they never run out of the window
DlgWrap(text, maxLen := 58) {
    out := ""
    for line in StrSplit(text, "`n") {
        words := []
        for w in StrSplit(line, " ") {
            while (StrLen(w) > maxLen) {
                cut := InStr(SubStr(w, 1, maxLen), "\", , -1)  ; last "\" within the limit
                cut := cut > 8 ? cut : maxLen
                words.Push(SubStr(w, 1, cut) "`n")
                w := SubStr(w, cut + 1)
            }
            words.Push(w)
        }
        l := ""
        for i, w in words
            l .= (i > 1 && SubStr(words[i - 1], -1) != "`n" ? " " : "") w
        out .= (A_Index > 1 ? "`n" : "") l
    }
    return out
}

; static text that wraps (also long paths) and gets exactly the height it needs
DlgText(g, opts, text) {
    text := DlgWrap(text)
    c := g.AddText(opts " +0x2080", text)                       ; SS_EDITCONTROL | SS_NOPREFIX (& stays &)
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", c.Hwnd, "Ptr", rc)
    hdc := DllCall("GetDC", "Ptr", c.Hwnd, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, c), "Ptr")     ; WM_GETFONT
    DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x2C10)       ; CALCRECT|WORDBREAK|EDITCONTROL|NOPREFIX
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    DllCall("ReleaseDC", "Ptr", c.Hwnd, "Ptr", hdc)
    c.Move(, , , Round((NumGet(rc, 12, "Int") + 2) * 96 / A_ScreenDPI))
    return c
}

; question / message window.  buttons: [[label, value, role], ...] at the bottom right, left to right;
; the "btnprimary" one is the default (Enter).  Esc / closing the window returns "".
ThemedAsk(title, heading, body, buttons, warn := true) {
    res := "", done := false
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", title)
    g.SetFont("s9", "Segoe UI")
    x0 := 16, y := 16
    if warn {
        try {
            bp := g.AddPicture("x16 y" (heading = "" ? 16 : 17) " w16 h16", DarkOn ? BadgeDkFile : BadgeLtFile)   ; the yellow !
            Roles[bp.Hwnd] := "skip"
            x0 := 40
        }
    }
    if (heading != "") {
        g.SetFont("s10 bold", "Segoe UI")
        hc := DlgText(g, "x" x0 " y14 w" (484 - x0), heading)
        hc.GetPos(, &hy, , &hh)
        y := hy + hh + 8
        g.SetFont("s9 norm", "Segoe UI")
        bx := 16
    } else
        bx := x0
    bc := DlgText(g, "x" bx " y" y " w" (484 - bx), body)
    bc.GetPos(, &by, , &bh)
    btnY := by + bh + 18
    Pick(v, *) {
        res := v
        Close()
    }
    Close(*) {
        if done
            return
        done := true
        if oh
            DllCall("EnableWindow", "Ptr", oh, "Int", 1)        ; before Destroy, so the owner gets the focus back
        g.Destroy()
    }
    def := "", x := 484, i := buttons.Length
    while (i >= 1) {
        b := buttons[i]
        w := Max(100, 28 + 7 * StrLen(b[1]))
        x -= w
        AddBtn(g, "x" x " y" btnY " w" w " h32", b[1], Pick.Bind(b[2]), b[3])
        if (b[3] = "btnprimary")
            def := b[2]
        x -= 10
        i--
    }
    hb := g.AddButton("Default x-300 y-300 w1 h1")              ; invisible: Enter = the highlighted button
    hb.OnEvent("Click", Pick.Bind(def))
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)            ; modal: the owner waits
    ShowOver(g, "w500 h" (btnY + 46), oh)
    while !done
        Sleep 50
    return res
}

; message with an OK button
ThemedNote(text, title := "Macro Manager", warn := false, heading := "") {
    ThemedAsk(title, heading, text, [[_T("OK"), "ok", "btnprimary"]], warn)
}

; text input; returns the text, or false when cancelled
ThemedInput(title, prompt, default := "") {
    res := false, done := false
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", title)
    g.SetFont("s9", "Segoe UI")
    pc := DlgText(g, "x16 y16 w368", prompt)
    pc.GetPos(, &py, , &ph)
    ed := g.AddEdit("x16 y" (py + ph + 8) " w368 h26", default)
    ed.SetFont("s10")
    btnY := py + ph + 8 + 26 + 18
    Ok(*) {
        res := ed.Value
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
    AddBtn(g, "x174 y" btnY " w100 h32", _T("OK"), Ok, "btnprimary")
    AddBtn(g, "x284 y" btnY " w100 h32", _T("Cancel"), Close)
    hb := g.AddButton("Default x-300 y-300 w1 h1")
    hb.OnEvent("Click", Ok)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w400 h" (btnY + 46), oh)
    ed.Focus()
    SendMessage(0xB1, 0, -1, ed)                                ; EM_SETSEL: all selected, typing replaces it
    while !done
        Sleep 50
    return res
}

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

; ============ embedded images (base64, written to config\assets by EnsureAssets) ============
IconB64() {
    return "
(Join
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
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
iVBORw0KGgoAAAANSUhEUgAAAKgAAAA4CAYAAABpLbP3AAANxUlEQVR4nO2dfZBU1ZnGn/ece2/f7p4vkc8lVWutKYSeZAhiTBQXRWGz61rJlqaJVlkmy7qD
CwsBgm7WRHqaaKhSIiACQsVErN3STLtb2UTZbNhCIoJgZNG4tLAbk7ClwUXmi5np7tv3nvPuH7e7GQzz0TM9Q7bn/v6aqZk+9zz3Pn0+3nPOe4GAgICAgICA
gICAgICAgID/H9BwP5hIJES6sZFix48Pu4wy0MlkUo/BdUqMB30tjWnCpNio6tsP4Kb90DRW+hKJhEgkEmJMLnYhFI/H5WhfZDzoYx57fcyg1tby9ZX17YnH
4zKVSikAWL364elK4lpo3eRpDWKu6DeRidgwDBBwCkIf2fLounf8OrTKVGqxquS1ilS7vtbWuFy82Nd38serpyuoa7VCk6c9MFNl9TGzbRsg0CkBHLnqti3v
fLQOQ2HIlSreuOXLEzNkyNygoRca0qgjQQCXU9IQYQBEADNcN+8KId9Qnkpu25L4t0QiISrdJVa7Pm6NS1qcUkeeWz6jrkZuUFovtENmnSFHtzHVmtGbzXtC
ip/n8t76uXds/wknEmKoXf6Qbnvx4S37amKJZVqbSIg613MhhYQQovIPrwgDzAylPAghQCTgufnNT25uWV1o7bT/XyOj2vUVzXk0tWxJNGxtMk1R15vJQzEr
MI+4/EEgIpIR2wQDyOa8zZ+6/cnVhZZ0UH2D3vpSy7Jy3ZdD4cgzjpNjKSUppfMAH2DwYWZ4o/U9ZKBJCDnPMIzJrpt3I5Eas6ene+eOJ5L39e2Sh0u16yt2
qf+RWv7l+rrQM5lsHp7SHogkjd5X73dgQBGAiQ0Reaa9Z+fVX9xx31C6+wErWOhqeOXK9R+HQW9qZktKaSilDmlG8/bN645XVEU/3Pe1xGQLxiNSGPfm3XzO
tsN2Jttz544t638wkjHbeNDX0pLkYy+u/HhI402Gtl1Pg4guxSQQzGAieA21ttnWlblz7hd3/KDYuvf3GWOgAtPpNAHQHryNISMcgfKgtDrc3f7uLbt3787F
460yFhvdMEw63chPfWfxGQB/vWLV+oxlWSsdx9ECYtOS++/f873HFvcATACV3VVVu77GxjQRQR97wdsYrrUjXT05j4gGfOajCRGImWU252opxKZXf7hkD77w
vR5mENHFu/oBKsuUSpFqXvXgNEFygee5DEEZ183fs3v37lwi8bKRTC7wRktMX4phn3T67TVTPtZ4C5FsNELWNOT4RgAvxuMpmUqhzFamuvX5Dz2l3vin5mlC
ipt7MnkGaNTDWBfWgcEMEBGKMQIiErm8p2qioWleBjcS4UVujUvg4q1ov019PJ4SAGDAnGcYRq2UBmnXPbzziYf/Ox6Py7F6eABQmNGKVCqltObnDdMAgRhE
nwOA4bRy1a4PqbgAAAFjXtQ2a5RmTTR2Y06tGSHLQG3UgmEQtL6ggWRDEBuMzwHAQIsF/Rq0eFOI0URCgARBkHgNAMVio7v6cDHS6UY/MCPFEa0UmJkA/mTh
z2WHZKpdX/GhE1GTH0oa9dl6CWagNmrhV+914uXX/wcd5xzURKySSYmIPMUEhq/vpv71DToeIaJS08uAhwqEPUYAg4R7/lcacUC76vVVoIxyUJoRDZt49sf/
iW3PH0PW8TDl8iha/mYerp89HT2ZPITwv/8sBh+2DDqb4z4rKFzh1ZThoLXuU4eR12c86RttlGLU14RwNP0BHv3+6yACGmpD+LA9g5YdB/FBWy9MU5RCr8SD
DzkuSbghoPrQmmGaAmc7s3j82TcQsiQMKZB3NeqiFv63rRcnft0G2zKhy+ijAoMGjBhmQAiCHTLwza2v4O1fnkHYNqA0Qwgg7yqEQwb+YFINXE+hnFX/wKAB
FYARDhn41s5DOHjsfVxWZ0Op0oQIWcfDsi/NwVVXTEDO8SDKcGhg0IAR4SmN+lob/7gnjef2pFFXY5XMaUiBznM53H1bI/7q9iZ0956fIA2VwKABw8ZTGhMb
Ithz4FfY+MzrmNAQhubz5jzbmcGtf3wl1n7lWnScy5XVcha5ZMteAZeeC4LnhLIMpBSjJmLhaPoDbPjuawhZEsz+eFRKQk8mj7mxqXjw3s/CyXv+dH0Y8YTA
oOMUZt9gzAwhCJ7SyOa8IXXBWjPCtoGznVl8beM+nOvNI2wb0NovK5vzMLEhgu+svRm1UWvI5V6MwKDjEGYgbJt46cC7+NHLv0QkbOIrX/gEmmZMQk+vCyn7
NxMzwzQEnLzC2o0v42xnFtGICaX8HR+upxGyDGxcexMmNoTRmxm4vMEIDDrO0JpRG7Xw/E9OIPnUqwhZBjxP4/Avfovt31iEaxqnoqMrB8O4yPSk0IVblsS3
tx/E0Xc+wOX1YXhKg8g/IJDPKzy47LOYO2sq2rqyGOmO/WCSNI5gBgxDoL0rh2d+9DZqwhZqI2YhLKSx5rF9ePPkGTTU2fDU7y6PK2ZMaAjj8Wd/jtTeEyVz
Av74tb0zizX3fBrxRTMrYk4gMOi4gwhwPQUnryClgNIMT2lYlkR3Jo8VG/4db/3XGTTUno9lAv6kqK7GwnN70viHl9KY0MecUhLO9eRx160x3P3nMbRXyJxA
YNBxBRHguhqTJkTxJ9ddgfauLGTBSFr7wfbeoklPnimNLT2l0VAXwsFj7+NbOw8hHDJK6+l+rNPBvDnT8dDS65F1PFAFD4gGBh1nEBFyjodVd1+Du/5sFto7
s6VJjNIM2zbQ3ZvHmo370NaZRciSiIZNpN9twze2vgI7ZEAIKoWTunsdxK6ciEdWzEfO8aA1l7WUORiBQccZRH5ryQwkl92AL/3pLLR35s6bVDEiYQNtnVms
fmwfnLyHTM7DQ9sOoONcDqYpSuGkvOuvIq1fdgMuq7PhunrY4aT+CGbx4xDfpBq9WRcPLb0eAPD8v76DCfU2lGYoxYhGTLx18gxWP7YPDODEr9tQXxsqhJN8
Iyulsen+mzHzjyagqzsPYwThpP4IDDpOIfK76Uwfk76w9yTqa0LwlIZSjIbaEI6dOAMAqKsJXbABJOe4+GbzdZgbm4rO7lzFJkUfJejixzGFxCbIZF2sW3o9
5n1quh8eKsRAVWHiFA4ZpWVRQwq0d2Vx920x3HVrDF3dzqiZEwgMOu4pjkmzjoeHV8zH1bOmoPPc+RZRM1+wAaStK4v4oplYc8+n/QlWhcecHyUwaIC/Fu/5
O9+3fn0hZs+Y7HfbfVaTDCn8DSCzpuKBv/wM8vnCxuNRPlAyqEGJzp8G/H04s8N8wZmdER9wq3Z9zENL+CCEv7E4GrGw9e8XYvZVk9HWkYUQ5Mc6ux1c3hDG
xrULYFkShQwlI6zb4AcUh9CCkln6yT8BeUkfIpHocwrzfN1GUGJ16yMMuQwp/BhpTcTClgduwc2f+UPkHA9dPQ5mz5iEJ76+EJfX2/6u+BF27b4zedC6DTqL
Z+A3KGSIAPMnAXA6nR7zo7mx2HFiZvrb1YlPCOlvEyPQKcBP8TLccqtV3/7ST/ybwgRnSGUUTRqNWNj8wM146+QZZHIe5sycjIhtojfrVmDcyWwIApGvD2gs
P3FDMtmiAcDT8meu5zlKeSBpzG9u/rv6WCzGY5yFmE6fPk1ExKxxu1YaBIAE7wWA48fLT7RQ7fr27y/k32TvZxnHc8pJGOaPSRVyjoc5M6fghqs/BkGE3qxb
kUC85kKiKUl7/br2nzll0Ox2APBhJx8xzdA1JAh5x/n+9i3JJQBTc/NSo6OjQwPxEVf64qRQzPKRTCa9ZV9NLLGs0NOu62oAjgvnyl2bv316uMm1ql0fc0K0
tAB/0fThkWgkdE1vNq8IKCs/UykbiKhM3hxmsCGJGex0KPfKG+/YdXqg5GEDXrOUO3NNcpEpzZ+6rps3LctSefcJJ/Pe2l27drkDfb6SrFiz/l4p5JOu8mDb
4VAu05vctiXZMpL0hNWur5h/8xf/snyRbZo/zeZcTzPkWOZo+ijM7E6oj5jtXdnknDu2tQyWfnHICWyXrVy3KVpTt6o30+OErFDIdZ3jmpGS4NdcP2UMiETF
xm6yMJtlRpMQ8lZpyEWu67q2HTZzuexhN/Pb+dOmTVPJZAsPp3UZL/pKCWxfWLZp0oToqrMdvR4IgjC2OUILM3bvsjrb7OzOHT7yoTu/uXmaApLcX+sJDG3g
TPF4q0ilFqvlq5JP2ba91HFyIBIwDANaj27qHyEktNbwPBe2HUE+7xzMsPf5pzclOwqJ3kdqmqrXx61xQYtT6q1/Xv5UXa29NJN1kfeUIvY711FLwQ+guC9P
CGHU19royTgHu3KZz18Xf7oDAAYyJ8qoFyUSCUomk3rl6vV3QogNQogr/PVcXUYx5cJ+1lMASulzrNWmQ6+8/8jRo7vc4Y7L+qHq9XEiQZRM6rd/uPJOKbHB
NOQVhhQX3TlfSaTwHZjLu91a4/FDLx16ZOmuo+5A484LKl7OxYpvn1iy5P7acEPtAkm0QGndxJpBFUh01RcGsb+ZVpwi4gMsvb1bH02+5/+RCVSxh1divOh7
9btLahumhBcQywVKc5PSClTp19AQs2VIEOGUZjqgXN47+46t7wHF5LqjlEUwHm8d0yy9F147LjHKgfRq18fDeJlWpWhtjUsuU99wbwbF462ikAR2VPuIPq8j
HMvXBVa1PmYQUnGxf1KMbhogeWxFSKVp/6QY7d8/9q97DAgICAgICAgICAgICAgIGEv+Dwvqj4JQKFFdAAAAAElFTkSuQmCC
)"
}

CbLightB64() {
    return "
(Join
iVBORw0KGgoAAAANSUhEUgAAAKgAAAA4CAYAAABpLbP3AAAN2UlEQVR4nO2de3BU133Hv79zH3t3Vy8ewhB3pp46g0FK5GAcJzYuRjYkreuJOyaSIXVxTG3J
gdo1lHrSOK60SV0mMTVOIGAppGHcxtgru+MmhqahBSUYDI4pJi4yuHnRxo8i9Nbu3tc5v/5xd8Wj6L0S09X9/LWa0Z5zvvd+9zx+59zfBUJCQkJCQkJCQkJC
QkJCQv5/QGP9YkNDg6isrKTy8vIxlzESWlsBoFUlEgk1kfVczFTQ11jZRiivmFh9AJa0QtFk6WtoaBANzGJSKjsPZqaaZFKb6Hqmgj7mhsugD5RM1oxa36h+
PclkUqutrZUAsH1n8koN2g3Kl1VKKTBzXn+JzMymaUEQnWbBRx649663L25Dvil8fTVabW2LBIBTP1h3pYS8QUlU+coHM+Vdn2XpINBpARy55o5vvH1xG0bC
iBuVu3BbmnfNjRjmRiXlUsMwS4SY2B8jM8NxHU8T2hu+7yXW1K34l4aGBpHvIbHQ9XGyRqPaFnlk19q5JUXaRqnUUitilOjaxOpTipHKuL7QxE9t1//KwuXb
fsgNDWKkQ/6IDJq7eVubnlttRaKbhRAlrutA1w0ITYDGPpUdFqUUfN+DEBqEILiu+/QXHrh7XbZNCgCPt45C15cz59GWNavjUXOzYYiSVNqFZJZgHnf5w0BE
pMUsAwwgY/tPf+yureuyPemw+oa98gM9S9Nz9xbFi3dm0inWdYN833MBHABwmJn9/Gi5GAFAVWmatsgwzFm2Y3ulJWVGT3dn09oHP/dgPobDwtcXDKn/3rL2
3tKSyM50xoUvlQ8ijcaxSB4tDEgCMLMspp3p7G+67rPbHxzJcD9kA4OhppG3b3/pw1oEbyqlTF03dF96h3zp1/1p3edO5FXFIGzb9tIsPcJP6IZxv23bdryo
yOrv7V2x9sGVL4znJk4FfY2NCT72ysMfjii8yVCW5ysQ0aQvkgCAGUwEv6zYMjp60isWfnb7C7nefbDv6EMVWFlZSQAppe3aFNFjMd/34fve4ff/O3VbInGf
nUwmtRMnymnJkrxrARCEKCrb27m2dvkZAA9s35FMW5b1sJ1JKwjavGPHy3tqau7sZ2YiolEPVYWvr42IoI696G+KFluxnn7bJ6Ih7/lEQgRiZi1je0oTYvOr
L6/egzv/rp8ZRHTpoX7QxmYvimxq+vs5ikS16zoshJa2PW9VInGfvX//fr26utoHgERioiQFNDCLRgC1tS3rqz9l36YJUWlFrDnpVOYWInolGYRnRtXLFL4+
EFGLfOOlujlCE7f2p10GaMLDWBe2gcEMEBFyMQIiErbry6J4ZI6fxi1EeIWTNRpw6V500K6+paVFAICntEWmGSk2DIMcxzn8yBf+6D+TyaSWu3mTQYJItba2
ipaWWgkpnzfNCIiIhU6fBoCxBNMLXR9aagQACOiL4pZRJBUrmsjV3kUoxYiYOorjJnSdoNQFHSTrglhnfBoAhtosGNSguYtCAlVCiNwq8zUwT/juyqVob29n
ACRZP+L7PpgVseKPAkBr65JRh2QKXV/uphNRVRBKmvDV+gDMQHHcxC9/0439r/8XunodFMXMAZMSEfmSCYyPAgCWYFB9w06WicRA18vMPsYwF8ojrOvSy/1B
ROMOaBe8Poy/jNEgFSNq6Xj2B/+BVY/txp99/d+w6rHdOHT83QtMCgAshp+2DGvQ83dQiPK72zAWlDrXBsb4d3emkr6JRkpGaVEER9s+wNe/+zqIgLLiCNo7
02jcfhAfdKRgGGIg9Eo8/JTjsoQbQgoPpRiGIXC2O4Onnn0DEVODrgm4nkJJ3MT/dKRw8lcdsEwDahRjVGjQkHHDDAhBsCI6vrzlJ3jr52cQtXRIxRACcD2J
aETHh8qL4PkSoxmnQoOG5AFGNKLjq02HcPDYu5hWYkHKgQURMo6PNXcvwDVXTYft+BCjcGho0JBx4UuF0mIL39vThl172lBSZA6YU9cEuntt3HNHJf7krir0
pVwIMbopcWjQkDHjS4WZZTHsOfBLbNr5OqaXRaH4nDnPdqdx++9ejQ2fvwFdvfaoes4cl23bK+Tyc0HwnDAqA0nJKIqZONr2ATbueA0RUwNzMB/VNEJ/2sXC
itn40v2fhOP6wXJ9DPGE0KBTFObAYMwMIQi+VMjY/oiGYJWNdZ7tzuDPN+1Db8pF1NKhVFBWxvYxsyyGv91wK4rj5ojLvRShQacgzEDUMrD7wC/w/f0/Ryxq
4PN3fgRVc8vRn/KgaYObiZlh6AKOK7Fh036c7c4gHjMgZXDiw/MVIqaOTRuWYGZZFKn00OUNR2jQKYZSjOK4ied/eBKJZ15FxNTh+wqHf/Yetj22DNdXzkZX
jw1dv8TyJDuEm6aGv9l2EEff/gAzSqPwpQIRQAS4rsSX1nwSC+fPRkdPBuM9sR8ukqYQzICuC3T22Nj5/bdQFDVRHDOyYSGF9U/uw5unzqCsxIIv/+/2uGTG
9LIonnr2p2jZe3LAnEAwf+3szmD9qo+jZtm8vJgTCA065SACPF/CcSU0TUAqhi8VTFNDX9rFQxv/FcffOYOy4nOxTCBYFJUUmdi1pw3/sLsN088zp6YRevtd
rLy9Avf8QQU682ROIDTolIII8DyF8ulxfOrGq9DZk4GWNZJSQbA9lTPpqTMDc0tfKpSVRHDw2Lv4atMhRCP6wH56EOt0sGjBlXi8/iZkHB/5PNIQGnSKQUSw
HR+P3HM9Vv7+fHR2ZwYWMVIxLEtHX8rF+k370NGdQcTUEI8aaPtFBx7b8hNYER1C0EA4qS/loOLqmXjiocWwHR9K8ai2MocjNOgUgyjoLZmBxJqbcffvzUdn
t33OpJIRi+ro6M5g3ZP74Lg+0raPx791AF29NgxDDISTXC/YRfrKmpsxrcSC56kxh5MGI1zFT0ECkyqkMh4er78JAPD8P7+N6aUWpGJIyYjHDBw/dQbrntwH
BnDyVx0oLY5kw0mBkaVU2PwXt2Le70xHT58LfRzhpMEIDTpFIQqG6fR5Jn1x7ymUFkXgSwUpGWXFERw7eQYAUFIUueAAiO14+HLdjVhYMRvdfXbeFkUXEw7x
UxgiDJj0r+pvwqKPXRmEh7IxUJldOEUj+sC2qK4JdPZkcM8dFVh5ewV6+pwJMycQGnTKk5uTZhwff/3QYlw3/wp0957rERXzBQdAOnoyqFk2D+tXfTxYYOV5
znkxoUFDgr14Pzj5vuWLS3Ht3FnBsH3ebpKuieAAyPzZePS+T8B1swePJ/iBkpE8k8Tnfb7sz+xIqc61gfOQt6jg9Y3sIUAhgoPF8ZiJLX+5FNdeMwsdXRkI
QUGss8/BjLIoNm2ohmlqyGYoGWfbhtc3gh5UGLlPwVOGl/cmapp+3pOAbAz+nyOlwPURRlyGJoIYaVHMxDcevQ23fuK3YTs+evodXDu3HN/84lLMKLWCU/Hj
HNoDZw6vb9hVvCD8OuhkGMFzzMTt7ZP3jHWO8vJyYmba3rTrI5puAawgiE4DQGXl2AeaQtXXOvCJf51d4IyojJxJ4zETTz96K46fOoO07WPBvFmIWQZSGS8P
805mXRAoqw+oHH3ihtbWVgUApOSPPddxPM+DpmuLm5qSpSdOgHlysxDTO+8UExExE92lpA+AwER7AaC8vHX0N7Dg9WXzb7L/47TjO6NJGBbMSSVsx8eCeVfg
5ut+C4IIqYyXl0C8YgTzDi3Q19p6YtBCh8luxwJoxKwPzTtiRiLXCxJw7Mx319SvXM3M1NzcrE+bNm1Cc4/nkndVV1f7W5ueWx21ot9xXVcB5GSUc/X6+j9+
f6zJtQpdH3ODaGwE/rCq/Ug8Frk+lXElAaPKzzSQDUTkJ28OM1jXiBnsdEnv6luWN78/VPKwIevMpf7b/u3kMtM0f+Q4thuxLNN13W8K2bWhvr7eG+r7+aTp
28n7NUPf6vke4rGiSF9fb2Jt/crG8aQnLHx9Qf7Nn/3T2mWWYfwoY3u+YmiTmaPpYpjZm14aMzp7MokFy7/VOFz6xREnsN3a9L3NZaUzHunt7XIsKxaxncwJ
MFo0wa9JFSR4ZRZ5m7sR5cYSVaUJ7XZN15e5ruPF40VGfzp1WFfdi997r042NoLH0rvkKHx92QS2L67ZXD49/sjZrpQPgiBMbo7Q7Irdn1ZiGd199uEj7d7i
uro5EkjwYL0nMLKJMyWTSVFbWyu3Nb/wTDwer89k0iASMEwD0p/Y1D+apkFKCc9zES8qhp1JH+xX/Jn199d0AcB4bl6WgtfHyRpBtS3y+D+ufaak2KpPZzy4
vpTEweDKyH84c6DMbBhPCKGXFlvoTzsHe+z0Z26s+U5W3zhTgOf+r6GhgRKJhGrakVwhdG2jIO0qIoJilc3hnu+FL4ERTE4IgO/LXma1+eiRvU80Nzd7Y52X
DVZZoevjhgaiREK99fLDKzQNGw1du0rXxCVPzucTTQQOtF2vTyk8dWj3oSfqm496Q807L2j4aCrLvX3ia1/bUVw2Y1o1BFezUlVSSnCef4QEsKbrEESnFasD
Qmp76+qW/wYYSD6b91DQVNH36o7VxWVXRKuJtWqpuEoqCcr3a2iI2dQ1EOG0YjogPd577fItWX0jM+eYSE7Cy6aGqXtCJ/iFro/H8DKtfJFM1mij/aGP6WIw
M7W0tIgTJ8oJGENy1RHTiMrKSgrqmbzXBRa+PhBaakRreQUtGSJ5bF5oaaPW8gpqbcWkv+4xJCQkJCQkJCQkJCQkJCRkMvlfZTTYPxDoOMUAAAAASUVORK5C
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

FlagB64(c) {
    if (c = "cs")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAABvElEQVR42s2YPUtCURjHz9vV640Sq6U1aKxJF1uajJaKIHAsyIaGgqClEoIa+gD1AQoJitZqCzJqKSP6AmJyFS2v2HX0nKfhQmGYL9fLPT6c+fDjx/P8n8PBkcgs6qViCKG0f/JwbWZhahwhxLmglMiimZ6eIwih3MfX4nZiaf+8YJiUEi4EAMhiIggh1cMGB7TTm1Q4dnx5+0YJwRhzLqQBCQAuxLC/r1iuRuNnywcXBaMqS9Vvu9S48Cos0O87uX4Ox45kqarr315Q1WCg5KpqPOESVTWLHCmqWmSg+6raCmU3VbW7JVxT1dnaaqYKwIHTKVBDVUXDpJQgjB041ra3UZYq1askrp7uXtN76/PRiREKwrq02+eHvRIArMbVoUDOqKZiG2HxbnV4V0SjYzaBKADHuKRowYoez94HTb0sqAMtbQ+IgTCp1wO1zezjaj7lgVqJ+ih1ZtaYTTGmvptJBk29wtQq8VBwLJBYV2IUjYGgjuYQ60YMA+eTmvWImLaA3BTTGshlMc2ApIj5F0iWmAZAcsX8BZIupg4IEP5UtJCp72SSIUli6oAIgq3sw0r+RaKYn8K99h3zDUdy4kUbCE0JAAAAAElFTkSuQmCC"
    if (c = "pl")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAAV0lEQVR42mN0c/NjGEyAhYGBYefOjYPENe7u/kwMgwyMOmjUQaMOGnXQqINGHTTqIBo0P+6K2g4W5xgJjUbZqINGHTTqoFEHjTpo1EEjofmRZSQ0eBwEAHwWBkHb25DwAAAAAElFTkSuQmCC"
    if (c = "de")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAAUUlEQVR42u3YQQ0AIAwEwStBCWL6xAcOUIkDvPBHwRF2FUxyjyaNzC6rrECZvcgsQIAAfQeqkraNZjAZIECAAL1xOtqy4UwmAwQIEKC7cHvHHMs0Bldf+x2dAAAAAElFTkSuQmCC"
    return "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"
}

DiscordB64() {
    return "
(Join
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
)"
}

DiscordHovB64() {
    return "
(Join
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
AAAAAElFTkSuQmCC
)"
}

; ===== TRANSLATIONS (generated by i18n/gen_tables.py - edit the JSON files, not this block) =====
TrCs() {
    m := Map()
    m["Dark mode"] := "Tmavý režim"
    m["All macros"] := "Všechna makra"
    m["Search (name, key or application)"] := "Hledat (název, klávesa nebo aplikace)"
    m["Name"] := "Název"
    m["Key"] := "Klávesa"
    m["Application"] := "Aplikace"
    m["Type"] := "Typ"
    m["Add"] := "Přidat"
    m["Copy"] := "Kopírovat"
    m["Edit"] := "Upravit"
    m["Delete"] := "Smazat"
    m["Export..."] := "Exportovat..."
    m["Import..."] := "Importovat..."
    m["Move up"] := "Nahoru"
    m["Move down"] := "Dolů"
    m["Export all..."] := "Exportovat vše..."
    m["All macros toggle key:"] := "Přepínač všech maker:"
    m["Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."] := "Zaškrtnutím makra ho zapneš. Dvojklikem na řádek ho upravíš. Tažením myší přes řádky (nebo Ctrl / Shift+klik) vybereš více maker. Kliknutím na záhlaví sloupce seřadíš seznam. Soubory .ahk přetažené do okna se naimportují; vybraná makra přetažená ze seznamu ven (na plochu, do složky, do chatu) se exportují. Zavřením okna aplikace zůstane běžet v oznamovací oblasti (pravým tlačítkem na ikonu → Exit)."
    m["Backup..."] := "Záloha..."
    m["Uninstall"] := "Odinstalovat"
    m["Open window"] := "Otevřít okno"
    m["Check for updates..."] := "Zkontrolovat aktualizace..."
    m["Check for updates at start"] := "Kontrolovat aktualizace při spuštění"
    m["Uninstall..."] := "Odinstalovat..."
    m["Exit"] := "Exit"
    m["Delete macro `"{1}`"?"] := "Smazat makro `"{1}`"?"
    m["Delete {1} selected macros?"] := "Smazat vybraná makra ({1})?"
    m["Cancel"] := "Zrušit"
    m["All macros: {1}"] := "Všechna makra: {1}"
    m["ON"] := "ZAP"
    m["OFF"] := "VYP"
    m["Move + actions"] := "Pohyb + akce"
    m["Sequence"] := "Sekvence"
    m["Script (.ahk)"] := "Skript (.ahk)"
    m["(everywhere)"] := "(všude)"
    m["Select a macro first."] := "Nejdřív vyber makro."
    m["Choose a folder for the {1} exported macros"] := "Vyber složku pro exportovaná makra ({1})"
    m["{1} macro(s) exported to:`n{2}"] := "Exportovaná makra ({1}) uložena do:`n{2}"
    m["Set a trigger key for this macro first."] := "Nejdřív nastav tomuto makru spouštěcí klávesu."
    m["Nothing to export (script file is missing)."] := "Není co exportovat (chybí soubor skriptu)."
    m["Export macro"] := "Exportovat makro"
    m["AutoHotkey scripts (*.ahk)"] := "Skripty AutoHotkey (*.ahk)"
    m["Exported to:`n{1}"] := "Exportováno do:`n{1}"
    m["There are no macros to export."] := "Nejsou žádná makra k exportu."
    m["Choose a folder for the exported macros"] := "Vyber složku pro exportovaná makra"
    m["Import macros"] := "Importovat makra"
    m["Drop .ahk files to import them"] := "Pusť soubory .ahk pro import"
    m["Can't read:`n{1}"] := "Nelze přečíst:`n{1}"
    m["Import anyway?"] := "Přesto importovat?"
    m["This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work."] := "Tento skript nemá řádek „#Requires AutoHotkey v2“.`nSpustí se pomocí AutoHotkey v2 – skripty pro v1 nebudou fungovat."
    m["Import anyway"] := "Přesto importovat"
    m["Macro Manager setup"] := "Instalace Macro Manageru"
    m["Macro Manager is already installed"] := "Macro Manager je už nainstalovaný"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Nainstalováno v:`n{1}`n`nAktualizovat ho tímto souborem a spustit, nebo jen spustit nainstalovanou kopii?"
    m["Just start"] := "Jen spustit"
    m["Update and start"] := "Aktualizovat a spustit"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Nainstalovanou kopii se nepodařilo aktualizovat (neběží?). Spouští se nainstalovaná verze.`n`n{1}"
    m["Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there."] := "Vyber, kam se má Macro Manager nainstalovat.`nVytvoří se tam složka 'MacroManager'."
    m["Installation failed:`n{1}"] := "Instalace se nezdařila:`n{1}"
    m["Create a Start Menu shortcut?"] := "Vytvořit zástupce v nabídce Start?"
    m["Skip"] := "Přeskočit"
    m["Create"] := "Vytvořit"
    m["Create a Desktop shortcut?"] := "Vytvořit zástupce na ploše?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Nainstalováno do:`n{1}`n`nTvoje makra a nastavení jsou uložena v:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "Tohle nevypadá jako nainstalovaná kopie, nic se neodstranilo."
    m["Uninstall Macro Manager"] := "Odinstalovat Macro Manager"
    m["Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "Odinstalovat Macro Manager?`n`nTím se trvale smaže celá složka včetně všech maker a nastavení:`n{1}"
    m["Export all your macros to a folder before uninstalling?"] := "Exportovat všechna makra do složky před odinstalací?"
    m["Don't export"] := "Neexportovat"
    m["Export first"] := "Nejdřív exportovat"
    m["Choose a folder for the backup"] := "Vyber složku pro zálohu"
    m["Macro Manager has been uninstalled.`nThe folder will be removed in a moment."] := "Macro Manager byl odinstalován.`nSložka bude za chvilku odstraněna."
    m["New macro"] := "Nové makro"
    m["Edit macro"] := "Upravit makro"
    m["Profiles"] := "Profily"
    m["Trigger key"] := "Spouštěcí klávesa"
    m["Toggle"] := "Přepínač"
    m["Only in app (exe)"] := "Jen v aplikaci (exe)"
    m["Select"] := "Vybrat"
    m["Run"] := "Spouštění"
    m["Once per key press"] := "Jednou na stisk klávesy"
    m["Repeat while key is held"] := "Opakovat při držení klávesy"
    m["Directions (optional)"] := "Směry (volitelné)"
    m["Record"] := "Nahrát"
    m["Actions in order"] := "Akce v pořadí"
    m["Delays (ms)"] := "Prodlevy (ms)"
    m["dir↓ → action↓"] := "směr↓ → akce↓"
    m["action↓ → dir↑"] := "akce↓ → směr↑"
    m["dir↑ → action↑"] := "směr↑ → akce↑"
    m["between cycles"] := "mezi cykly"
    m["Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4)."] := "Směry prázdné = jen akce (prodleva 2 = doba držení, prodleva 4 = pauza). Nahrát: stiskni klávesy, pak Hotovo. Klávesy držené současně se spojí pomocí + (např. Shift+4)."
    m["One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"] := "Jeden krok na řádek: down|up|tap klávesa prodleva_ms   (např. down A 25,  tap Shift+4 10)"
    m["Runs as its own process while this macro is checked (AutoHotkey v2)."] := "Běží jako samostatný proces, dokud je toto makro zaškrtnuté (AutoHotkey v2)."
    m["This macro is in several profiles ({1})."] := "Toto makro je v několika profilech ({1})."
    m["Apply the change to all of them, or only to the current profile ({1})? The other profiles then keep the old, unchanged version."] := "Použít změnu ve všech, nebo jen v aktuálním profilu ({1})? Ostatní profily si pak ponechají starou, nezměněnou verzi."
    m["Only in `"{1}`""] := "Jen v „{1}“"
    m["All profiles"] := "Všechny profily"
    m["Paste or write a script first."] := "Nejdřív vlož nebo napiš skript."
    m["Enter a trigger key."] := "Zadej spouštěcí klávesu."
    m["Save"] := "Uložit"
    m["Saving the settings failed: {1}"] := "Uložení nastavení se nezdařilo: {1}"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makro `"{1}`" nelze zapnout (klávesa `"{2}`"):`n{3}"
    m["Same trigger key"] := "Stejná spouštěcí klávesa"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}“ používá stejnou spouštěcí klávesu ({2}) jako aktivní makro „{3}“. Fungovat bude jen jedno z nich."
    m["Turn on anyway"] := "Přesto zapnout"
    m["Same trigger key as `"{1}`" - only one of them works"] := "Stejná spouštěcí klávesa jako „{1}“ – funguje jen jedno z nich"
    m["starts other programs or commands"] := "spouští jiné programy nebo příkazy"
    m["connects to the internet or downloads files"] := "připojuje se k internetu nebo stahuje soubory"
    m["deletes files or folders"] := "maže soubory nebo složky"
    m["writes, copies or moves files"] := "zapisuje, kopíruje nebo přesouvá soubory"
    m["changes the Windows registry"] := "mění registr Windows"
    m["calls Windows functions directly"] := "volá funkce Windows napřímo"
    m["reads what you type or the clipboard"] := "čte, co píšeš, nebo schránku"
    m["closes programs or shuts the PC down"] := "zavírá programy nebo vypíná počítač"
    m["loads code from other files"] := "načítá kód z jiných souborů"
    m["calls commands by a computed name (can hide what it does)"] := "volá příkazy podle vypočteného názvu (může skrývat, co dělá)"
    m["Imported script"] := "Importovaný skript"
    m["Turn on `"{1}`"?"] := "Zapnout „{1}“?"
    m["This script was imported. It runs with administrator rights, so it can do anything on this PC. Only turn it on if you trust the person it came from."] := "Tento skript byl importován. Běží s právy správce, takže může na tomto počítači udělat cokoli. Zapni ho, jen pokud věříš tomu, od koho pochází."
    m["Found in the code - the script:"] := "Nalezeno v kódu – skript:"
    m["No risky commands were found. This is only a quick check, not a guarantee."] := "Nebyly nalezeny žádné rizikové příkazy. Je to jen rychlá kontrola, ne záruka."
    m["Show the code"] := "Zobrazit kód"
    m["Turn on"] := "Zapnout"
    m["Script file for `"{1}`" is missing."] := "Chybí soubor skriptu pro `"{1}`"."
    m["Script macros need AutoHotkey v2 installed (not found)."] := "Skriptová makra potřebují nainstalovaný AutoHotkey v2 (nebyl nalezen)."
    m["New version {1} available - click to update"] := "Je dostupná nová verze {1} - klikni pro aktualizaci"
    m["Up to date (v{1}) - click to check again"] := "Aktuální (v{1}) - klikni pro novou kontrolu"
    m["Done"] := "Hotovo"
    m["none"] := "žádná"
    m["Press a key or mouse button...   (Esc = cancel, Backspace = none)"] := "Stiskni klávesu nebo tlačítko myši...   (Esc = zrušit, Backspace = žádná)"
    m["Press a key or mouse button...   (Esc = cancel)"] := "Stiskni klávesu nebo tlačítko myši...   (Esc = zrušit)"
    m["Profile: {1}"] := "Profil: {1}"
    m["{1} profiles"] := "Profily: {1}"
    m["New profile..."] := "Nový profil..."
    m["Rename current..."] := "Přejmenovat aktuální..."
    m["Delete current"] := "Smazat aktuální"
    m["New profile"] := "Nový profil"
    m["Name of the new profile:"] := "Název nového profilu:"
    m["A profile with this name already exists."] := "Profil s tímto názvem už existuje."
    m["Rename profile"] := "Přejmenovat profil"
    m["New name for profile `"{1}`":"] := "Nový název profilu `"{1}`":"
    m["You can't delete the last profile."] := "Poslední profil nelze smazat."
    m["Delete profile `"{1}`"?`n`nMacros that belong only to this profile are moved to the first remaining profile."] := "Smazat profil `"{1}`"?`n`nMakra, která patří jen do tohoto profilu, se přesunou do prvního zbývajícího profilu."
    m["Profiles of this macro"] := "Profily tohoto makra"
    m["The macro is active in the selected profiles:"] := "Makro je aktivní ve vybraných profilech:"
    m["Select at least one profile."] := "Vyber aspoň jeden profil."
    m["OK"] := "OK"
    m["Select application"] := "Vybrat aplikaci"
    m["Use one of the currently running applications, or browse for the .exe file?"] := "Vybrat z právě spuštěných aplikací, nebo najít soubor .exe?"
    m["Browse for the .exe"] := "Najít soubor .exe"
    m["Running applications"] := "Spuštěné aplikace"
    m["No running applications found - choose the file instead."] := "Nebyly nalezeny žádné spuštěné aplikace - vyber raději soubor."
    m["Double-click an application:"] := "Dvojklikni na aplikaci:"
    m["Browse..."] := "Procházet..."
    m["Select the application"] := "Vyber aplikaci"
    m["Applications (*.exe)"] := "Aplikace (*.exe)"
    m["Could not check for updates. Check your internet connection and try again."] := "Nepodařilo se zkontrolovat aktualizace. Zkontroluj připojení k internetu a zkus to znovu."
    m["Updates"] := "Aktualizace"
    m["You have the latest version (v{1})."] := "Máš nejnovější verzi (v{1})."
    m["`n`nUpdate now? The app restarts. Your macros, profiles and settings are not changed."] := "`n`nAktualizovat teď? Aplikace se restartuje. Tvoje makra, profily a nastavení zůstanou beze změny."
    m["Macro Manager update"] := "Aktualizace Macro Manageru"
    m["Version {1} is available (you have v{2})."] := "Je dostupná verze {1} (máš v{2})."
    m["Later"] := "Později"
    m["Update now"] := "Aktualizovat"
    m["The download failed. Try again later."] := "Stahování se nezdařilo. Zkus to znovu později."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Stažený soubor neodpovídá očekávanému kontrolnímu součtu (nová verze se možná ještě nahrává). Nic se nezměnilo - zkus to znovu za pár minut.`n`nOčekáváno: {1}...`nPřijato: {2}  ({3} bajtů)"
    m["(could not compute)"] := "(nelze vypočítat)"
    m["The downloaded file is not a valid Macro Manager script. Nothing was changed."] := "Stažený soubor není platný skript Macro Manageru. Nic se nezměnilo."
    m["Could not replace the app file: {1}"] := "Nepodařilo se nahradit soubor aplikace: {1}"
    m["Version {1}"] := "Verze {1}"
    m["hlp_start"] := "Macro Manager za tebe spouští makra na klávesové zkratky. Každé makro má spouštěcí klávesu; dokud ji držíš (ve vybrané aplikaci), makro se přehrává.`n`n- Zaškrtnutím makra v seznamu ho zapneš, odškrtnutím vypneš.`n- Přepínač Všechna makra v horní liště zapne nebo vypne všechna makra najednou.`n- Tmavý režim přepíná vzhled aplikace.`n- Tlačítko jazyka v horní liště přepíná jazyk aplikace (English, Čeština, Polski, Deutsch). Aplikace se kvůli tomu restartuje.`n- Dvojklikem na řádek (nebo tlačítkem Upravit) makro změníš. Přidat vytvoří nové, Kopírovat ho zduplikuje, Smazat ho odstraní.`n- Chceš-li vybrat více maker, táhni myší přes řádky (nebo Ctrl / Shift + klik). Kopírovat, Smazat, Exportovat, Nahoru / Dolů i přetažení ven z okna fungují na všech vybraných řádcích.`n- Zavřením okna aplikace zůstane běžet v oznamovací oblasti. Po kliknutí pravým tlačítkem na ikonu v oznamovací oblasti najdeš Otevřít okno / Odinstalovat / Exit.`n- Aplikace vždy běží jako správce, takže makra fungují i ve hrách spuštěných se zvýšenými oprávněními.`n- Pole pro hledání nad seznamem zobrazí jen makra, jejichž název, klávesa nebo aplikace obsahuje zadaný text. Křížek vedle něj hledání zruší."
    m["hlp_edit"] := "Název - libovolný text, zobrazuje se v seznamu.`nProfily - do kterých profilů makro patří (může jich být víc).`nSpouštěcí klávesa - klikni do pole a stiskni klávesu nebo tlačítko myši (pravé, prostřední, boční tlačítka X1 / X2, kolečko myši). Pro kombinaci při stisku drž Ctrl / Shift / Alt, například Ctrl+XButton1. Esc zruší výběr.`nPřepínač - volitelná klávesa, která toto makro zapíná/vypíná bez otevření okna. Backspace ji smaže.`nJen v aplikaci (exe) - makro funguje, jen když je daný program v popředí. Tlačítkem Vybrat vybereš spuštěnou aplikaci nebo najdeš soubor .exe. Prázdné = funguje všude.`nTyp - Pohyb + akce, Sekvence nebo Skript (.ahk). Viz další témata.`nSpouštění - Jednou na stisk klávesy: přehraje jeden průchod a čeká, dokud klávesu nepustíš. Opakovat při držení klávesy: přehrává dokola, dokud klávesu nepustíš (zastaví se okamžitě).`n`nUložit makro uloží, Zrušit zahodí změny."
    m["hlp_move"] := "Určeno pro hry, kde se neustále pohybuješ (například A a D) a mezitím sesíláš kouzla.`n`nSměry - pohybové klávesy v pořadí, například: a,d`nAkce v pořadí - klávesy ke stisknutí, jedna na cyklus, například: 1,2,1,F7,1,F8`n`nKaždý cyklus proběhne takto, s prodlevami, které nastavíš:`n  1. směr dolů`n  2. (prodleva 1) akce dolů`n  3. (prodleva 2) směr nahoru`n  4. (prodleva 3) akce nahoru`n  5. (prodleva 4) pauza, pak další směr + další akce`n`nSeznamy se po dojetí na konec opakují od začátku. Pokud jsou Směry prázdné, mačkají se jen akce: doba držení = prodleva 2, pauza = prodleva 4.`nPokud hra makro ignoruje, zvyš prodlevy (běžně se používá 20-30 ms)."
    m["hlp_seq"] := "Volný seznam kroků. Piš jeden krok na řádek:`n`n  down KEY PAUSE   - stiskne a drží klávesu`n  up KEY PAUSE     - pustí klávesu`n  tap KEY PAUSE    - stiskne a hned pustí`n`nPAUSE je čekání po kroku v milisekundách (prázdné = 0).`n`nPříklad - rychlé střídání A / D:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nPříklad - útok a kouzla:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nPříklad - dvě klávesy najednou:`n  tap Shift+4 50`n`nPři Spouštění = Opakovat se řádky přehrávají ve smyčce, dokud držíš spouštěcí klávesu; při Jednou se přehrají jen jednou.`nKlávesy, které jsou při puštění spouštěcí klávesy stále stisknuté, se uvolní automaticky."
    m["hlp_script"] := "Pro všechno, co ostatní typy neumí. Vlož nebo napiš vlastní skript AutoHotkey v2.`n`n- Skript běží jako samostatný proces, dokud je makro zaškrtnuté, a po odškrtnutí se zastaví.`n- Musí to být kód AutoHotkey v2 (skripty pro v1 nebudou fungovat).`n- Spouštěcí klávesa a filtr aplikace se nepoužívají, to si řeší tvůj skript sám.`n- Importované soubory .ahk, které nevytvořil Macro Manager, se stanou skriptovými makry.`n- Importovaný skript se před prvním spuštěním zeptá: běží s právy správce, takže ho zapni, jen pokud věříš, odkud pochází. Okno ukáže, co skript dělá (například spouští programy nebo maže soubory), a nabídne zobrazení kódu."
    m["hlp_keys"] := "Názvy kláves odpovídají názvům v AutoHotkey: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nKlávesu lze zapsat i jako scan kód, například sc002 - jde o fyzickou klávesu bez ohledu na rozložení. Klávesy jako čárka, plus, & a | se takto ukládají automaticky.`n`nMyš: spouštěcí klávesa, přepínač i klávesa Všechna makra může být také tlačítko myši: RButton, MButton (klik kolečkem), XButton1 / XButton2 (dvě boční tlačítka) nebo samotné kolečko (WheelUp / WheelDown / WheelLeft / WheelRight). Kolečko nelze držet, proto se makra na kolečku vždy přehrají jednou. Levé tlačítko se nenabízí.`nHerní / MMO myši: Windows zná jen pět tlačítek myši, další boční tlačítka obsluhuje software myši (G HUB, Synapse, iCUE, ...). Nastav jim tam klávesy, nejlépe F13 - F24 (nebo Ctrl+Alt+číslo); Macro Manager je pak vidí jako obyčejné klávesy, takže klikni do pole spouštěcí klávesy a stiskni boční tlačítko.`n`nNahrát (vedle Směrů a Akcí): stiskni Nahrát, mačkej klávesy v požadovaném pořadí a pak stiskni Hotovo. Pole se plní průběžně. Během nahrávání jsou makra pozastavená.`n`nKlávesy současně: klávesy, které držíš zároveň, se uloží jako jeden krok spojený pomocí +, například Shift+4. Při přehrávání se všechny stisknou společně a společně se i uvolní (ne nejdřív Shift a pak 4).`nStejně to funguje i při psaní do polí: a,Shift+4,d"
    m["hlp_profiles"] := "Profily udržují různé sady maker odděleně (například jeden na hru).`n`n- Tlačítko profilu v horní liště ukazuje aktuální profil. Kliknutím přepneš profil nebo vytvoříš / přejmenuješ / smažeš profil.`n- Seznam ukazuje jen makra aktuálního profilu a jen ta jsou aktivní.`n- V editoru můžeš v Profily vybrat pro makro jeden nebo více profilů. Když změníš makro, které patří do více profilů, aplikace se zeptá: použít změnu ve všech, nebo jen v aktuálním profilu (ostatní profily si ponechají starou verzi).`n- Zaškrtnutí makra je ve všech profilech stejné; přepnutím profilu se jen mění, která makra jsou ve hře.`n- Smazáním profilu se makra, která patřila jen jemu, přesunou do prvního zbývajícího profilu."
    m["hlp_toggle"] := "Přepínač (v editoru) - klávesa, která zapíná / vypíná jedno konkrétní makro, stejně jako jeho zaškrtnutí v seznamu. Malý tooltip ukáže ZAP / VYP.`nPřepínač všech maker (tlačítko pod seznamem) - přepíná hlavní vypínač. Funguje ve všech profilech.`n`nKlikni na tlačítko a stiskni klávesu. Esc zruší, Backspace klávesu odstraní.`nMakra z jiných profilů na své přepínací klávesy nereagují."
    m["hlp_order"] := "Nahoru / Dolů mění pořadí v seznamu. Kliknutím na záhlaví sloupce se seznam seřadí (dalším kliknutím se pořadí obrátí).`n`nExportovat... uloží vybrané makro jako samostatný soubor .ahk pro AutoHotkey v2, který běží i sám (požádá o práva správce).`nImportovat... načte jeden nebo více souborů .ahk (nebo je stačí přetáhnout do hlavního okna). Makro můžeš také přetáhnout ze seznamu na plochu / do složky / do okna chatu a exportovat ho tak jako soubor .ahk. Makro se pojmenuje podle souboru; soubory vytvořené Macro Managerem se vrátí jako upravitelná makra, ostatní skripty se stanou skriptovými makry. Importy jdou do aktuálního profilu a začínají vypnuté.`nExportovat vše... zapíše všechna makra do složky, každé do jednoho souboru.`n`nZáloha... (vedle Odinstalovat) uloží všechno – makra, profily, nastavení i soubory skriptů – do jednoho souboru .mmbackup a obnoví ho na novém PC nebo po přeinstalaci. Soubor zálohy můžeš také přetáhnout do okna. Před obnovou se současný stav uloží jako config\backup-before-restore.mmbackup.`n`nOdinstalovat smaže celou složku aplikace včetně všech maker a nastavení. Nejdřív nabídne export všech maker."
    m["hlp_updates"] := "Ikona šipky v horní liště (vedle tlačítka profilu) ukazuje, jestli existuje nová verze: šedá = máš aktuální verzi, zelená = je dostupná nová verze. Po najetí myší uvidíš podrobnosti.`n`nAplikace kontroluje několik sekund po spuštění (lze vypnout v nabídce v oznamovací oblasti: Kontrolovat aktualizace při spuštění). Kliknutím na ikonu můžeš kdykoli zkontrolovat znovu. Nic se nenainstaluje, dokud neklikneš na zelenou ikonu a nepotvrdíš.`n`nPři aktualizaci aplikace stáhne nový soubor, zkontroluje jeho kontrolní součet, starý ponechá jako Macro Manager.ahk.bak a restartuje se. Tvoje makra, profily a nastavení jsou uložené zvlášť ve složce config a zůstanou přesně tak, jak jsou.`n`nKdyž se něco pokazí, zavři aplikaci, smaž Macro Manager.ahk a přejmenuj Macro Manager.ahk.bak zpět na Macro Manager.ahk.`n`nAktualizace potřebuje přístup k internetu na github.com."
    m["hlp_tips"] := "- Hra nic nedělá: zkus zvýšit prodlevy, ověř, že Jen v aplikaci (exe) odpovídá hře (použij Vybrat), a nech aplikaci běžet jako správce.`n- Postava běží jedním směrem: ve Směrech drž dvojice směrů (a,d) a prodlevu mezi cykly nastav malou, ale ne 0.`n- Makro se nespustí: zkontroluj, že je zaškrtnuté, Všechna makra je zapnuté, makro je v aktuálním profilu a spouštěcí klávesa je nastavená (není nedefinovaná).`n- Dvě makra se stejnou spouštěcí klávesou: funguje jen jedno z nich - použij různé klávesy nebo různé profily.`n- Zaseknutá klávesa po přerušení: jednou ji stiskni a pusť; aplikace při zastavení makra uvolní klávesy, které stiskla.`n- Nastavení a skripty jsou ve složce config vedle aplikace."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Discord se nepodařilo otevřít. Odkaz je zkopírovaný do schránky - vlož ho do prohlížeče:`n`n{1}"
    m["Help"] := "Nápověda"
    m["For support click here"] := "Podpora: klikni sem"
    m["Close"] := "Zavřít"
    m["Set a trigger key first: {1}"] := "Nejdřív nastav spouštěcí klávesu: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Přetažení makra ven se nezdařilo:`n{1}"
    m["Backup"] := "Záloha"
    m["Backup and restore"] := "Záloha a obnova"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Ulož všechna makra, profily a nastavení (včetně souborů skriptů) do jednoho souboru zálohy – pro nový počítač nebo přeinstalaci. Nebo je z takového souboru obnov."
    m["Restore..."] := "Obnovit..."
    m["Create backup..."] := "Vytvořit zálohu..."
    m["Create backup"] := "Vytvořit zálohu"
    m["Macro Manager backup (*.mmbackup)"] := "Záloha Macro Manageru (*.mmbackup)"
    m["Backup saved to:`n{1}"] := "Záloha uložena do:`n{1}"
    m["The backup could not be saved:`n{1}"] := "Zálohu se nepodařilo uložit:`n{1}"
    m["Restore from backup"] := "Obnovit ze zálohy"
    m["This is not a Macro Manager backup file:`n{1}"] := "Tohle není soubor zálohy Macro Manageru:`n{1}"
    m["Restore this backup?"] := "Obnovit tuto zálohu?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Všechna současná makra, profily a nastavení se nahradí zálohou z {1} ({2} maker). Aplikace se restartuje.`n`nSoučasný stav se nejdřív uloží jako:`n{3}"
    m["Restore"] := "Obnovit"
    m["The backup could not be restored:`n{1}"] := "Zálohu se nepodařilo obnovit:`n{1}"
    m["Release notes"] := "Poznámky k verzi"
    m["Getting started"] := "Začínáme"
    m["Add / edit a macro"] := "Přidání / úprava makra"
    m["Keys and recording"] := "Klávesy a nahrávání"
    m["Toggle keys"] := "Přepínací klávesy"
    m["Order, export, backup"] := "Pořadí, export, záloha"
    m["Tips and problems"] := "Tipy a problémy"
    return m
}
TrPl() {
    m := Map()
    m["Dark mode"] := "Tryb ciemny"
    m["All macros"] := "Wszystkie makra"
    m["Search (name, key or application)"] := "Szukaj (nazwa, klawisz lub aplikacja)"
    m["Name"] := "Nazwa"
    m["Key"] := "Klawisz"
    m["Application"] := "Aplikacja"
    m["Type"] := "Typ"
    m["Add"] := "Dodaj"
    m["Copy"] := "Kopiuj"
    m["Edit"] := "Edytuj"
    m["Delete"] := "Usuń"
    m["Export..."] := "Eksportuj..."
    m["Import..."] := "Importuj..."
    m["Move up"] := "W górę"
    m["Move down"] := "W dół"
    m["Export all..."] := "Eksportuj całość..."
    m["All macros toggle key:"] := "Klawisz przełączania wszystkich makr:"
    m["Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."] := "Zaznacz makro, aby je włączyć. Kliknij dwukrotnie wiersz, aby edytować. Przeciągnij myszą po wierszach (lub Ctrl / Shift+kliknięcie), aby zaznaczyć kilka. Kliknij nagłówek kolumny, aby posortować. Upuść pliki .ahk na okno, aby je zaimportować; przeciągnij zaznaczone makra z listy (na pulpit, do folderu, na czat), aby je wyeksportować. Zamknięcie okna zostawia aplikację w zasobniku systemowym (kliknij ikonę prawym przyciskiem → Zamknij)."
    m["Backup..."] := "Kopia..."
    m["Uninstall"] := "Odinstaluj"
    m["Open window"] := "Otwórz okno"
    m["Check for updates..."] := "Sprawdź aktualizacje..."
    m["Check for updates at start"] := "Sprawdzaj aktualizacje przy starcie"
    m["Uninstall..."] := "Odinstaluj..."
    m["Exit"] := "Zamknij"
    m["Delete macro `"{1}`"?"] := "Usunąć makro `"{1}`"?"
    m["Delete {1} selected macros?"] := "Usunąć zaznaczone makra ({1})?"
    m["Cancel"] := "Anuluj"
    m["All macros: {1}"] := "Wszystkie makra: {1}"
    m["ON"] := "WŁ."
    m["OFF"] := "WYŁ."
    m["Move + actions"] := "Ruch + akcje"
    m["Sequence"] := "Sekwencja"
    m["Script (.ahk)"] := "Skrypt (.ahk)"
    m["(everywhere)"] := "(wszędzie)"
    m["Select a macro first."] := "Najpierw wybierz makro."
    m["Choose a folder for the {1} exported macros"] := "Wybierz folder dla eksportowanych makr ({1})"
    m["{1} macro(s) exported to:`n{2}"] := "Wyeksportowano makra ({1}) do:`n{2}"
    m["Set a trigger key for this macro first."] := "Najpierw ustaw klawisz wyzwalający dla tego makra."
    m["Nothing to export (script file is missing)."] := "Nie ma czego eksportować (brak pliku skryptu)."
    m["Export macro"] := "Eksportuj makro"
    m["AutoHotkey scripts (*.ahk)"] := "Skrypty AutoHotkey (*.ahk)"
    m["Exported to:`n{1}"] := "Wyeksportowano do:`n{1}"
    m["There are no macros to export."] := "Nie ma makr do wyeksportowania."
    m["Choose a folder for the exported macros"] := "Wybierz folder dla eksportowanych makr"
    m["Import macros"] := "Importuj makra"
    m["Drop .ahk files to import them"] := "Upuść pliki .ahk, aby je zaimportować"
    m["Can't read:`n{1}"] := "Nie można odczytać:`n{1}"
    m["Import anyway?"] := "Zaimportować mimo to?"
    m["This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work."] := "Ten skrypt nie ma wiersza „#Requires AutoHotkey v2”.`nZostanie uruchomiony przez AutoHotkey v2 – skrypty v1 nie zadziałają."
    m["Import anyway"] := "Importuj mimo to"
    m["Macro Manager setup"] := "Instalator Macro Manager"
    m["Macro Manager is already installed"] := "Macro Manager jest już zainstalowany"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Zainstalowano w:`n{1}`n`nZaktualizować go tym plikiem i uruchomić, czy tylko uruchomić zainstalowaną kopię?"
    m["Just start"] := "Tylko uruchom"
    m["Update and start"] := "Zaktualizuj i uruchom"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Nie udało się zaktualizować zainstalowanej kopii (czy jest uruchomiona?). Uruchamiam zainstalowaną wersję.`n`n{1}"
    m["Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there."] := "Wybierz, gdzie zainstalować Macro Manager.`nZostanie tam utworzony folder 'MacroManager'."
    m["Installation failed:`n{1}"] := "Instalacja nie powiodła się:`n{1}"
    m["Create a Start Menu shortcut?"] := "Utworzyć skrót w menu Start?"
    m["Skip"] := "Pomiń"
    m["Create"] := "Utwórz"
    m["Create a Desktop shortcut?"] := "Utworzyć skrót na pulpicie?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Zainstalowano w:`n{1}`n`nTwoje makra i ustawienia są przechowywane w:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "To nie wygląda na zainstalowaną kopię, nic nie zostało usunięte."
    m["Uninstall Macro Manager"] := "Odinstaluj Macro Manager"
    m["Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "Odinstalować Macro Manager?`n`nTo trwale usunie cały folder, razem ze wszystkimi makrami i ustawieniami:`n{1}"
    m["Export all your macros to a folder before uninstalling?"] := "Wyeksportować wszystkie makra do folderu przed odinstalowaniem?"
    m["Don't export"] := "Nie eksportuj"
    m["Export first"] := "Najpierw eksportuj"
    m["Choose a folder for the backup"] := "Wybierz folder na kopię zapasową"
    m["Macro Manager has been uninstalled.`nThe folder will be removed in a moment."] := "Macro Manager został odinstalowany.`nFolder zostanie za chwilę usunięty."
    m["New macro"] := "Nowe makro"
    m["Edit macro"] := "Edytuj makro"
    m["Profiles"] := "Profile"
    m["Trigger key"] := "Klawisz wyzwalający"
    m["Toggle"] := "Przełącznik"
    m["Only in app (exe)"] := "Tylko w apce (exe)"
    m["Select"] := "Wybierz"
    m["Run"] := "Uruchamiaj"
    m["Once per key press"] := "Raz na naciśnięcie klawisza"
    m["Repeat while key is held"] := "Powtarzaj, gdy klawisz jest wciśnięty"
    m["Directions (optional)"] := "Kierunki (opcjonalne)"
    m["Record"] := "Nagraj"
    m["Actions in order"] := "Akcje po kolei"
    m["Delays (ms)"] := "Opóźnienia (ms)"
    m["dir↓ → action↓"] := "kier↓ → akcja↓"
    m["action↓ → dir↑"] := "akcja↓ → kier↑"
    m["dir↑ → action↑"] := "kier↑ → akcja↑"
    m["between cycles"] := "między cyklami"
    m["Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4)."] := "Puste Kierunki = tylko akcje (opóźnienie 2 = czas przytrzymania, opóźnienie 4 = pauza). Nagraj: naciśnij klawisze, potem Gotowe. Klawisze wciśnięte razem są łączone znakiem + (np. Shift+4)."
    m["One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"] := "Jeden krok w linii: down|up|tap klawisz opóźnienie_ms   (np. down A 25,  tap Shift+4 10)"
    m["Runs as its own process while this macro is checked (AutoHotkey v2)."] := "Działa jako osobny proces, dopóki to makro jest zaznaczone (AutoHotkey v2)."
    m["This macro is in several profiles ({1})."] := "To makro jest w kilku profilach ({1})."
    m["Apply the change to all of them, or only to the current profile ({1})? The other profiles then keep the old, unchanged version."] := "Zastosować zmianę we wszystkich, czy tylko w bieżącym profilu ({1})? Pozostałe profile zachowają wtedy starą, niezmienioną wersję."
    m["Only in `"{1}`""] := "Tylko w „{1}”"
    m["All profiles"] := "Wszystkie profile"
    m["Paste or write a script first."] := "Najpierw wklej lub napisz skrypt."
    m["Enter a trigger key."] := "Podaj klawisz wyzwalający."
    m["Save"] := "Zapisz"
    m["Saving the settings failed: {1}"] := "Nie udało się zapisać ustawień: {1}"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makra `"{1}`" nie można włączyć (klawisz `"{2}`"):`n{3}"
    m["Same trigger key"] := "Ten sam klawisz wyzwalający"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}” używa tego samego klawisza wyzwalającego ({2}) co aktywne makro „{3}”. Działać będzie tylko jedno z nich."
    m["Turn on anyway"] := "Włącz mimo to"
    m["Same trigger key as `"{1}`" - only one of them works"] := "Ten sam klawisz wyzwalający co „{1}” – działa tylko jedno z nich"
    m["starts other programs or commands"] := "uruchamia inne programy lub polecenia"
    m["connects to the internet or downloads files"] := "łączy się z internetem lub pobiera pliki"
    m["deletes files or folders"] := "usuwa pliki lub foldery"
    m["writes, copies or moves files"] := "zapisuje, kopiuje lub przenosi pliki"
    m["changes the Windows registry"] := "zmienia rejestr Windows"
    m["calls Windows functions directly"] := "wywołuje funkcje Windows bezpośrednio"
    m["reads what you type or the clipboard"] := "odczytuje to, co piszesz, lub schowek"
    m["closes programs or shuts the PC down"] := "zamyka programy lub wyłącza komputer"
    m["loads code from other files"] := "wczytuje kod z innych plików"
    m["calls commands by a computed name (can hide what it does)"] := "wywołuje polecenia przez wyliczoną nazwę (może ukrywać, co robi)"
    m["Imported script"] := "Zaimportowany skrypt"
    m["Turn on `"{1}`"?"] := "Włączyć „{1}”?"
    m["This script was imported. It runs with administrator rights, so it can do anything on this PC. Only turn it on if you trust the person it came from."] := "Ten skrypt został zaimportowany. Działa z uprawnieniami administratora, więc może zrobić na tym komputerze wszystko. Włącz go tylko wtedy, gdy ufasz osobie, od której pochodzi."
    m["Found in the code - the script:"] := "Znaleziono w kodzie – skrypt:"
    m["No risky commands were found. This is only a quick check, not a guarantee."] := "Nie znaleziono ryzykownych poleceń. To tylko szybkie sprawdzenie, a nie gwarancja."
    m["Show the code"] := "Pokaż kod"
    m["Turn on"] := "Włącz"
    m["Script file for `"{1}`" is missing."] := "Brak pliku skryptu dla `"{1}`"."
    m["Script macros need AutoHotkey v2 installed (not found)."] := "Makra skryptowe wymagają zainstalowanego AutoHotkey v2 (nie znaleziono)."
    m["New version {1} available - click to update"] := "Dostępna nowa wersja {1} - kliknij, aby zaktualizować"
    m["Up to date (v{1}) - click to check again"] := "Masz aktualną wersję (v{1}) - kliknij, aby sprawdzić ponownie"
    m["Done"] := "Gotowe"
    m["none"] := "brak"
    m["Press a key or mouse button...   (Esc = cancel, Backspace = none)"] := "Naciśnij klawisz lub przycisk myszy...   (Esc = anuluj, Backspace = brak)"
    m["Press a key or mouse button...   (Esc = cancel)"] := "Naciśnij klawisz lub przycisk myszy...   (Esc = anuluj)"
    m["Profile: {1}"] := "Profil: {1}"
    m["{1} profiles"] := "Profile: {1}"
    m["New profile..."] := "Nowy profil..."
    m["Rename current..."] := "Zmień nazwę bieżącego..."
    m["Delete current"] := "Usuń bieżący"
    m["New profile"] := "Nowy profil"
    m["Name of the new profile:"] := "Nazwa nowego profilu:"
    m["A profile with this name already exists."] := "Profil o tej nazwie już istnieje."
    m["Rename profile"] := "Zmień nazwę profilu"
    m["New name for profile `"{1}`":"] := "Nowa nazwa profilu `"{1}`":"
    m["You can't delete the last profile."] := "Nie możesz usunąć ostatniego profilu."
    m["Delete profile `"{1}`"?`n`nMacros that belong only to this profile are moved to the first remaining profile."] := "Usunąć profil `"{1}`"?`n`nMakra należące tylko do tego profilu zostaną przeniesione do pierwszego pozostałego profilu."
    m["Profiles of this macro"] := "Profile tego makra"
    m["The macro is active in the selected profiles:"] := "Makro jest aktywne w zaznaczonych profilach:"
    m["Select at least one profile."] := "Zaznacz co najmniej jeden profil."
    m["OK"] := "OK"
    m["Select application"] := "Wybierz aplikację"
    m["Use one of the currently running applications, or browse for the .exe file?"] := "Wybrać spośród uruchomionych aplikacji czy wskazać plik .exe?"
    m["Browse for the .exe"] := "Wskaż plik .exe"
    m["Running applications"] := "Uruchomione aplikacje"
    m["No running applications found - choose the file instead."] := "Nie znaleziono uruchomionych aplikacji - wskaż plik."
    m["Double-click an application:"] := "Kliknij dwukrotnie aplikację:"
    m["Browse..."] := "Przeglądaj..."
    m["Select the application"] := "Wybierz aplikację"
    m["Applications (*.exe)"] := "Aplikacje (*.exe)"
    m["Could not check for updates. Check your internet connection and try again."] := "Nie udało się sprawdzić aktualizacji. Sprawdź połączenie z internetem i spróbuj ponownie."
    m["Updates"] := "Aktualizacje"
    m["You have the latest version (v{1})."] := "Masz najnowszą wersję (v{1})."
    m["`n`nUpdate now? The app restarts. Your macros, profiles and settings are not changed."] := "`n`nZaktualizować teraz? Aplikacja uruchomi się ponownie. Twoje makra, profile i ustawienia nie zostaną zmienione."
    m["Macro Manager update"] := "Aktualizacja Macro Manager"
    m["Version {1} is available (you have v{2})."] := "Dostępna jest wersja {1} (masz v{2})."
    m["Later"] := "Później"
    m["Update now"] := "Aktualizuj teraz"
    m["The download failed. Try again later."] := "Pobieranie nie powiodło się. Spróbuj ponownie później."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Pobrany plik nie zgadza się z oczekiwaną sumą kontrolną (nowa wersja może być jeszcze wgrywana). Nic nie zostało zmienione - spróbuj ponownie za kilka minut.`n`nOczekiwano: {1}...`nOtrzymano: {2}  ({3} B)"
    m["(could not compute)"] := "(nie udało się obliczyć)"
    m["The downloaded file is not a valid Macro Manager script. Nothing was changed."] := "Pobrany plik nie jest prawidłowym skryptem Macro Manager. Nic nie zostało zmienione."
    m["Could not replace the app file: {1}"] := "Nie udało się zastąpić pliku aplikacji: {1}"
    m["Version {1}"] := "Wersja {1}"
    m["hlp_start"] := "Macro Manager uruchamia za ciebie makra klawiszowe. Każde makro ma klawisz wyzwalający; dopóki go trzymasz (w wybranej aplikacji), makro jest odtwarzane.`n`n- Zaznacz makro na liście, aby je włączyć, odznacz, aby je wyłączyć.`n- Przełącznik Wszystkie makra w nagłówku włącza lub wyłącza wszystkie makra naraz.`n- Tryb ciemny zmienia wygląd aplikacji.`n- Przycisk języka w nagłówku zmienia język aplikacji (English, Čeština, Polski, Deutsch). Aplikacja uruchomi się ponownie, aby go zastosować.`n- Kliknij dwukrotnie wiersz (lub naciśnij Edytuj), aby zmienić makro. Dodaj tworzy nowe, Kopiuj je powiela, Usuń je kasuje.`n- Aby zaznaczyć kilka makr, przeciągnij myszą po wierszach (lub Ctrl / Shift + kliknięcie). Kopiuj, Usuń, Eksportuj, W górę / W dół oraz przeciąganie poza okno działają na wszystkich zaznaczonych wierszach.`n- Zamknięcie okna zostawia aplikację uruchomioną w zasobniku systemowym. Kliknij ikonę w zasobniku prawym przyciskiem, aby wybrać Otwórz okno / Odinstaluj / Zamknij.`n- Aplikacja zawsze działa jako administrator, więc makra działają też w grach uruchomionych z podwyższonymi uprawnieniami.`n- Pole wyszukiwania nad listą pokazuje tylko makra, których nazwa, klawisz lub aplikacja zawiera wpisany tekst. Krzyżyk obok czyści wyszukiwanie."
    m["hlp_edit"] := "Nazwa - dowolny tekst, widoczny na liście.`nProfile - do jakich profili należy makro (może być kilka).`nKlawisz wyzwalający - kliknij pole, potem naciśnij klawisz lub przycisk myszy (prawy, środkowy, boczne X1 / X2, kółko myszy). Przytrzymaj Ctrl / Shift / Alt podczas naciskania, aby uzyskać kombinację, na przykład Ctrl+XButton1. Esc anuluje.`nPrzełącznik - opcjonalny klawisz, który włącza/wyłącza to makro bez otwierania okna. Backspace go czyści.`nTylko w apce (exe) - makro działa tylko wtedy, gdy ten program jest na wierzchu. Naciśnij Wybierz, aby wskazać uruchomioną aplikację lub wskazać plik .exe. Puste = działa wszędzie.`nTyp - Ruch + akcje, Sekwencja lub Skrypt (.ahk). Zobacz kolejne tematy.`nUruchamiaj - Raz na naciśnięcie klawisza: odtwarza jeden przebieg i czeka, aż puścisz klawisz. Powtarzaj, gdy klawisz jest wciśnięty: odtwarza w kółko, dopóki nie puścisz klawisza (zatrzymuje się natychmiast).`n`nZapisz zapisuje makro, Anuluj odrzuca zmiany."
    m["hlp_move"] := "Stworzone dla gier, w których cały czas się poruszasz (np. A i D) i w międzyczasie rzucasz czary.`n`nKierunki - klawisze ruchu, po kolei, na przykład: a,d`nAkcje po kolei - klawisze do naciśnięcia, po jednym na cykl, na przykład: 1,2,1,F7,1,F8`n`nKażdy cykl wygląda tak, z ustawionymi przez ciebie opóźnieniami:`n  1. kierunek w dół`n  2. (opóźnienie 1) akcja w dół`n  3. (opóźnienie 2) kierunek w górę`n  4. (opóźnienie 3) akcja w górę`n  5. (opóźnienie 4) pauza, potem następny kierunek + następna akcja`n`nListy powtarzają się od początku, gdy się skończą. Jeśli Kierunki są puste, naciskane są tylko akcje: czas przytrzymania = opóźnienie 2, pauza = opóźnienie 4.`nJeśli gra ignoruje makro, zwiększ opóźnienia (20-30 ms to częsta wartość)."
    m["hlp_seq"] := "Dowolna lista kroków. Napisz jeden krok w linii:`n`n  down KEY PAUSE   - wciśnij i przytrzymaj klawisz`n  up KEY PAUSE     - puść klawisz`n  tap KEY PAUSE    - wciśnij i od razu puść`n`nPAUSE to czas oczekiwania po kroku w milisekundach (puste = 0).`n`nPrzykład - szybka zmiana A / D:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nPrzykład - atak i czary:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nPrzykład - dwa klawisze naraz:`n  tap Shift+4 50`n`nPrzy Uruchamiaj = Powtarzaj linie są odtwarzane w pętli, dopóki trzymasz klawisz wyzwalający; przy Raz odtwarzane są jeden raz.`nKlawisze, które nadal są wciśnięte, gdy puścisz klawisz wyzwalający, są puszczane automatycznie."
    m["hlp_script"] := "Do wszystkiego, czego nie potrafią inne typy. Wklej lub napisz własny skrypt AutoHotkey v2.`n`n- Skrypt działa jako osobny proces, dopóki makro jest zaznaczone, i jest zatrzymywany, gdy je odznaczysz.`n- Musi to być kod AutoHotkey v2 (skrypty v1 nie zadziałają).`n- Klawisz wyzwalający i filtr aplikacji nie są używane, twój skrypt robi to sam.`n- Zaimportowane pliki .ahk, które nie zostały utworzone przez Macro Manager, stają się makrami skryptowymi.`n- Zaimportowany skrypt pyta przed pierwszym uruchomieniem: działa z uprawnieniami administratora, więc włącz go tylko wtedy, gdy ufasz jego źródłu. Okno pokazuje, co robi skrypt (na przykład uruchamia programy lub usuwa pliki), i pozwala obejrzeć kod."
    m["hlp_keys"] := "Nazwy klawiszy to nazwy z AutoHotkey: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nKlawisz można też zapisać jako kod skanowania, na przykład sc002 - to fizyczny klawisz, niezależnie od układu. Klawisze takie jak przecinek, plus, & i | są zapisywane w ten sposób automatycznie.`n`nMysz: klawisz wyzwalający, przełącznik i klawisz Wszystkie makra mogą być też przyciskiem myszy: RButton, MButton (kliknięcie kółkiem), XButton1 / XButton2 (dwa przyciski boczne) lub samo kółko (WheelUp / WheelDown / WheelLeft / WheelRight). Kółko nie ma przytrzymania, więc makra na kółku zawsze odtwarzają się raz. Lewy przycisk nie jest dostępny.`nMyszy dla graczy / MMO: Windows zna tylko pięć przycisków myszy, dodatkowymi przyciskami bocznymi zajmuje się oprogramowanie myszy (G HUB, Synapse, iCUE, ...). Ustaw je tam na klawisze, najlepiej F13 - F24 (lub Ctrl+Alt+cyfra); Macro Manager widzi je wtedy jako zwykłe klawisze, więc kliknij pole klawisza wyzwalającego i naciśnij przycisk boczny.`n`nNagraj (obok Kierunków i Akcji): naciśnij Nagraj, naciskaj klawisze w żądanej kolejności, potem naciśnij Gotowe. Pole wypełnia się na żywo. Podczas nagrywania makra są wstrzymane.`n`nKlawisze jednocześnie: klawisze trzymane razem są zapisywane jako jeden krok połączony znakiem +, na przykład Shift+4. Przy odtwarzaniu makra wszystkie idą w dół razem i są puszczane razem (nie najpierw Shift, a potem 4).`nTo samo działa przy wpisywaniu w polach: a,Shift+4,d"
    m["hlp_profiles"] := "Profile oddzielają od siebie różne zestawy makr (na przykład jeden na grę).`n`n- Przycisk profilu w nagłówku pokazuje bieżący profil. Kliknij go, aby przełączyć profil albo utworzyć / zmienić nazwę / usunąć profil.`n- Lista pokazuje tylko makra bieżącego profilu i tylko one są aktywne.`n- W edytorze Profile pozwalają wybrać jeden lub kilka profili dla makra. Gdy zmieniasz makro należące do kilku profili, aplikacja pyta: zastosować zmianę we wszystkich, czy tylko w bieżącym profilu (pozostałe profile zachowają starą wersję).`n- Stan zaznaczenia makra jest taki sam w każdym profilu; zmiana profilu zmienia tylko to, które makra są w grze.`n- Usunięcie profilu przenosi makra, które należały tylko do niego, do pierwszego pozostałego profilu."
    m["hlp_toggle"] := "Przełącznik (w edytorze) - klawisz, który włącza / wyłącza to jedno makro, tak samo jak jego zaznaczenie na liście. Mała podpowiedź pokazuje WŁ. / WYŁ.`nKlawisz przełączania wszystkich makr (przycisk pod listą) - przełącza główny wyłącznik. Działa w każdym profilu.`n`nKliknij przycisk, naciśnij klawisz. Esc anuluje, Backspace usuwa klawisz.`nMakra z innych profili nie reagują na swoje klawisze przełączające."
    m["hlp_order"] := "W górę / W dół zmieniają kolejność na liście. Kliknięcie nagłówka kolumny sortuje listę (kliknij ponownie, aby odwrócić).`n`nEksportuj... zapisuje zaznaczone makro jako samodzielny plik AutoHotkey v2 .ahk, który działa też sam (poprosi o uprawnienia administratora).`nImportuj... wczytuje jeden lub więcej plików .ahk (albo po prostu przeciągnij je na główne okno). Możesz też przeciągnąć makro z listy na pulpit / do folderu / do okna czatu, aby wyeksportować je jako plik .ahk. Makro dostaje nazwę od pliku; pliki utworzone przez Macro Manager wracają jako edytowalne makra, inne skrypty stają się makrami skryptowymi. Importowane makra trafiają do bieżącego profilu i startują wyłączone.`nEksportuj całość... zapisuje każde makro do folderu, po jednym pliku.`n`nKopia... (obok Odinstaluj) zapisuje wszystko – makra, profile, ustawienia i pliki skryptów – do jednego pliku .mmbackup i przywraca go na nowym komputerze lub po ponownej instalacji. Plik kopii możesz też przeciągnąć na okno. Przed przywróceniem bieżący stan zostaje zapisany jako config\backup-before-restore.mmbackup.`n`nOdinstaluj usuwa cały folder aplikacji razem ze wszystkimi makrami i ustawieniami. Najpierw proponuje wyeksportowanie wszystkich makr."
    m["hlp_updates"] := "Ikona strzałki w nagłówku (obok przycisku profilu) pokazuje, czy jest nowa wersja: szara = masz aktualną wersję, zielona = dostępna jest nowa wersja. Najedź na nią, aby zobaczyć szczegóły.`n`nAplikacja sprawdza aktualizacje kilka sekund po uruchomieniu (można to wyłączyć w menu zasobnika systemowego: Sprawdzaj aktualizacje przy starcie). Kliknij ikonę w dowolnym momencie, aby sprawdzić ponownie. Nic nie zostanie zainstalowane, dopóki nie klikniesz zielonej ikony i nie potwierdzisz.`n`nPodczas aktualizacji aplikacja pobiera nowy plik, sprawdza jego sumę kontrolną, zachowuje stary jako Macro Manager.ahk.bak i uruchamia się ponownie. Twoje makra, profile i ustawienia są przechowywane osobno w folderze config i pozostają dokładnie takie, jakie są.`n`nJeśli coś pójdzie nie tak, zamknij aplikację, usuń Macro Manager.ahk i zmień nazwę Macro Manager.ahk.bak z powrotem na Macro Manager.ahk.`n`nAktualizacja wymaga dostępu do internetu i github.com."
    m["hlp_tips"] := "- Gra nic nie robi: spróbuj zwiększyć opóźnienia, upewnij się, że Tylko w apce (exe) pasuje do gry (użyj Wybierz) i zostaw aplikację uruchomioną jako administrator.`n- Postać biegnie w jedną stronę: trzymaj pary kierunków w Kierunkach (a,d), a opóźnienie między cyklami małe, ale nie 0.`n- Makro się nie uruchamia: sprawdź, czy jest zaznaczone, czy Wszystkie makra jest włączone, czy jest w bieżącym profilu i czy klawisz wyzwalający jest ustawiony (nie jest pusty).`n- Dwa makra z tym samym klawiszem wyzwalającym: działa tylko jedno z nich - użyj różnych klawiszy lub różnych profili.`n- Zablokowany klawisz po przerwaniu: naciśnij go i puść raz; aplikacja puszcza klawisze, które nacisnęła, gdy makro się zatrzymuje.`n- Ustawienia i skrypty leżą w folderze config obok aplikacji."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Nie udało się otworzyć Discorda. Link został skopiowany do schowka - wklej go w przeglądarce:`n`n{1}"
    m["Help"] := "Pomoc"
    m["For support click here"] := "Po pomoc kliknij tutaj"
    m["Close"] := "Zamknij"
    m["Set a trigger key first: {1}"] := "Najpierw ustaw klawisz wyzwalający: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Przeciągnięcie makra na zewnątrz nie powiodło się:`n{1}"
    m["Backup"] := "Kopia zapasowa"
    m["Backup and restore"] := "Kopia zapasowa i przywracanie"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Zapisz wszystkie makra, profile i ustawienia (łącznie z plikami skryptów) w jednym pliku kopii – na nowy komputer lub po ponownej instalacji. Albo przywróć je z takiego pliku."
    m["Restore..."] := "Przywróć..."
    m["Create backup..."] := "Utwórz kopię..."
    m["Create backup"] := "Utwórz kopię zapasową"
    m["Macro Manager backup (*.mmbackup)"] := "Kopia Macro Managera (*.mmbackup)"
    m["Backup saved to:`n{1}"] := "Kopię zapisano w:`n{1}"
    m["The backup could not be saved:`n{1}"] := "Nie udało się zapisać kopii:`n{1}"
    m["Restore from backup"] := "Przywróć z kopii"
    m["This is not a Macro Manager backup file:`n{1}"] := "To nie jest plik kopii Macro Managera:`n{1}"
    m["Restore this backup?"] := "Przywrócić tę kopię?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Wszystkie obecne makra, profile i ustawienia zostaną zastąpione kopią z {1} ({2} makr). Aplikacja uruchomi się ponownie.`n`nObecny stan zostanie najpierw zapisany jako:`n{3}"
    m["Restore"] := "Przywróć"
    m["The backup could not be restored:`n{1}"] := "Nie udało się przywrócić kopii:`n{1}"
    m["Release notes"] := "Release notes"
    m["Getting started"] := "Pierwsze kroki"
    m["Add / edit a macro"] := "Dodawanie / edycja makra"
    m["Keys and recording"] := "Klawisze i nagrywanie"
    m["Toggle keys"] := "Klawisze przełączające"
    m["Order, export, backup"] := "Kolejność i eksport"
    m["Tips and problems"] := "Wskazówki i problemy"
    return m
}
TrDe() {
    m := Map()
    m["Dark mode"] := "Dunkelmodus"
    m["All macros"] := "Alle Makros"
    m["Search (name, key or application)"] := "Suchen (Name, Taste oder Anwendung)"
    m["Name"] := "Name"
    m["Key"] := "Taste"
    m["Application"] := "Anwendung"
    m["Type"] := "Typ"
    m["Add"] := "Hinzufügen"
    m["Copy"] := "Kopieren"
    m["Edit"] := "Bearbeiten"
    m["Delete"] := "Löschen"
    m["Export..."] := "Exportieren..."
    m["Import..."] := "Importieren..."
    m["Move up"] := "Nach oben"
    m["Move down"] := "Nach unten"
    m["Export all..."] := "Alle exportieren..."
    m["All macros toggle key:"] := "Ein/Aus-Taste für alle Makros:"
    m["Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."] := "Hake ein Makro an, um es einzuschalten. Doppelklick auf eine Zeile zum Bearbeiten. Zieh die Maus über mehrere Zeilen (oder Ctrl / Shift+Klick), um mehrere auszuwählen. Klick auf eine Spaltenüberschrift zum Sortieren. Zieh .ahk-Dateien ins Fenster, um sie zu importieren; zieh ausgewählte Makros aus der Liste (Desktop, Ordner, Chat), um sie zu exportieren. Beim Schließen des Fensters läuft die App im Infobereich weiter (Rechtsklick auf das Symbol → Beenden)."
    m["Backup..."] := "Sicherung..."
    m["Uninstall"] := "Deinstall."
    m["Open window"] := "Fenster öffnen"
    m["Check for updates..."] := "Nach Updates suchen..."
    m["Check for updates at start"] := "Beim Start nach Updates suchen"
    m["Uninstall..."] := "Deinstallieren..."
    m["Exit"] := "Beenden"
    m["Delete macro `"{1}`"?"] := "Makro `"{1}`" löschen?"
    m["Delete {1} selected macros?"] := "{1} ausgewählte Makros löschen?"
    m["Cancel"] := "Abbrechen"
    m["All macros: {1}"] := "Alle Makros: {1}"
    m["ON"] := "AN"
    m["OFF"] := "AUS"
    m["Move + actions"] := "Bewegung + Aktionen"
    m["Sequence"] := "Sequenz"
    m["Script (.ahk)"] := "Skript (.ahk)"
    m["(everywhere)"] := "(überall)"
    m["Select a macro first."] := "Wähle zuerst ein Makro aus."
    m["Choose a folder for the {1} exported macros"] := "Wähle einen Ordner für die {1} exportierten Makros"
    m["{1} macro(s) exported to:`n{2}"] := "{1} Makro(s) exportiert nach:`n{2}"
    m["Set a trigger key for this macro first."] := "Lege zuerst eine Auslösetaste für dieses Makro fest."
    m["Nothing to export (script file is missing)."] := "Nichts zu exportieren (Skriptdatei fehlt)."
    m["Export macro"] := "Makro exportieren"
    m["AutoHotkey scripts (*.ahk)"] := "AutoHotkey-Skripte (*.ahk)"
    m["Exported to:`n{1}"] := "Exportiert nach:`n{1}"
    m["There are no macros to export."] := "Es gibt keine Makros zum Exportieren."
    m["Choose a folder for the exported macros"] := "Wähle einen Ordner für die exportierten Makros"
    m["Import macros"] := "Makros importieren"
    m["Drop .ahk files to import them"] := "Zieh .ahk-Dateien hierher, um sie zu importieren"
    m["Can't read:`n{1}"] := "Kann nicht gelesen werden:`n{1}"
    m["Import anyway?"] := "Trotzdem importieren?"
    m["This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work."] := "Dieses Skript hat keine Zeile „#Requires AutoHotkey v2“.`nEs wird mit AutoHotkey v2 ausgeführt – v1-Skripte funktionieren nicht."
    m["Import anyway"] := "Trotzdem importieren"
    m["Macro Manager setup"] := "Macro Manager Setup"
    m["Macro Manager is already installed"] := "Macro Manager ist bereits installiert"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Installiert in:`n{1}`n`nMit dieser Datei aktualisieren und starten oder nur die installierte Kopie starten?"
    m["Just start"] := "Nur starten"
    m["Update and start"] := "Aktualisieren und starten"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Die installierte Kopie konnte nicht aktualisiert werden (läuft sie noch?). Die installierte Version wird gestartet.`n`n{1}"
    m["Choose where to install Macro Manager.`nA 'MacroManager' folder will be created there."] := "Wähle, wo Macro Manager installiert werden soll.`nDort wird ein Ordner 'MacroManager' angelegt."
    m["Installation failed:`n{1}"] := "Installation fehlgeschlagen:`n{1}"
    m["Create a Start Menu shortcut?"] := "Verknüpfung im Startmenü erstellen?"
    m["Skip"] := "Überspringen"
    m["Create"] := "Erstellen"
    m["Create a Desktop shortcut?"] := "Verknüpfung auf dem Desktop erstellen?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Installiert in:`n{1}`n`nDeine Makros und Einstellungen liegen in:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "Das sieht nicht nach einer installierten Kopie aus, es wurde nichts entfernt."
    m["Uninstall Macro Manager"] := "Macro Manager deinstallieren"
    m["Uninstall Macro Manager?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "Macro Manager deinstallieren?`n`nDadurch wird der gesamte Ordner endgültig gelöscht, einschließlich aller Makros und Einstellungen:`n{1}"
    m["Export all your macros to a folder before uninstalling?"] := "Alle Makros vor dem Deinstallieren in einen Ordner exportieren?"
    m["Don't export"] := "Nicht exportieren"
    m["Export first"] := "Zuerst exportieren"
    m["Choose a folder for the backup"] := "Wähle einen Ordner für das Backup"
    m["Macro Manager has been uninstalled.`nThe folder will be removed in a moment."] := "Macro Manager wurde deinstalliert.`nDer Ordner wird gleich entfernt."
    m["New macro"] := "Neues Makro"
    m["Edit macro"] := "Makro bearbeiten"
    m["Profiles"] := "Profile"
    m["Trigger key"] := "Auslösetaste"
    m["Toggle"] := "Ein/Aus-Taste"
    m["Only in app (exe)"] := "Nur in App (exe)"
    m["Select"] := "Wählen"
    m["Run"] := "Ausführung"
    m["Once per key press"] := "Einmal pro Tastendruck"
    m["Repeat while key is held"] := "Wiederholen, solange Taste gehalten"
    m["Directions (optional)"] := "Richtungen (optional)"
    m["Record"] := "Aufnehmen"
    m["Actions in order"] := "Aktionen in Folge"
    m["Delays (ms)"] := "Verzögerungen (ms)"
    m["dir↓ → action↓"] := "Ri↓ → Aktion↓"
    m["action↓ → dir↑"] := "Aktion↓ → Ri↑"
    m["dir↑ → action↑"] := "Ri↑ → Aktion↑"
    m["between cycles"] := "zwischen Zyklen"
    m["Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4)."] := "Richtungen leer = nur Aktionen (Verzögerung 2 = Haltezeit, Verzögerung 4 = Pause). Aufnehmen: Tasten drücken, dann Fertig. Gleichzeitig gehaltene Tasten werden mit + verbunden (z. B. Shift+4)."
    m["One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"] := "Ein Schritt pro Zeile: down|up|tap Taste Verzögerung_ms   (z. B. down A 25,  tap Shift+4 10)"
    m["Runs as its own process while this macro is checked (AutoHotkey v2)."] := "Läuft als eigener Prozess, solange dieses Makro angehakt ist (AutoHotkey v2)."
    m["This macro is in several profiles ({1})."] := "Dieses Makro ist in mehreren Profilen ({1})."
    m["Apply the change to all of them, or only to the current profile ({1})? The other profiles then keep the old, unchanged version."] := "Die Änderung in allen übernehmen oder nur im aktuellen Profil ({1})? Die anderen Profile behalten dann die alte, unveränderte Version."
    m["Only in `"{1}`""] := "Nur in „{1}“"
    m["All profiles"] := "Alle Profile"
    m["Paste or write a script first."] := "Füge zuerst ein Skript ein oder schreibe eines."
    m["Enter a trigger key."] := "Gib eine Auslösetaste an."
    m["Save"] := "Speichern"
    m["Saving the settings failed: {1}"] := "Speichern der Einstellungen fehlgeschlagen: {1}"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makro `"{1}`" kann nicht aktiviert werden (Taste `"{2}`"):`n{3}"
    m["Same trigger key"] := "Gleiche Auslösetaste"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}“ verwendet dieselbe Auslösetaste ({2}) wie das aktive Makro „{3}“. Nur eines von beiden wird funktionieren."
    m["Turn on anyway"] := "Trotzdem einschalten"
    m["Same trigger key as `"{1}`" - only one of them works"] := "Gleiche Auslösetaste wie „{1}“ – nur eines von beiden funktioniert"
    m["starts other programs or commands"] := "startet andere Programme oder Befehle"
    m["connects to the internet or downloads files"] := "verbindet sich mit dem Internet oder lädt Dateien herunter"
    m["deletes files or folders"] := "löscht Dateien oder Ordner"
    m["writes, copies or moves files"] := "schreibt, kopiert oder verschiebt Dateien"
    m["changes the Windows registry"] := "ändert die Windows-Registrierung"
    m["calls Windows functions directly"] := "ruft Windows-Funktionen direkt auf"
    m["reads what you type or the clipboard"] := "liest, was du tippst, oder die Zwischenablage"
    m["closes programs or shuts the PC down"] := "schließt Programme oder fährt den PC herunter"
    m["loads code from other files"] := "lädt Code aus anderen Dateien"
    m["calls commands by a computed name (can hide what it does)"] := "ruft Befehle über einen berechneten Namen auf (kann verbergen, was es tut)"
    m["Imported script"] := "Importiertes Skript"
    m["Turn on `"{1}`"?"] := "„{1}“ einschalten?"
    m["This script was imported. It runs with administrator rights, so it can do anything on this PC. Only turn it on if you trust the person it came from."] := "Dieses Skript wurde importiert. Es läuft mit Administratorrechten und kann daher auf diesem PC alles tun. Schalte es nur ein, wenn du der Person vertraust, von der es stammt."
    m["Found in the code - the script:"] := "Im Code gefunden – das Skript:"
    m["No risky commands were found. This is only a quick check, not a guarantee."] := "Es wurden keine riskanten Befehle gefunden. Das ist nur eine schnelle Prüfung, keine Garantie."
    m["Show the code"] := "Code anzeigen"
    m["Turn on"] := "Einschalten"
    m["Script file for `"{1}`" is missing."] := "Die Skriptdatei für `"{1}`" fehlt."
    m["Script macros need AutoHotkey v2 installed (not found)."] := "Skript-Makros benötigen installiertes AutoHotkey v2 (nicht gefunden)."
    m["New version {1} available - click to update"] := "Neue Version {1} verfügbar - zum Aktualisieren klicken"
    m["Up to date (v{1}) - click to check again"] := "Aktuell (v{1}) - zum erneuten Prüfen klicken"
    m["Done"] := "Fertig"
    m["none"] := "keine"
    m["Press a key or mouse button...   (Esc = cancel, Backspace = none)"] := "Drücke eine Taste oder Maustaste...   (Esc = abbrechen, Backspace = keine)"
    m["Press a key or mouse button...   (Esc = cancel)"] := "Drücke eine Taste oder Maustaste...   (Esc = abbrechen)"
    m["Profile: {1}"] := "Profil: {1}"
    m["{1} profiles"] := "{1} Profile"
    m["New profile..."] := "Neues Profil..."
    m["Rename current..."] := "Aktuelles umbenennen..."
    m["Delete current"] := "Aktuelles löschen"
    m["New profile"] := "Neues Profil"
    m["Name of the new profile:"] := "Name des neuen Profils:"
    m["A profile with this name already exists."] := "Ein Profil mit diesem Namen existiert bereits."
    m["Rename profile"] := "Profil umbenennen"
    m["New name for profile `"{1}`":"] := "Neuer Name für Profil `"{1}`":"
    m["You can't delete the last profile."] := "Das letzte Profil kann nicht gelöscht werden."
    m["Delete profile `"{1}`"?`n`nMacros that belong only to this profile are moved to the first remaining profile."] := "Profil `"{1}`" löschen?`n`nMakros, die nur zu diesem Profil gehören, werden in das erste verbleibende Profil verschoben."
    m["Profiles of this macro"] := "Profile dieses Makros"
    m["The macro is active in the selected profiles:"] := "Das Makro ist in den ausgewählten Profilen aktiv:"
    m["Select at least one profile."] := "Wähle mindestens ein Profil aus."
    m["OK"] := "OK"
    m["Select application"] := "Anwendung auswählen"
    m["Use one of the currently running applications, or browse for the .exe file?"] := "Eine der laufenden Anwendungen verwenden oder die .exe-Datei suchen?"
    m["Browse for the .exe"] := ".exe-Datei suchen"
    m["Running applications"] := "Laufende Anwendungen"
    m["No running applications found - choose the file instead."] := "Keine laufenden Anwendungen gefunden - wähle stattdessen die Datei aus."
    m["Double-click an application:"] := "Doppelklick auf eine Anwendung:"
    m["Browse..."] := "Suchen..."
    m["Select the application"] := "Anwendung auswählen"
    m["Applications (*.exe)"] := "Anwendungen (*.exe)"
    m["Could not check for updates. Check your internet connection and try again."] := "Die Suche nach Updates ist fehlgeschlagen. Prüfe deine Internetverbindung und versuche es erneut."
    m["Updates"] := "Updates"
    m["You have the latest version (v{1})."] := "Du hast die neueste Version (v{1})."
    m["`n`nUpdate now? The app restarts. Your macros, profiles and settings are not changed."] := "`n`nJetzt aktualisieren? Die App wird neu gestartet. Deine Makros, Profile und Einstellungen bleiben unverändert."
    m["Macro Manager update"] := "Macro Manager Update"
    m["Version {1} is available (you have v{2})."] := "Version {1} ist verfügbar (du hast v{2})."
    m["Later"] := "Später"
    m["Update now"] := "Jetzt aktualisieren"
    m["The download failed. Try again later."] := "Der Download ist fehlgeschlagen. Versuche es später erneut."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Die heruntergeladene Datei stimmt nicht mit der erwarteten Prüfsumme überein (die neue Version wird möglicherweise noch hochgeladen). Es wurde nichts geändert - versuche es in ein paar Minuten erneut.`n`nErwartet: {1}...`nErhalten: {2}  ({3} Bytes)"
    m["(could not compute)"] := "(konnte nicht berechnet werden)"
    m["The downloaded file is not a valid Macro Manager script. Nothing was changed."] := "Die heruntergeladene Datei ist kein gültiges Macro Manager Skript. Es wurde nichts geändert."
    m["Could not replace the app file: {1}"] := "Die App-Datei konnte nicht ersetzt werden: {1}"
    m["Version {1}"] := "Version {1}"
    m["hlp_start"] := "Macro Manager führt Hotkey-Makros für dich aus. Jedes Makro hat eine Auslösetaste; solange du sie gedrückt hältst (innerhalb der gewählten Anwendung), läuft das Makro.`n`n- Hake ein Makro in der Liste an, um es einzuschalten, entferne den Haken, um es auszuschalten.`n- Der Schalter Alle Makros in der Kopfzeile schaltet alle Makros auf einmal ein oder aus.`n- Dunkelmodus wechselt das Aussehen der App.`n- Die Sprachschaltfläche in der Kopfzeile wechselt die App-Sprache (English, Čeština, Polski, Deutsch). Die App startet neu, um sie zu übernehmen.`n- Doppelklick auf eine Zeile (oder Bearbeiten) ändert ein Makro. Hinzufügen legt ein neues an, Kopieren dupliziert es, Löschen entfernt es.`n- Um mehrere Makros auszuwählen, zieh die Maus über die Zeilen (oder Ctrl / Shift + Klick). Kopieren, Löschen, Exportieren, Nach oben / unten und das Herausziehen aus dem Fenster wirken auf alle ausgewählten Zeilen.`n- Beim Schließen des Fensters läuft die App im Infobereich weiter. Rechtsklick auf das Symbol im Infobereich öffnet Fenster öffnen / Deinstallieren... / Beenden.`n- Die App läuft immer als Administrator, damit Makros auch in Spielen funktionieren, die mit erhöhten Rechten laufen.`n- Das Suchfeld über der Liste zeigt nur die Makros, deren Name, Taste oder Anwendung den Text enthält. Das Kreuz daneben leert es."
    m["hlp_edit"] := "Name - beliebiger Text, wird in der Liste angezeigt.`nProfile - zu welchen Profilen das Makro gehört (auch mehrere).`nAuslösetaste - klicke in das Feld und drücke dann die Taste oder eine Maustaste (rechte, mittlere, Seitentasten X1 / X2, Mausrad). Halte beim Drücken Ctrl / Shift / Alt gedrückt, um eine Kombination zu bilden, zum Beispiel Ctrl+XButton1. Esc bricht ab.`nEin/Aus-Taste - optionale Taste, die dieses Makro ein-/ausschaltet, ohne das Fenster zu öffnen. Backspace löscht sie.`nNur in App (exe) - das Makro funktioniert nur, solange dieses Programm im Vordergrund ist. Drücke Wählen, um eine laufende Anwendung auszuwählen oder nach der .exe zu suchen. Leer = funktioniert überall.`nTyp - Bewegung + Aktionen, Sequenz oder Skript (.ahk). Siehe die nächsten Themen.`nAusführung - Einmal pro Tastendruck: spielt einen Durchlauf ab und wartet, bis du die Taste loslässt. Wiederholen, solange Taste gehalten: spielt immer wieder ab, bis du die Taste loslässt (es stoppt sofort).`n`nSpeichern sichert das Makro, Abbrechen verwirft die Änderungen."
    m["hlp_move"] := "Gedacht für Spiele, in denen du dich ständig bewegst (zum Beispiel A und D) und dazwischen Zauber wirkst.`n`nRichtungen - die Bewegungstasten in Reihenfolge, zum Beispiel: a,d`nAktionen in Folge - die zu drückenden Tasten, eine pro Zyklus, zum Beispiel: 1,2,1,F7,1,F8`n`nJeder Zyklus läuft so ab, mit den eingestellten Verzögerungen:`n  1. Richtung runter`n  2. (Verzögerung 1) Aktion runter`n  3. (Verzögerung 2) Richtung hoch`n  4. (Verzögerung 3) Aktion hoch`n  5. (Verzögerung 4) Pause, dann die nächste Richtung + nächste Aktion`n`nDie Listen beginnen am Ende wieder von vorn. Wenn Richtungen leer ist, werden nur die Aktionen gedrückt: Haltezeit = Verzögerung 2, Pause = Verzögerung 4.`nWenn ein Spiel das Makro ignoriert, erhöhe die Verzögerungen (20-30 ms sind üblich)."
    m["hlp_seq"] := "Eine freie Liste von Schritten. Schreibe einen Schritt pro Zeile:`n`n  down KEY PAUSE   - Taste drücken und halten`n  up KEY PAUSE     - Taste loslassen`n  tap KEY PAUSE    - sofort drücken und loslassen`n`nPAUSE ist die Wartezeit nach dem Schritt in Millisekunden (leer = 0).`n`nBeispiel - schneller A / D-Wechsel:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nBeispiel - Angriff und Zauber:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nBeispiel - zwei Tasten zusammen:`n  tap Shift+4 50`n`nBei Ausführung = Wiederholen laufen die Zeilen in einer Schleife, solange die Auslösetaste gehalten wird; bei Einmal werden sie einmal abgespielt.`nTasten, die beim Loslassen der Auslösetaste noch gehalten werden, werden automatisch losgelassen."
    m["hlp_script"] := "Für alles, was die anderen Typen nicht können. Füge ein eigenes AutoHotkey v2 Skript ein oder schreibe eines.`n`n- Das Skript läuft als eigener Prozess, solange das Makro angehakt ist, und wird beendet, wenn du den Haken entfernst.`n- Es muss AutoHotkey v2 Code sein (v1-Skripte funktionieren nicht).`n- Auslösetaste und Anwendungsfilter werden nicht verwendet, das erledigt dein Skript selbst.`n- Importierte .ahk-Dateien, die nicht von Macro Manager erstellt wurden, werden zu Skript-Makros.`n- Ein importiertes Skript fragt vor dem ersten Start nach: Es läuft mit Administratorrechten, schalte es also nur ein, wenn du seiner Herkunft vertraust. Das Fenster zeigt, was das Skript tut (zum Beispiel Programme starten oder Dateien löschen), und bietet an, den Code anzuzeigen."
    m["hlp_keys"] := "Tastennamen sind die AutoHotkey-Namen: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nEine Taste kann auch als Scancode geschrieben werden, zum Beispiel sc002 - das ist die physische Taste, unabhängig vom Layout. Tasten wie Komma, Plus, & und | werden automatisch so gespeichert.`n`nMaus: Auslöse-, Ein/Aus-Taste und die Taste für Alle Makros können auch eine Maustaste sein: RButton, MButton (Radklick), XButton1 / XButton2 (die zwei Seitentasten) oder das Rad selbst (WheelUp / WheelDown / WheelLeft / WheelRight). Ein Rad kann nicht gehalten werden, daher laufen Rad-Makros immer nur einmal. Die linke Taste steht nicht zur Auswahl.`nGaming- / MMO-Mäuse: Windows kennt nur fünf Maustasten, die zusätzlichen Seitentasten werden von der Maussoftware (G HUB, Synapse, iCUE, ...) verwaltet. Belege sie dort mit Tasten, am besten F13 - F24 (oder Ctrl+Alt+Zahl); Macro Manager sieht sie dann als normale Tasten, klicke also in das Feld Auslösetaste und drücke die Seitentaste.`n`nAufnehmen (neben Richtungen und Aktionen): Drücke Aufnehmen, drücke die Tasten in der gewünschten Reihenfolge und dann Fertig. Das Feld füllt sich live. Makros sind während der Aufnahme pausiert.`n`nTasten gleichzeitig: Tasten, die du zusammen hältst, werden als ein Schritt gespeichert und mit + verbunden, zum Beispiel Shift+4. Beim Abspielen gehen alle zusammen runter und werden zusammen losgelassen (nicht erst Shift und danach 4).`nDasselbe funktioniert durch Eintippen in die Felder: a,Shift+4,d"
    m["hlp_profiles"] := "Profile halten verschiedene Makro-Sets getrennt (zum Beispiel eines pro Spiel).`n`n- Die Profilschaltfläche in der Kopfzeile zeigt das aktuelle Profil. Klicke darauf, um zu wechseln oder ein Profil anzulegen / umzubenennen / zu löschen.`n- Die Liste zeigt nur die Makros des aktuellen Profils, und nur diese sind aktiv.`n- Im Editor kannst du unter Profile ein oder mehrere Profile für das Makro wählen. Wenn du ein Makro änderst, das zu mehreren Profilen gehört, fragt die App: Änderung auf alle anwenden oder nur auf das aktuelle Profil (die anderen Profile behalten die alte Version).`n- Der Haken-Status eines Makros bleibt in jedem Profil gleich; ein Profilwechsel ändert nur, welche Makros im Spiel sind.`n- Beim Löschen eines Profils werden Makros, die nur dazu gehörten, in das erste verbleibende Profil verschoben."
    m["hlp_toggle"] := "Ein/Aus-Taste (im Editor) - eine Taste, die genau dieses Makro ein- / ausschaltet, wie das Anhaken in der Liste. Ein kleiner Tooltip zeigt AN / AUS.`nEin/Aus-Taste für alle Makros (Schaltfläche unter der Liste) - schaltet den Hauptschalter. Funktioniert in jedem Profil.`n`nKlicke auf die Schaltfläche, drücke die Taste. Esc bricht ab, Backspace entfernt die Taste.`nMakros anderer Profile reagieren nicht auf ihre Ein/Aus-Tasten."
    m["hlp_order"] := "Nach oben / Nach unten ändern die Reihenfolge in der Liste. Ein Klick auf eine Spaltenüberschrift sortiert die Liste (erneut klicken kehrt um).`n`nExportieren... speichert das ausgewählte Makro als eigenständige AutoHotkey v2 .ahk-Datei, die auch allein läuft (sie fragt nach Administratorrechten).`nImportieren... lädt eine oder mehrere .ahk-Dateien (oder zieh sie einfach ins Hauptfenster). Du kannst ein Makro auch aus der Liste auf den Desktop / in einen Ordner / in ein Chatfenster ziehen, um es als .ahk-Datei zu exportieren. Das Makro wird nach der Datei benannt; von Macro Manager erstellte Dateien kommen als bearbeitbare Makros zurück, andere Skripte werden zu Skript-Makros. Importe landen im aktuellen Profil und sind zunächst ausgeschaltet.`nAlle exportieren... schreibt jedes Makro in einen Ordner, je eine Datei.`n`nSicherung... (neben Deinstall.) speichert alles – Makros, Profile, Einstellungen und Skriptdateien – in einer .mmbackup-Datei und stellt sie auf einem neuen PC oder nach einer Neuinstallation wieder her. Du kannst die Sicherungsdatei auch auf das Fenster ziehen. Vor dem Wiederherstellen wird der aktuelle Stand als config\backup-before-restore.mmbackup gespeichert.`n`nDeinstallieren löscht den gesamten App-Ordner einschließlich aller Makros und Einstellungen. Es bietet vorher an, alle Makros zu exportieren."
    m["hlp_updates"] := "Das Pfeilsymbol in der Kopfzeile (neben der Profilschaltfläche) zeigt, ob es eine neue Version gibt: grau = du bist auf dem neuesten Stand, grün = eine neue Version ist verfügbar. Fahre mit der Maus darüber für Details.`n`nDie App prüft einige Sekunden nach dem Start (im Menü des Infobereichs abschaltbar: Beim Start nach Updates suchen). Klicke jederzeit auf das Symbol, um erneut zu prüfen. Es wird nichts installiert, bis du auf das grüne Symbol klickst und bestätigst.`n`nBeim Update lädt die App die neue Datei herunter, prüft ihre Prüfsumme, behält die alte als Macro Manager.ahk.bak und startet neu. Deine Makros, Profile und Einstellungen liegen getrennt im Ordner config und bleiben genau so, wie sie sind.`n`nWenn etwas schiefgeht, schließe die App, lösche Macro Manager.ahk und benenne Macro Manager.ahk.bak wieder in Macro Manager.ahk um.`n`nFür das Update ist Internetzugang zu github.com nötig."
    m["hlp_tips"] := "- Das Spiel reagiert nicht: Erhöhe die Verzögerungen, stelle sicher, dass Nur in App zum Spiel passt (nutze Wählen), und lass die App als Administrator laufen.`n- Der Charakter läuft nur in eine Richtung: Halte Richtungspaare in Richtungen (a,d) und die Verzögerung zwischen Zyklen klein, aber nicht 0.`n- Ein Makro startet nicht: Prüfe, ob es angehakt ist, Alle Makros an ist, es im aktuellen Profil liegt und die Auslösetaste gesetzt ist (nicht undefiniert).`n- Zwei Makros mit derselben Auslösetaste: Nur eines davon funktioniert - nutze unterschiedliche Tasten oder unterschiedliche Profile.`n- Hängende Taste nach einem Abbruch: Drücke sie einmal und lass sie los; die App lässt Tasten los, die sie gedrückt hat, wenn das Makro stoppt.`n- Einstellungen und Skripte liegen im Ordner config neben der App."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Discord konnte nicht geöffnet werden. Der Link wurde in die Zwischenablage kopiert - füge ihn in deinen Browser ein:`n`n{1}"
    m["Help"] := "Hilfe"
    m["For support click here"] := "Für Support hier klicken"
    m["Close"] := "Schließen"
    m["Set a trigger key first: {1}"] := "Lege zuerst eine Auslösetaste fest: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Das Herausziehen des Makros ist fehlgeschlagen:`n{1}"
    m["Backup"] := "Sicherung"
    m["Backup and restore"] := "Sichern und Wiederherstellen"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Speichere alle Makros, Profile und Einstellungen (inklusive Skriptdateien) in einer Sicherungsdatei – für einen neuen PC oder eine Neuinstallation. Oder stelle sie aus einer solchen Datei wieder her."
    m["Restore..."] := "Wiederherstellen..."
    m["Create backup..."] := "Sicherung erstellen..."
    m["Create backup"] := "Sicherung erstellen"
    m["Macro Manager backup (*.mmbackup)"] := "Macro Manager-Sicherung (*.mmbackup)"
    m["Backup saved to:`n{1}"] := "Sicherung gespeichert unter:`n{1}"
    m["The backup could not be saved:`n{1}"] := "Die Sicherung konnte nicht gespeichert werden:`n{1}"
    m["Restore from backup"] := "Aus Sicherung wiederherstellen"
    m["This is not a Macro Manager backup file:`n{1}"] := "Das ist keine Sicherungsdatei von Macro Manager:`n{1}"
    m["Restore this backup?"] := "Diese Sicherung wiederherstellen?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Alle aktuellen Makros, Profile und Einstellungen werden durch die Sicherung vom {1} ({2} Makros) ersetzt. Die App startet neu.`n`nDer aktuelle Stand wird zuerst gespeichert als:`n{3}"
    m["Restore"] := "Wiederherstellen"
    m["The backup could not be restored:`n{1}"] := "Die Sicherung konnte nicht wiederhergestellt werden:`n{1}"
    m["Release notes"] := "Versionshinweise"
    m["Getting started"] := "Erste Schritte"
    m["Add / edit a macro"] := "Makro anlegen/ändern"
    m["Keys and recording"] := "Tasten und Aufnahme"
    m["Toggle keys"] := "Ein/Aus-Tasten"
    m["Order, export, backup"] := "Ordnung, Export, Backup"
    m["Tips and problems"] := "Tipps und Probleme"
    return m
}
; ===== END TRANSLATIONS =====
