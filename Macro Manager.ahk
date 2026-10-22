; ComboCrown (files keep the old name Macro Manager) - built from src/*.ahk by tools/build.py (edit those files, not this one)
#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName ComboCrown
;@Ahk2Exe-SetDescription ComboCrown
;@Ahk2Exe-SetProductName ComboCrown
;@Ahk2Exe-SetInternalName ComboCrown
;@Ahk2Exe-SetOrigFilename Macro Manager.exe
;@Ahk2Exe-SetCompanyName vavr0s
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-UpdateManifest 1
#SingleInstance Force
Persistent
SendMode "Event"
SetKeyDelay -1, -1
ProcessSetPriority "High"
NoThrottle()

; Windows 11 slows the timers of apps whose window is hidden (this app sits in the tray) and may put them into
; "efficiency mode" - macro delays would then be longer than set. This opts the app out of both.
NoThrottle() {
    st := Buffer(12, 0)
    for mask in [0x5, 0x1] {                      ; EXECUTION_SPEED + IGNORE_TIMER_RESOLUTION (Win11), else only the first
        NumPut("UInt", 1, "UInt", mask, "UInt", 0, st)
        try if DllCall("SetProcessInformation", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Int", 4, "Ptr", st, "UInt", 12)
            return
    }
}
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
BtnLook := Map()       ; flat button hwnd -> {left, round, hover, badge, pad} (drawn by DrawBtn)
HelpBadgeOn := false   ; gold "!" on the help button: release notes of this version not opened yet
OnMessage(0x2B, DrawBtn)       ; WM_DRAWITEM: the flat buttons are drawn by the app
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
DiscordInvite := "NJUn6AmBSH"    ; ComboCrown community server (help banner: support)
SwOffFile := AssetsDir "\switch_off.png"
SwOnFile := AssetsDir "\switch_on.png"
AssetVersion := "b12"    ; bump when the embedded logo/icon change
AppVersion := "1.23.4"     ; bump on every release (must match version.json in the GitHub repo)
UpdAvail := false       ; a newer version exists (icon in the banner turns green)
UpdInfo := Map()
UpdRepo := "vavr0s/macro-manager"
UpdBranch := "beta"      ; the test (beta) build uses "beta"
UpdateUrl := "https://raw.githubusercontent.com/" UpdRepo "/" UpdBranch "/version.json"      ; fallback (cached by GitHub for ~5 min)
UpdEtag := ""            ; GitHub API answers "not modified" for free when nothing changed
UpdBody := ""
; release notes of THIS version, shown in Help (English + translations below; written by tools/set_notes.py from
; tools/notes.json). No double quotes here.
ReleaseNotes := "BETA build - for testing.`n- Macro Manager is now called ComboCrown. Your macros, profiles and settings stay as they are, and your shortcuts get the new name by themselves.`n- New look of the logo and the app icon: just the crown, without the lettering.`n- The support link in Help is now a Join Discord button, the same as on the website."
; the same notes in the other languages (keep this on one line - tools/set_notes.py rewrites it)
ReleaseNotesL := Map("cs", "BETA verze – k testování.`n- Macro Manager se teď jmenuje ComboCrown. Makra, profily i nastavení zůstávají, jak jsou, a zástupci dostanou nový název sami.`n- Nový vzhled loga a ikony aplikace: jen koruna, bez nápisu.`n- Odkaz na podporu v Nápovědě je teď tlačítko Přidej se na Discord, stejné jako na webu.", "pl", "Wersja BETA – do testów.`n- Macro Manager nazywa się teraz ComboCrown. Makra, profile i ustawienia zostają bez zmian, a skróty same dostaną nową nazwę.`n- Nowy wygląd logo i ikony aplikacji: sama korona, bez napisu.`n- Link do pomocy w Pomocy to teraz przycisk Dołącz do Discorda, taki sam jak na stronie.", "de", "BETA-Version – zum Testen.`n- Macro Manager heißt jetzt ComboCrown. Deine Makros, Profile und Einstellungen bleiben, wie sie sind, und deine Verknüpfungen bekommen den neuen Namen von selbst.`n- Neues Logo und App-Symbol: nur die Krone, ohne Schriftzug.`n- Der Support-Link in der Hilfe ist jetzt ein Discord-beitreten-Button, genau wie auf der Website.")
SeenVer := AppVersion   ; last version whose release notes the user has opened (! shown while different)
AutoUpd := true         ; check for updates when the app starts
Macros := []
MasterOn := true
Registered := []
Populating := false
HoverHwnd := 0
BtnAlias := Map()       ; picture hwnd -> button hwnd (a flag lying on a button hovers the button)
Recording := false
InjDown := Map()        ; trigger key -> a press from another program (mouse software, ...) is held
ForeignMod := Map()     ; virtual key -> Ctrl / Alt / Shift / Win held by another program (ModWatch leaves it alone)
PressBusy := Map()      ; trigger key -> its press modes are being told apart / played
DblWait := Map()        ; trigger key -> waiting for the 2nd press of a double tap
DblHit := Map()         ; trigger key -> the 2nd press came
DragOut := false
DragEnd := 0
DragStart := Map("row", 0, "x", 0, "y", 0, "last", "", "lock", false)
MasterKey := ""        ; optional hotkey that toggles "All macros"
HoldMs := 300          ; long press = trigger key held at least this long (macros.ini [main] holdms)
DblMs := 250           ; double tap = second press within this time (macros.ini [main] doublems)
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
LibApi := "https://macro-manager-library.vavr0smacromanager.workers.dev/v1/macros"     ; macro library (server/)
UpdServer := "https://macro-manager-library.vavr0smacromanager.workers.dev/v1/app"     ; app updates through the same server
LibId := ""             ; random id of this install for the library (macros.ini [main] libid)
LibAuthor := ""         ; nickname last used for sharing (macros.ini [main] libauthor)
LibGui := 0, LibOpen := false, LibBusy := false, LibW := 440, LibH := 0
LibItems := [], LibSort := "top", LibMore := false
LibWho := "others"      ; library tab: others = macros of other players, mine = my shared macros
LibGameF := ""          ; library filter: one game ("" = all)
LibGames := []          ; games used in the library (game filter, share form)
LibGame := ""           ; game last used for sharing (macros.ini [main] libgame)
LibNew := Map()         ; downloaded macro -> its newer version in Macro Hub (LibCheckUpdates)
LibOff := Map(), LibIsOff := false      ; the "No connection" sign of the panel (hwnd -> control) / shown now
LibLV := 0, LibSearch := 0, LibDesc := 0, LibInfo := 0, LibBtn := Map()
EnsureAssets()          ; logo + icon are embedded in this file
SetAppIdentity()        ; notifications / taskbar: "ComboCrown" with its icon (not AutoHotkey)

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
Main := Gui(, "ComboCrown (beta)")
Main.SetFont("s9", "Segoe UI")
try {
    Main.AddPicture("x10 y8 w820 h72", LogoWideFile)      ; black rounded banner with the logo
    Main.SetFont("s16 bold cD0AE6B", "Segoe UI")
    ttl := Main.AddText("x100 y29 w200 BackgroundTrans", "ComboCrown")
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
    ; help on top, updates below (same size). The help control is a bit larger than its button: the gold "!" badge
    ; (release notes not read yet) is drawn on the button's top right corner
    bHelp := AddBtn(Main, "x782 y12 w36 h30", "?", OpenHelp, "btnbanner")
    BtnLook[bHelp.Hwnd].pad := [0, 2, 8, 0]
    BtnLook[bHelp.Hwnd].badge := true
    HelpBadgeOn := (SeenVer != AppVersion)
    Main.SetFont("s12 norm", "Segoe MDL2 Assets")
    bUpd := AddBtn(Main, "x782 y46 w28 h28", Chr(0xE896), OnUpdIcon, "btnupd0")      ; download arrow: grey = up to date, green = new version
    Main.SetFont("s9 norm c000000", "Segoe UI")
}
try {
    TraySetIcon(IconFile)
    A_IconTip := "ComboCrown BETA v" AppVersion
}
SetWinIcon(Main.Hwnd)
; column header strip (flat, themed) - the list itself has no native header
; search box above the list: shows only the macros whose name, key or application contains the text
eSearch := Main.AddEdit("x10 y92 w300 h26")
eSearch.OnEvent("Change", (*) => Refresh())
SendMessage(0x1501, 1, StrPtr(_T("Search (name, key or application)")), eSearch)     ; EM_SETCUEBANNER: grey hint text
bClear := AddBtn(Main, "x314 y92 w28 h26", Chr(0xD7), (*) => ClearSearch(), "btn")
bLib := AddBtn(Main, "x660 y92 w170 h26", _T("Macro Hub") "  " Chr(0x25B8), ToggleLibrary)    ; shared macros (panel on the right)
hdrNames := [_T("Name"), _T("Key"), _T("Application"), _T("Type"), _T("Share")]
hdrW := [270, 150, 190, 130, 80]
hdrCtl := []
hx := 10
for i, nm in hdrNames {
    h := Main.AddText("x" hx " y126 w" hdrW[i] " h28 +0x200" (i = 5 ? " Center" : ""), (i = 5 ? "" : "  ") nm)
    Roles[h.Hwnd] := "hdr"
    if (i < 5)                                ; (the share column is not sorted)
        h.OnEvent("Click", SortBy.Bind(i))
    hdrCtl.Push(h)
    hx += hdrW[i]
}
LV := Main.AddListView("x10 y154 w820 r13 -Hdr -E0x200 Checked Multi", [_T("Name"), _T("Key"), _T("Application"), _T("Type"), _T("Share")])
LV.SetFont("s10")
LV.Opt("+LV0x10020")                          ; LVS_EX_DOUBLEBUFFER (no flicker on repaint) + full-row select (a row can be picked / dragged anywhere)
for i, w in hdrW
    LV.ModifyCol(i, w)
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
DarkMenus(DarkOn)
OnExit(ExitHandler)

Refresh()
Apply()
ApplyTheme(Main)
SetTimer(HoverTick, 40)
SetTimer(ModWatch, 250)              ; un-sticks Ctrl / Alt / Shift / Win that Windows still thinks are held
ModHookStart()                       ; ... except those another program holds on purpose
SetTimer(ScriptWatch, 1000)          ; a script macro whose script has finished is turned off
try Hotkey("~*RAlt up", AltGrUp)     ; AltGr released: make sure its Ctrl is released too
OnMessage(0x18, OnMainShown)         ; WM_SHOWWINDOW: repaint the list when the window appears
OnMessage(0x3, LibFollow)            ; WM_MOVE: the library panel moves with the main window
Main.Show()
FitCols()                            ; (now that the window has its size: the last column fits, no horizontal scroll bar)
SetTimer(RedrawList, -300)
SetTimer(() => AutoCheck(), -4000)
SetTimer(() => LibCheckUpdates(true), -8000)   ; new versions of macros downloaded from Macro Hub (also when the
SetTimer(() => LibCheckUpdates(true), 900000)   ; window is opened and when Macro Hub is opened)
SetTimer(AutoCheck, 60000)         ; background check (at most every 2 minutes, see AutoCheck)
return

; ============ third-party credits ============
; Some features follow ideas and small techniques from these MIT-licensed projects (the code here is written
; for ComboCrown, nothing is copied as a library):
;   - press modes short tap / double tap / long press (RunPress) .... evilC/TapHoldManager
;       Copyright (c) 2018 Clive Galway
;   - exact pauses (StepWait) ....................................... thqby/ahk2_lib (HighPrecisionSleep)
;       Copyright (c) 2023 thqby
;   - rounded buttons, themed tray menu (RoundCorners, DarkMenus) ... nperovic/GuiEnhancerKit, ColorButton.ahk
;       Copyright (c) 2024 Nikola (nperovic)
;
; MIT License: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
; associated documentation files (the "Software"), to deal in the Software without restriction, including without
; limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
; Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
; The above copyright notice and this permission notice shall be included in all copies or substantial portions of
; the Software.
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
; THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
; CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
; DEALINGS IN THE SOFTWARE.

; ============ window handlers ============
OnMainClose(*) {
    Main.Hide()
    try LibGui.Hide()                              ; the library panel goes with it (LibOpen stays: back on Open window)
    return 1
}

ExitHandler(*) {
    ReleaseHeld()                                  ; keys a macro was holding when the app was closed
    for k in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]     ; and modifiers Windows still thinks are down
        if (GetKeyState(k) && !GetKeyState(k, "P") && !ForeignMod.Has(GetKeyVK(k)))
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
        c["libshare"] := ""                     ; the copy itself is not in the library
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
    if (ThemedAsk("ComboCrown", "", msg, [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
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
    k := MKst["key"]
    if (k != "") {                                  ; works in every profile: no macro of any profile may use the key
        id := KeyId(k)
        for m in Macros {
            who := KeyId(m["tkey"]) = id ? _T("the toggle key of `"{1}`"", m["name"]) : (TrigId(m) = id ? _T("the trigger key of `"{1}`"", m["name"]) : "")
            if (who != "") {
                ThemedNote(_T("The key {1} is already used as {2}.", k, who), , true)
                MKst["key"] := MasterKey            ; keep the previous key
                bMKey.Text := KeyLabel(_T("All macros toggle key:") "  ", MasterKey)
                return
            }
        }
    }
    MasterKey := k
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

Toast(txt, ms := 1200) {
    ToolTip(txt)
    SetTimer(() => ToolTip(), -ms)
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
        if (i < 5)
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

; the list is repainted whenever the main window appears: after some starts its rows kept a look from before
; their check boxes were set - every macro was shown unticked although it was on (seen on Windows 11)
OnMainShown(wp, lp, msg, hwnd) {
    if (wp && hwnd = Main.Hwnd) {
        SetTimer(RedrawList, -100)
        if LibOpen
            SetTimer(OpenLibrary, -50)
        SetTimer(() => LibCheckUpdates(), -1500)                ; new versions of downloaded Macro Hub macros
    }
}

RedrawList() => DllCall("RedrawWindow", "Ptr", LV.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)    ; invalidate + erase + frame + children, now

; the key as shown in the list: a script has no trigger key (stored as "undefined") - shown as a dash
KeyShown(m) => (Trim(m["hotkey"]) = "" || Trim(m["hotkey"]) = "undefined") ? Chr(0x2014) : m["hotkey"]

Refresh() {
    global Populating
    Populating := true
    LV.Delete()
    global View
    View := []
    ; search box: every word must be in the name, key or application ("war lctrl" = warrior macros on LCtrl)
    words := StrSplit(Trim(RegExReplace(eSearch.Value, "\s+", " ")), " ")
    for m in Macros
        if (InProfile(m) && SearchHit(m, words))
            View.Push(m)
    for m in View
        LV.Add(m["enabled"] ? "Check" : "", m["name"], KeyShown(m) (PressEff(m) = "" ? "" : "  · " PressShort(PressEff(m))), (m["app"] = "" || m["type"] = "script") ? _T("(everywhere)") : m["app"], TypeLabel(m["type"]), "")
    Populating := false
    FitCols()
}

; the last column takes the width that is left: no horizontal scroll bar when the vertical one shows
; (the rows are drawn by OnLvDraw, which does not follow a horizontal scroll - the check boxes got smeared)
FitCols() {
    cl := Buffer(16)
    DllCall("GetClientRect", "Ptr", LV.Hwnd, "Ptr", cl)
    used := 0
    loop 4
        used += SendMessage(0x101D, A_Index - 1, 0, LV)        ; LVM_GETCOLUMNWIDTH
    SendMessage(0x101E, 4, Max(30, NumGet(cl, 8, "Int") - used), LV)       ; LVM_SETCOLUMNWIDTH
}

SearchHit(m, words) {
    for w in words
        if (w != "" && !InStr(m["name"], w) && !InStr(KeyShown(m), w) && !InStr(m["app"], w))
            return false
    return true
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
    path := FileSelect("S16", A_Desktop "\" SafeFileName(m["name"]) ".ahk", _T("Export macro"), _T("AutoHotkey scripts (*.ahk)"))
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
        if (m["type"] != "script" && (Trim(m["hotkey"]) = "" || Trim(m["hotkey"]) = "undefined"))
            continue                                  ; no trigger key: the file would not run
        code := ""
        try code := ExportCode(m)
        if (code = "")
            continue
        base := SafeFileName(m["name"])
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

; a macro name as a file name Windows accepts (no \ / : * ? " < > |, no trailing dot / space, no CON, NUL, COM1 ...)
SafeFileName(name) {
    s := RTrim(RegExReplace(name, '[\\/:*?"<>|\x00-\x1F]', "_"), ". ")
    if (s = "")
        s := "macro"
    if RegExMatch(s, "i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$")
        s := "_" s
    return s
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
        ; file exported by ComboCrown -> editable native macro
        m["type"] := meta["type"]
        for k in ["app", "dirs", "actions", "seq", "tkey", "press"]
            if meta.Has(k)
                m[k] := meta[k]
        for k in ["g1", "g2", "g3", "ge", "repeat"]
            if meta.Has(k)
                m[k] := Num(meta[k])
        m["exact"] := meta.Has("exact") ? Num(meta["exact"]) : 0     ; exported before exact delays existed: old timing
        m["hotkey"] := (meta.Has("hotkey") && Trim(meta["hotkey"]) != "") ? Trim(meta["hotkey"]) : "undefined"
    } else {
        ; any other script -> runs as its own process while the macro is on
        if (!InStr(text, "#Requires AutoHotkey v2")
            && ThemedAsk("ComboCrown", _T("Import anyway?"), _T("This script has no `"#Requires AutoHotkey v2`" line.`nIt will be run with AutoHotkey v2 - v1 scripts won't work."), [[_T("Import anyway"), "yes", "btn"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
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
; so Explorer, the taskbar and Task Manager show ComboCrown instead of AutoHotkey).
Bootstrap() {
    reg := "HKCU\Software\MacroManagerBeta"
    prev := RegRead(reg, "InstallDir", "")
    if (prev != "")
        InitLang(prev "\config\macros.ini")             ; an existing install keeps its language
    if (prev != "" && FileExist(prev "\config\.installed") && FindInstalled(prev) != "") {
        r := ThemedAsk(_T("ComboCrown setup"), _T("ComboCrown is already installed"), _T("Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?", prev)
            , [[_T("Just start"), "start", "btn"], [_T("Update and start"), "update", "btnprimary"]], false)
        if (r = "")
            return
        if (r = "update") {
            try {
                InstallProgram(prev)
            } catch as e {
                ThemedNote(_T("Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}", e.Message), _T("ComboCrown setup"), true)
            }
        }
        LaunchInstalled(prev)
        return
    }

    dir := DirSelect("*" A_ProgramFiles, 1, _T("Choose where to install ComboCrown.`nA 'ComboCrown' folder will be created there."))
    if (dir = "")
        return
    target := RTrim(dir, "\") "\ComboCrownBeta"
    compiled := false
    try {
        DirCreate(target "\config\assets")
        B64ToFile(IconB64(), target "\config\assets\app.ico")
        B64ToFile(LogoB64(), target "\config\assets\logo.png")
        compiled := InstallProgram(target)
        FileAppend "installed", target "\config\.installed"
        RegWrite(target, "REG_SZ", reg, "InstallDir")
    } catch as e {
        ThemedNote(_T("Installation failed:`n{1}", e.Message), _T("ComboCrown setup"), true)
        return
    }

    icon := target "\config\assets\app.ico"
    if (ThemedAsk(_T("ComboCrown setup"), "", _T("Create a Start Menu shortcut?"), [[_T("Skip"), "", "btn"], [_T("Create"), "yes", "btnprimary"]], false) = "yes")
        MakeShortcut(A_Programs "\ComboCrown Beta.lnk", target, icon)
    if (ThemedAsk(_T("ComboCrown setup"), "", _T("Create a Desktop shortcut?"), [[_T("Skip"), "", "btn"], [_T("Create"), "yes", "btnprimary"]], false) = "yes")
        MakeShortcut(A_Desktop "\ComboCrown Beta.lnk", target, icon)
    ThemedNote(_T("Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config", target), _T("ComboCrown setup"))
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

; the AutoHotkey v2 interpreter (a compiled ComboCrown can't use its own A_AhkPath for scripts)
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
; so Explorer, the taskbar and Task Manager show ComboCrown instead of AutoHotkey.
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
    strs := BufCat(VerString("CompanyName", "vavr0s"), VerString("FileDescription", "ComboCrown")
        , VerString("FileVersion", "1.0.0.0"), VerString("InternalName", "ComboCrown")
        , VerString("OriginalFilename", "Macro Manager.exe"), VerString("ProductName", "ComboCrown")
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
        RegWrite("ComboCrown (beta)", "REG_SZ", k, "DisplayName")
        RegWrite("vavr0s", "REG_SZ", k, "Publisher")
        RegWrite(cmd, "REG_SZ", k, "UninstallString")
        RegWrite(A_ScriptDir, "REG_SZ", k, "InstallLocation")
        RegWrite(FileExist(IconFile) ? IconFile : (A_IsCompiled ? A_ScriptFullPath : A_AhkPath), "REG_SZ", k, "DisplayIcon")
        RegWrite(1, "REG_DWORD", k, "NoModify")
        RegWrite(1, "REG_DWORD", k, "NoRepair")
        RegWrite(A_ScriptDir, "REG_SZ", "HKCU\Software\MacroManagerBeta", "InstallDir")
    } catch as e
        DiagLog("RegisterUninstall", e)
    if (InStr(RegRead(k, "DisplayName", ""), "ComboCrown") != 1)
        DiagLog("RegisterUninstall", Error("written but reads back as " RegRead(k, "DisplayName", "?"), , k))
}

; problems that are not worth a message box (config\diag.log, the newest 50 lines are kept)
DiagLog(where, e) {
    try {
        f := ConfigDir "\diag.log"
        old := FileExist(f) ? FileRead(f) : ""
        lines := StrSplit(Trim(old, "`n"), "`n")
        while (lines.Length > 49)
            lines.RemoveAt(1)
        t := ""
        for l in lines
            t .= l "`n"
        t .= FormatTime(, "yyyy-MM-dd HH:mm:ss") " v" AppVersion " " where ": " e.Message (e.Extra != "" ? " (" e.Extra ")" : "") " [" e.What "] admin=" A_IsAdmin "`n"
        WriteText(f, t)
    }
}

UninstallApp(fromArg := false) {
    dir := A_ScriptDir
    if (StrLen(dir) <= 3 || !FileExist(dir "\config\.installed")) {
        ThemedNote(_T("This doesn't look like an installed copy, nothing was removed."), _T("Uninstall ComboCrown"), true)
        return false
    }
    if (ThemedAsk(_T("Uninstall ComboCrown"), "", _T("Uninstall ComboCrown?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}", dir), [[_T("Uninstall"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes") {
        if fromArg
            LaunchInstalled(dir)
        return false
    }
    ; offer a backup file (macros, profiles, settings, script files) before everything is deleted
    if (!Macros.Length && FileExist(IniFile))
        try Load()
    if Macros.Length {
        r := ThemedAsk(_T("Uninstall ComboCrown"), "", _T("Save a backup of your macros, profiles and settings before uninstalling? After a reinstall you can restore it with Backup... > Restore..."), [[_T("Cancel"), "", "btn"], [_T("Don't save"), "no", "btn"], [_T("Create backup..."), "yes", "btnprimary"]], false)
        if (r = "") {
            if fromArg
                LaunchInstalled(dir)
            return false
        }
        if (r = "yes") {
            path := FileSelect("S16", A_Desktop "\ComboCrown backup " FormatTime(, "yyyy-MM-dd") ".mmbackup", _T("Create backup"), _T("ComboCrown backup (*.mmbackup)"))
            if (path = "") {
                if fromArg
                    LaunchInstalled(dir)
                return false
            }
            if !RegExMatch(path, "i)\.mmbackup$")
                path .= ".mmbackup"
            try {
                Save()                                  ; the settings in memory are the newest
                WriteBackup(path)
            } catch as e {
                ThemedNote(_T("The backup could not be saved:`n{1}", e.Message), _T("Uninstall ComboCrown"), true)
                if fromArg
                    LaunchInstalled(dir)
                return false                            ; nothing deleted without the backup the user asked for
            }
            ThemedNote(_T("Backup saved to:`n{1}", path), _T("Uninstall ComboCrown"))
        }
    }
    ; stop imported scripts started by the manager
    for m, pid in Procs
        try ProcessClose(pid)
    ; remove registry entries and the Start Menu / Desktop shortcuts
    try RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManagerBeta")
    try RegDeleteKey("HKCU\Software\MacroManagerBeta")
    try RegDeleteKey("HKCU\Software\Classes\AppUserModelId\" AppId())     ; name + icon of its notifications
    try FileDelete(A_Programs "\ComboCrown Beta.lnk")
    try FileDelete(A_Desktop "\ComboCrown Beta.lnk")
    ThemedNote(_T("ComboCrown has been uninstalled.`nThe folder will be removed in a moment."), _T("Uninstall ComboCrown"))
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

    press := PressEff(m)
    if (m["type"] = "move") {
        data := "rep := " (m["repeat"] && press != "tap" ? "true" : "false") "`n"
            . "dirs := " ArrLit(SplitKeys(m["dirs"])) "`n"
            . "acts := " ArrLit(SplitKeys(m["actions"])) "`n"
            . "g1 := " m["g1"] ", g2 := " m["g2"] ", g3 := " m["g3"] ", ge := " m["ge"]
        body := TplMove()
    } else {
        data := "rep := " (m["repeat"] && press != "tap" ? "true" : "false") "`n"
            . "steps := " StepsLit(m["seq"])
        body := TplSeq()
    }
    code := TplHeader() "`n" body
    code := StrReplace(code, "@DATA@", data)
    code := StrReplace(code, "@PRESS@", press)
    code := StrReplace(code, "@EXACT@", m["exact"] ? "true" : "false")
    code := StrReplace(code, "@HOLDMS@", HoldMs)
    code := StrReplace(code, "@DBLMS@", DblMs)
    code := StrReplace(code, "@DBL@", Round(DblMs / 1000, 3))
    mods := "["                                       ; modifiers of a combination such as LCtrl+XButton1
    parts := StrSplit(Trim(m["hotkey"]), "+")
    loop parts.Length - 1
        if (Trim(parts[A_Index]) != "")
            mods .= (mods = "[" ? "" : ", ") '"' Trim(parts[A_Index]) '"'
    code := StrReplace(code, "@MODS@", mods "]")
    code := StrReplace(code, "@UP@", IsWheel(m["hotkey"]) ? "" : TrigHot(m["hotkey"]) " up:: {`n    global inj := false`n}")
    code := StrReplace(code, "@HOT@", TrigHot(m["hotkey"]))
    code := StrReplace(code, "@TRIG@", TrigMain(m["hotkey"]))
    app := StrReplace(m["app"], '"', "")
    code := StrReplace(code, "@APP@", app)
    code := StrReplace(code, "@HOTIF@", app = "" ? "" : '#HotIf WinActive("ahk_exe ' app '")')   ; plain criterion: checked by the hook itself

    code .= "`n`n; ===== ComboCrown metadata (used when importing this file) =====`n"
    for k in ["type", "hotkey", "app", "dirs", "actions", "g1", "g2", "g3", "ge", "seq", "repeat", "tkey", "press", "exact"]
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
st := Buffer(12, 0)     ; Windows 11: no slowed-down timers / efficiency mode for this background script
for mask in [0x5, 0x1] {
    NumPut("UInt", 1, "UInt", mask, "UInt", 0, st)
    try if DllCall("SetProcessInformation", "Ptr", -1, "Int", 4, "Ptr", st, "UInt", 12)
        break
}

if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

trig := "@TRIG@"
app := "@APP@"
press := "@PRESS@"      ; "" = at once, tap = short press, double = pressed twice quickly, hold = held a moment
exact := @EXACT@        ; true = delays kept to about a millisecond, false = plain Sleep
@DATA@
if InStr(trig, "Wheel") = 1
    rep := false        ; a wheel can't be held

; a press from another program (mouse software, Steam Input, remote desktop) is not "physical" for Windows:
; for such a press the script follows the key's own down / up events instead of the physical key state
mods := @MODS@          ; modifiers of a key combination (they must stay down too)
inj := false, busy := false, waiting := false, dblHit := false

Held() {
    global inj
    if GetKeyState(trig, "P")
        return true
    if !inj
        return false
    for k in mods
        if !GetKeyState(k) {
            inj := false
            return false
        }
    return true
}

; waits until the key is released (true) or ms have passed (false)
WaitUp(ms) {
    if !inj
        return ms ? KeyWait(trig, "P T" ms / 1000) : KeyWait(trig, "P")
    t := A_TickCount
    while Held() {
        if (ms && A_TickCount - t >= ms)
            return false
        Sleep 5
    }
    return true
}

; is this the press the macro waits for? (long press: still held after a moment; double tap: pressed again in time)
PressOk() {
    global inj, waiting, dblHit
    inj := !GetKeyState(trig, "P")
    fromApp := inj                                    ; (inj goes back to false when the key is released)
    if (press = "")
        return true
    if (press = "hold")
        return !WaitUp(@HOLDMS@)
    WaitUp(0)
    if (press = "tap")
        return true
    dblHit := false, waiting := true
    if fromApp {
        t := A_TickCount
        while (!dblHit && A_TickCount - t < @DBLMS@)
            Sleep 5
        hit := dblHit
    } else
        hit := KeyWait(trig, "D P T@DBL@")
    waiting := false
    return hit
}

; the trigger key: a 2nd press while the macro is busy only counts as the 2nd press of a double tap
OnTrigger(play) {
    global busy, inj, dblHit
    if busy {
        if waiting {
            inj := !GetKeyState(trig, "P")
            dblHit := true
        }
        return
    }
    busy := true
    try {
        if PressOk()
            play()
    } finally
        busy := false
}

; exact pause: most of it a normal Sleep, the rest measured in 1 ms steps (Sleep alone can be ~15 ms longer)
Wait(ms) {
    static f := 0
    if (ms <= 0) {
        Sleep -1
        return
    }
    if !exact {
        Sleep ms
        return
    }
    if !f
        DllCall("QueryPerformanceFrequency", "Int64*", &f)
    DllCall("QueryPerformanceCounter", "Int64*", &t := 0)
    stop := t + ms * f / 1000
    if (ms > 20)
        Sleep ms - 16
    loop {
        DllCall("QueryPerformanceCounter", "Int64*", &t)
        left := (stop - t) * 1000 / f
        if (left <= 0)
            break
        if (left > 1.5)
            DllCall("Sleep", "UInt", 1)
    }
}

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

Active() => Held() && (app = "" || WinActive("ahk_exe " app))

@HOTIF@
)"
}

TplMove() {
    return "
(
#MaxThreadsPerHotkey 2
@HOT@::OnTrigger(Play)
@UP@
#HotIf

Play() {
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    di := 1, ai := 1, n := 0
    while (rep ? Active() : n < acts.Length) {
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            Send Down(dir)
            Wait(g1)
            Send Down(key)
            Wait(g2)
            Send Up(dir)
            Wait(g3)
            Send Up(key)
            di := di >= dirs.Length ? 1 : di + 1
        } else {
            Send Down(key)
            Wait(g2)
            Send Up(key)
        }
        Wait(ge)
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
)"
}

TplSeq() {
    return "
(
#MaxThreadsPerHotkey 2
@HOT@::OnTrigger(Play)
@UP@
#HotIf

Play() {
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
            Wait(s[3])
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
)"
}

; ============ macro editor ============
EditMacro(idx) {
    static open := 0                                  ; one editor at a time (two editors of one macro would overwrite each other)
    if (open && WinExist("ahk_id " open)) {
        WinActivate("ahk_id " open)
        return
    }
    isNew := !idx
    if (!isNew && idx > View.Length)
        return                                        ; the list changed in the meantime
    m := isNew ? Defaults() : View[idx]
    if isNew
        m["profiles"] := CurProfile
    pv := Map("v", m["profiles"])
    origProfs := m["profiles"]
    g := Gui("+Owner" Main.Hwnd " +ToolWindow", isNew ? _T("New macro") : _T("Edit macro"))
    open := g.Hwnd
    g.SetFont("s9", "Segoe UI")
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)             ; same banner as the main window
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w400 BackgroundTrans", isNew ? _T("New macro") : _T("Edit macro"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s9 norm c000000", "Segoe UI")
    }

    g.AddText("x10 y100 w136 +0x200 h26", _T("Name"))
    eName := g.AddEdit("x150 y100 w250 h26", isNew ? "" : m["name"])
    if isNew                                          ; new macro: the default name is only a grey hint, typing replaces it
        DllCall("SendMessageW", "Ptr", eName.Hwnd, "UInt", 0x1501, "Ptr", 1, "WStr", m["name"])   ; EM_SETCUEBANNER
    g.AddText("x405 y100 w85 +0x200 h26", _T("Profiles"))
    bProfs := AddBtn(g, "x495 y100 w155 h26", ProfLabel(pv["v"]), (*) => (pv["v"] := PickProfiles(g, pv["v"]), bProfs.Text := ProfLabel(pv["v"])))
    g.AddText("x10 y136 w136 +0x200 h26", _T("Trigger key"))
    st := Map("key", Trim(m["hotkey"]) = "undefined" ? "" : m["hotkey"], "tkey", m["tkey"])   ; (a script without a key: "undefined")
    bKey := AddBtn(g, "x150 y136 w250 h26", KeyLabel("", st["key"]), (*) => CaptureKey(bKey, st, "key", false))
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
    ; press mode: how the trigger key has to be pressed (different modes can share one key)
    psel := 1
    for i, p in ["", "tap", "double", "hold"]
        if (PressOf(m) = p)
            psel := i
    pl := g.AddText("x10 y244 w136 +0x200 h26", _T("Press"))
    pb := []
    for i, nm in [_T("Normal"), _T("Short tap"), _T("Double tap"), _T("Long press")]
        pb.Push(AddBtn(g, "x" (150 + (i - 1) * 126) " y244 w122 h26", nm, SetPress.Bind(i), i = psel ? "btnprimary" : "btn"))
    rl := g.AddText("x10 y280 w136 +0x200 h26", _T("Run"))
    rb := []
    for i, nm in [_T("Once per key press"), _T("Repeat while key is held")]
        rb.Push(AddBtn(g, "x" (150 + (i - 1) * 255) " y280 w245 h26", nm, SetRun.Bind(i), i = rsel ? "btnprimary" : "btn"))

    ; --- group: move + actions ---
    mv := []
    mv.Push(g.AddText("x10 y328 w136 +0x200 h26", _T("Directions (optional)")))
    eDirs := g.AddEdit("x150 y328 w420 h26", m["dirs"])
    rb1 := AddBtn(g, "x580 y328 w70 h26", _T("Record"), (*) => StartListRec(eDirs, rb1))
    mv.Push(eDirs, rb1)
    mv.Push(g.AddText("x10 y364 w136 +0x200 h26", _T("Actions in order")))
    eActs := g.AddEdit("x150 y364 w420 h26", m["actions"])
    rb2 := AddBtn(g, "x580 y364 w70 h26", _T("Record"), (*) => StartListRec(eActs, rb2))
    mv.Push(eActs, rb2)
    mv.Push(g.AddText("x10 y400 w136 +0x200 h26", _T("Delays (ms)")))
    e1 := g.AddEdit("x150 y400 w110 h26 Number", m["g1"])
    e2 := g.AddEdit("x275 y400 w110 h26 Number", m["g2"])
    e3 := g.AddEdit("x400 y400 w110 h26 Number", m["g3"])
    e4 := g.AddEdit("x525 y400 w110 h26 Number", m["ge"])
    mv.Push(e1, e2, e3, e4)
    mv.Push(AddHint(g, "x150 y430 w120 h32", _T("dir↓ → action↓")))
    mv.Push(AddHint(g, "x275 y430 w120 h32", _T("action↓ → dir↑")))
    mv.Push(AddHint(g, "x400 y430 w120 h32", _T("dir↑ → action↑")))
    mv.Push(AddHint(g, "x525 y430 w120 h32", _T("between cycles")))
    mv.Push(AddHint(g, "x10 y470 w640", _T("Directions empty = actions only (delay 2 = hold time, delay 4 = pause). Record: press keys, then Done. Keys held together are joined with + (e.g. Shift+4).")))

    ; --- group: sequence ---
    eSeq := g.AddEdit("x10 y328 w640 h120 Multi WantReturn", StrReplace(m["seq"], "|", "`n"))
    eSeq.OnEvent("Change", FixLineEnds)
    sq := [eSeq, AddHint(g, "x10 y454 w640", _T("One step per line: down|up|tap key delay_ms   (e.g. down A 25,  tap Shift+4 10)"))]

    ; --- group: script ---
    code := ""
    if (m["type"] = "script" && m["file"] != "" && FileExist(ScriptPath(m)))
        code := FileRead(ScriptPath(m), "UTF-8")
    eCode := g.AddEdit("x10 y328 w640 h150 Multi WantReturn -Wrap HScroll", code)
    eCode.SetFont("s9", "Consolas")
    eCode.OnEvent("Change", FixLineEnds)
    Roles[eCode.Hwnd] := "code"
    sc := [eCode, AddHint(g, "x10 y484 w640", _T("Runs as its own process while this macro is checked (AutoHotkey v2)."))]

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
    SetPress(n, *) {
        psel := n
        SetSeg(pb, n)
        Toggle()
    }
    Toggle(*) {
        t := tsel
        for c in mv
            c.Visible := (t = 1)
        for c in sq
            c.Visible := (t = 2)
        for c in sc
            c.Visible := (t = 3)
        try bExact.Visible := (t != 3)
        bKey.Enabled := (t != 3)
        eApp.Enabled := (t != 3)
        bApp.Enabled := (t != 3)
        pl.Visible := (t != 3)
        for c in pb
            c.Visible := (t != 3)
        rv := (t != 3 && psel != 2)                 ; a short tap has already been released: it always plays once
        rl.Visible := rv
        for c in rb
            c.Visible := rv
    }

    ; a macro that belongs to several profiles: apply the change everywhere, or only in the current profile
    Detach() {
        if (isNew || !HasProf(pv["v"], CurProfile) || StrSplit(pv["v"], "|").Length < 2)
            return true
        r := ThemedAsk("ComboCrown", _T("This macro is in several profiles ({1}).", ProfLabel(pv["v"]))
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
        if (nm = "" && isNew)
            nm := m["name"]                             ; nothing typed: the default name (the grey hint)
        if (st["tkey"] != "" && (who := KeyTaken(KeyId(st["tkey"]), m, pv["v"], true))) {   ; toggle = another key in use
            ThemedNote(_T("The toggle key {1} is already used as {2}.", st["tkey"], who), , true)
            return
        }
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
            if (st["tkey"] != "" && StrLower(TrigHot(st["tkey"])) = StrLower(TrigHot(key))) {
                ThemedNote(_T("The toggle key can't be the same as the trigger key."), , true)
                return
            }
            if (who := KeyTaken(KeyId(key), m, pv["v"], false)) {        ; trigger = a toggle key in the same profile
                ThemedNote(_T("The trigger key {1} is already used as {2}.", key, who), , true)
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
            m["press"] := ["", "tap", "double", "hold"][psel]
            m["exact"] := ex["v"]
        }
        m["name"] := nm = "" ? "Macro" : nm
        m["profiles"] := pv["v"] = "" ? CurProfile : pv["v"]
        m["tkey"] := st["tkey"]
        if isNew {
            Macros.Push(m)
            if (eSearch.Value != "")
                eSearch.Value := ""               ; the new macro must be visible
        }
        if (!isNew && !IndexOf(m))
            Macros.Push(m)                          ; deleted from the list while the editor was open: keep the edit
        g.Destroy()
        Save()
        Apply()
        Refresh()
        if (m["enabled"] && (other := KeyClash(m)))
            Toast(_T("Same trigger key as `"{1}`" - only one of them works", other["name"]))
        if LibSharedChanged(m)                          ; shared in Macro Hub and changed now: update it there?
            SetTimer(LibOfferUpdate.Bind(m), -150)
    }

    ; exact delays: on for new macros; older macros keep their timing until this is switched on
    ex := Map("v", m["exact"] ? 1 : 0)
    ExLabel() => ex["v"] ? Chr(0x2713) "  " _T("Exact delays") : _T("Exact delays") ": " _T("OFF")
    bExact := AddBtn(g, "x10 y518 w220 h34", ExLabel(), FlipExact, ex["v"] ? "btnprimary" : "btn")
    FlipExact(*) {
        ex["v"] := !ex["v"]
        bExact.Text := ExLabel()
        Roles[bExact.Hwnd] := ex["v"] ? "btnprimary" : "btn"
        PaintBtn(bExact.Hwnd, true)
    }
    AddBtn(g, "x450 y518 w95 h34", _T("Save"), Commit, "btnprimary")
    AddBtn(g, "x555 y518 w95 h34", _T("Cancel"), (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Close", (*) => (FinishRec(), g.Destroy()))
    g.OnEvent("Escape", (*) => (Rec.ih ? 0 : (FinishRec(), g.Destroy())))     ; Esc while recording belongs to the recorder
    Toggle()
    ApplyTheme(g)
    ShowOver(g, "w660 h568", Main)
}

Num(v) => IsInteger(v) ? Integer(v) : 0

; text pasted with Unix line ends (only LF - e.g. code copied from a web page) shows as one long line in a Windows
; edit box: turn every lone LF into CR LF and keep the caret where it was
FixLineEnds(ed, *) {
    h := ed.Hwnd
    n := DllCall("GetWindowTextLengthW", "Ptr", h)
    buf := Buffer((n + 1) * 2, 0)
    DllCall("GetWindowTextW", "Ptr", h, "Ptr", buf, "Int", n + 1)
    raw := StrGet(buf, n, "UTF-16")
    if !RegExMatch(raw, "(?<!`r)`n")
        return
    s := 0, e := 0
    DllCall("SendMessageW", "Ptr", h, "UInt", 0xB0, "UInt*", &s, "UInt*", &e)      ; EM_GETSEL
    RegExReplace(SubStr(raw, 1, e), "(?<!`r)`n", "", &add)
    DllCall("SetWindowTextW", "Ptr", h, "Str", RegExReplace(raw, "(?<!`r)`n", "`r`n"))
    SendMessage(0xB1, e + add, e + add, h)                                        ; EM_SETSEL
    SendMessage(0xB7, 0, 0, h)                                                    ; EM_SCROLLCARET
}

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

; a pause between steps, exact to about a millisecond. A plain Sleep can last up to ~15 ms longer than asked
; (Windows timer ticks), so the same macro could play at a different speed each time. Here most of the wait is a
; normal Sleep (the app stays responsive), the rest is measured with the performance counter in 1 ms steps.
; 0 still lets Windows and the app breathe (Sleep -1 = handle messages, no wait).
; (idea: thqby/ahk2_lib HighPrecisionSleep, MIT - done here without machine code)
; exact = false: the timing of macros made before this existed (a plain Sleep - short delays last ~10-15 ms longer)
StepWait(ms, exact := true) {
    static f := 0
    if (ms <= 0) {
        Sleep -1
        return
    }
    if !exact {
        Sleep ms
        return
    }
    if !f
        DllCall("QueryPerformanceFrequency", "Int64*", &f)
    DllCall("QueryPerformanceCounter", "Int64*", &t := 0)
    stop := t + ms * f / 1000
    if (ms > 20)
        Sleep ms - 16
    loop {
        DllCall("QueryPerformanceCounter", "Int64*", &t)
        left := (stop - t) * 1000 / f
        if (left <= 0)
            break
        if (left > 1.5)
            DllCall("Sleep", "UInt", 1)                 ; ~1 ms (timeBeginPeriod 1 is on while a macro plays)
    }
}

; repeated macros: one cycle takes at least this long, so a macro with 0 ms delays can't flood
; Windows with thousands of key events per second (that blocks the whole keyboard, even after the app is closed)
CycleFloor(t0) {
    rest := 10 - (A_TickCount - t0)
    if (rest > 0)
        Sleep rest
}

; ============ type: move + actions ============
RunMove(m, trig, once := false) {
    global MacroBusy
    MacroBusy++
    DllCall("winmm\timeBeginPeriod", "UInt", 1)       ; 1 ms timer while playing (exact delays)
    try RunMove2(m, trig, once)
    finally {
        DllCall("winmm\timeEndPeriod", "UInt", 1)     ; also when the macro stops with an error
        MacroBusy--
    }
}

RunMove2(m, trig, once) {
    ex := m["exact"]
    dirs := SplitKeys(m["dirs"])
    acts := SplitKeys(m["actions"])
    if !acts.Length
        return
    g1 := m["g1"], g2 := m["g2"], g3 := m["g3"], ge := m["ge"]
    di := 1, ai := 1, n := 0
    rep := !once && m["repeat"] && !IsWheel(trig)          ; a wheel can't be held
    while (rep ? Active(m, trig) : n < acts.Length) {      ; once = every action one time
        t0 := A_TickCount
        n++
        key := acts[ai]
        if dirs.Length {
            dir := dirs[di]
            KeyDown(dir)      ; 1. direction down (all keys of a chord together)
            StepWait(g1, ex)
            KeyDown(key)      ; 2. action down
            StepWait(g2, ex)
            KeyUp(dir)        ; 3. direction up
            StepWait(g3, ex)
            KeyUp(key)        ; 4. action up
            di := di >= dirs.Length ? 1 : di + 1
        } else {                   ; no movement: action only
            KeyDown(key)
            StepWait(g2, ex)
            KeyUp(key)
        }
        StepWait(ge, ex)
        ai := ai >= acts.Length ? 1 : ai + 1
        if rep
            CycleFloor(t0)
    }
    ReleaseAll(dirs)
    ReleaseAll(acts)
    if (!rep && !IsWheel(trig))
        try KeyWait(TrigMain(trig))          ; "once": don't restart until the key is released
}

; ============ type: custom sequence ============
RunSeq(m, trig, once := false) {
    global MacroBusy
    MacroBusy++
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    try RunSeq2(m, trig, once)
    finally {
        DllCall("winmm\timeEndPeriod", "UInt", 1)
        MacroBusy--
    }
}

RunSeq2(m, trig, once) {
    ex := m["exact"]
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
    rep := !once && m["repeat"] && !IsWheel(trig)
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
            StepWait(s[3], ex)
        }
        if !rep
            stop := true
        else if !stop
            CycleFloor(t0)
    }
    ReleaseAll(used)
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
        if (GetKeyState(k) && !GetKeyState(k, "P") && !ForeignMod.Has(GetKeyVK(k)))
            Send "{Blind}{" k " up}"
}

; Ctrl / Alt / Shift / Win pressed by another program (mouse software with Shift on a button, Steam Input, remote
; desktop) are held on purpose - ModWatch leaves them alone. The hook doesn't see this app's own Send (I1) and a key
; on the keyboard is physical, so a modifier that goes down here without being physically held comes from another
; program. AltGr's fake Left Ctrl (scan code 0x21D) is not one of them.
ModHookStart() {
    ih := InputHook("V I1 L0")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "N")
    ih.OnKeyDown := ModForeignDown
    ih.OnKeyUp := ModForeignUp
    ih.Start()
}
ModForeignDown(ih, vk, sc) {
    if (sc != 0x21D && !GetKeyState(Format("vk{:x}", vk), "P"))
        ForeignMod[vk] := true
}
ModForeignUp(ih, vk, sc) {
    if ForeignMod.Has(vk)
        ForeignMod.Delete(vk)
}

; every 250 ms: Ctrl / Alt / Shift / Win down for Windows but not held on the keyboard for over a second -> released
; (unless another program holds it, see ModHookStart)
ModWatch() {
    static mods := ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"], since := Map()
    if (MacroBusy > 0 || Rec.ih || GetKeyState("RAlt", "P")) {      ; a macro is playing, recording, or AltGr is held
        since.Clear()
        return
    }
    for k in mods {
        vk := GetKeyVK(k)
        if (!GetKeyState(k) && ForeignMod.Has(vk))
            ForeignMod.Delete(vk)
        if (GetKeyState(k) && !GetKeyState(k, "P") && !ForeignMod.Has(vk)) {
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
        if (cur != AssetVersion || !FileExist(IconFile) || !FileExist(LogoFile) || !FileExist(SwOnFile) || !FileExist(LogoWideFile) || !FileExist(CbDarkFile) || !FileExist(FlagFile("de"))) {
            B64ToFile(IconB64(), IconFile)
            B64ToFile(LogoB64(), LogoFile)
            B64ToFile(SwOffB64(), SwOffFile)
            B64ToFile(SwOnB64(), SwOnFile)
            B64ToFile(LogoWideB64(), LogoWideFile)
            B64ToFile(CbDarkB64(), CbDarkFile)
            B64ToFile(CbLightB64(), CbLightFile)
            for c in LangOrder
                B64ToFile(FlagB64(c), FlagFile(c))
            for old in ["badge_main.png", "badge_dk.png", "badge_lt.png", "discord.png", "discord_hov.png"]    ; pictures of older versions (the "!" and the Discord button are drawn now)
                try FileDelete(AssetsDir "\" old)
            WriteText(verFile, AssetVersion)
            RebrandExe()                                                     ; new icon: the program file shows it too
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
        FileCreateShortcut(lp[1], lnk, target, lp[2], "ComboCrown", icon)
        SetLnkAppId(lnk, AppId())
    }
}

; ============ app identity (Windows notifications, taskbar) ============
; Windows shows a notification with the name and icon of the app's AppUserModelID. Without an own one it makes one
; from the exe - a renamed AutoHotkey, so the notice said "AutoHotkey" with its green icon. The shortcuts get the
; same id, so the taskbar still groups the running app with a pinned shortcut.
AppId() => UpdBranch = "beta" ? "vavr0s.MacroManager.Beta" : "vavr0s.MacroManager"

SetAppIdentity() {
    id := AppId()
    try DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "WStr", id)
    try RegDeleteKey("HKCU\Software\Classes\AppUserModelId\VAVROS.MacroManager" (UpdBranch = "beta" ? ".Beta" : ""))   ; (old name, beta 1.22.9)
    png := AssetsDir "\notify_" AssetVersion ".png"
    if !FileExist(png)
        try IcoToPng(IconFile, png)
    k := "HKCU\Software\Classes\AppUserModelId\" id
    try {
        RegWrite(UpdBranch = "beta" ? "ComboCrown (beta)" : "ComboCrown", "REG_SZ", k, "DisplayName")
        if FileExist(png)
            RegWrite(png, "REG_SZ", k, "IconUri")
    } catch as e
        DiagLog("SetAppIdentity", e)
    lnk := UpdBranch = "beta" ? "ComboCrown Beta.lnk" : "ComboCrown.lnk"
    old := UpdBranch = "beta" ? "Macro Manager Beta.lnk" : "Macro Manager.lnk"       ; the app's name before 1.24
    for dir in [A_Programs, A_Desktop] {                       ; shortcuts made by older versions
        if (FileExist(dir "\" old) && !FileExist(dir "\" lnk)) {   ; the shortcut (and so the notifications) get the new name
            tgt := "", args := ""
            try FileGetShortcut(dir "\" old, &tgt, , &args)
            if InStr(tgt " " args, A_ScriptDir "\")             ; only a shortcut of this install (not of another copy)
                try FileMove(dir "\" old, dir "\" lnk)
        }
        if FileExist(dir "\" lnk)
            SetLnkAppId(dir "\" lnk, id)
    }
}

; the branded interpreter of an installed copy gets the current name and icon too (installed by an older version).
; The running .exe can't be overwritten, but it can be moved aside: patched copy -> its place, old one -> .bak
RebrandExe() {
    exe := A_ScriptDir "\Macro Manager.exe"
    if (A_AhkPath != exe)
        return
    try {
        FileCopy(exe, exe ".new", 1)
        if !PatchExe(exe ".new", IconFile)
            throw Error("patch")
        FileMove(exe, exe ".bak", 1)
        FileMove(exe ".new", exe)
    } catch {
        try FileDelete(exe ".new")
        if !FileExist(exe)
            try FileMove(exe ".bak", exe)
    }
}

; the largest picture of the app icon as a PNG file (the icon keeps its big sizes as PNG inside)
IcoToPng(ico, png) {
    b := FileRead(ico, "RAW")
    n := NumGet(b, 4, "UShort"), best := 0, bestSz := 0
    loop n {
        e := 6 + (A_Index - 1) * 16
        w := NumGet(b, e, "UChar") || 256
        if (w > bestSz)
            bestSz := w, best := e
    }
    size := NumGet(b, best + 8, "UInt"), off := NumGet(b, best + 12, "UInt")
    if (NumGet(b, off, "UInt") != 0x474E5089)                   ; not a PNG inside ("\x89PNG")
        return
    f := FileOpen(png, "w")
    f.RawWrite(b.Ptr + off, size)
    f.Close()
}

; System.AppUserModel.ID of a shortcut (only written when it differs)
SetLnkAppId(lnk, id) {
    static iid := 0, key := 0
    if !iid {
        iid := Buffer(16), key := Buffer(20)
        DllCall("ole32\CLSIDFromString", "WStr", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}", "Ptr", iid)     ; IPropertyStore
        DllCall("ole32\CLSIDFromString", "WStr", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", "Ptr", key)     ; PKEY_AppUserModel_ID
        NumPut("UInt", 5, key, 16)
    }
    ps := 0
    if DllCall("shell32\SHGetPropertyStoreFromParsingName", "WStr", lnk, "Ptr", 0, "Int", 2, "Ptr", iid, "Ptr*", &ps)   ; GPS_READWRITE
        return
    try {
        pv := Buffer(24, 0)
        ComCall(5, ps, "Ptr", key, "Ptr", pv)                    ; GetValue
        same := NumGet(pv, 0, "UShort") = 31 && StrGet(NumGet(pv, 8, "Ptr")) = id
        DllCall("ole32\PropVariantClear", "Ptr", pv)
        if !same {
            NumPut("UShort", 31, pv, 0), NumPut("Ptr", StrPtr(id), pv, 8)       ; VT_LPWSTR
            ComCall(6, ps, "Ptr", key, "Ptr", pv)                ; SetValue
            ComCall(7, ps)                                       ; Commit
        }
    }
    ObjRelease(ps)
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
    DarkMenus(DarkOn)
    ApplyTheme(Main)
    if LibGui
        ApplyTheme(LibGui)
}

; tray menu in the app's look: dark or light, whatever Windows uses
; (SetPreferredAppMode / FlushMenuThemes, uxtheme ordinals 135 / 136 - as in nperovic/GuiEnhancerKit, MIT)
DarkMenus(on) {
    try {
        ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
        setMode := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr")
        flush := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr")
        if (setMode && flush && VerCompare(A_OSVersion, "10.0.18362") >= 0) {
            DllCall(setMode, "Int", on ? 2 : 3)         ; 2 = always dark, 3 = always light
            DllCall(flush)
        }
    }
}

SetTheme(hwnd, name := "", sub := "") {
    if (name = "")
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Ptr", 0, "Ptr", 0)      ; back to the default theme
    else
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", name, "Ptr", sub = "" ? 0 : StrPtr(sub))
}

; [fill, text] or [fill, text, border] - light mode buttons get a thin border so they stand out from the window
RoleColors(role, hover := false) {
    d := DarkOn
    switch role {
        case "btnprimary":
            if d
                return hover ? ["E3C486", "141414"] : ["D0AE6B", "141414"]
            return hover ? ["DDBB78", "141414", "B08D4E"] : ["D0AE6B", "141414", "B08D4E"]
        case "btndanger":
            if d
                return hover ? ["55292F", "FFB4B4"] : ["3B2226", "FF9C9C"]
            return hover ? ["F0C4C4", "9E1F18", "D69494"] : ["F6D9D9", "9E1F18", "E2AEAE"]
        case "btnghost":
            if d
                return hover ? ["1F2127", "ECECEF"] : ["15161A", "A9ADB8"]
            return hover ? ["DCDDE4", "1B1B1F", "BDBEC8"] : ["EBEBF0", "3E3E48", "D3D3DB"]
        case "btnbanner":
            return hover ? ["3A3E49", "E3C486"] : ["22242B", "D0AE6B"]
        case "btnupd0":
            return hover ? ["3A3E49", "B8BCC8"] : ["22242B", "6E7380"]
        case "btnupd1":
            return hover ? ["3FE07F", "FFFFFF"] : ["1FB95A", "FFFFFF"]      ; + radar halo (UpdPulseTick)
        case "hdr":
            return d ? ["1F2127", "A9ADB8"] : ["E9E9EE", "5A5A66"]
        case "libhead":                                                    ; title strip of the library panel
            return ["000000", "D0AE6B"]
        case "btndiscord":                                                 ; Discord Blurple (help banner)
            return hover ? ["4752C4", "FFFFFF"] : ["5865F2", "FFFFFF"]
        default:    ; plain button
            if d
                return hover ? ["3A3E49", "FFFFFF"] : ["2A2D35", "ECECEF"]
            return hover ? ["CBCCD6", "111114", "AEB0BC"] : ["DCDDE4", "111114", "BDBEC8"]
    }
}

; flat "button" = a clickable text control with its own colours (no system border)
; the button is drawn by the app itself (owner-drawn text control, see DrawBtn): rounded, smooth corners.
; round = false: square (rows of the drop-down lists)
AddBtn(g, opts, text, handler, role := "btn", round := true) {
    c := g.AddText(RegExReplace(opts, "i)\bLeft\b") " +0xD", text)      ; SS_OWNERDRAW ("Left" would clear it; DrawBtn aligns)
    c.OnEvent("Click", handler)
    Roles[c.Hwnd] := role
    BtnLook[c.Hwnd] := {left: InStr(opts, "Left") > 0, round: round, hover: false, badge: false, pad: [0, 0, 0, 0]}
    return c
}

PaintBtn(hwnd, hover) {
    try {
        if BtnLook.Has(hwnd)
            BtnLook[hwnd].hover := hover
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 0)     ; repaint without erasing first: no flicker
        for pic, btn in BtnAlias                                       ; a picture lying on the button (a flag):
            if (btn = hwnd) {                                          ; button first, then the picture on top again
                DllCall("UpdateWindow", "Ptr", hwnd)
                DllCall("RedrawWindow", "Ptr", pic, "Ptr", 0, "Ptr", 0, "UInt", 0x105)   ; invalidate + erase + now
            }
    }
}

; WM_DRAWITEM of a flat button: background of the window in the corners, rounded fill (GDI+, anti-aliased),
; text in the middle. Drawn into a memory bitmap first, so hovering does not flicker.
; (rounded colour buttons: idea of nperovic/ColorButton.ahk, MIT)
DrawBtn(wParam, lParam, *) {
    static ps := A_PtrSize
    if (NumGet(lParam, 0, "UInt") != 5)                       ; ODT_STATIC only
        return
    h := NumGet(lParam, ps = 8 ? 24 : 20, "Ptr")
    if !(Roles.Has(h) && BtnLook.Has(h))
        return
    dc := NumGet(lParam, ps = 8 ? 32 : 24, "Ptr")
    rcOff := ps = 8 ? 40 : 28
    w := NumGet(lParam, rcOff + 8, "Int") - NumGet(lParam, rcOff, "Int")
    hh := NumGet(lParam, rcOff + 12, "Int") - NumGet(lParam, rcOff + 4, "Int")
    if (w < 1 || hh < 1)
        return true
    lk := BtnLook[h]
    role := Roles[h]
    s := A_ScreenDPI / 96
    winBg := DarkOn ? "15161A" : "F5F5F7"
    mdc := DllCall("CreateCompatibleDC", "Ptr", dc, "Ptr")
    bmp := DllCall("CreateCompatibleBitmap", "Ptr", dc, "Int", w, "Int", hh, "Ptr")
    obmp := DllCall("SelectObject", "Ptr", mdc, "Ptr", bmp, "Ptr")
    r := Buffer(16, 0)
    if (role = "badge") {                                      ; the yellow "!" on its own (help window, dialogs)
        FillHex(mdc, 0, 0, w, hh, winBg)
        if GdipOn() {
            gr := GrOn(mdc)
            DrawBadge(gr, w / 2, hh / 2, Min(w, hh) / 2, "")
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        }
    } else {
        disabled := !DllCall("IsWindowEnabled", "Ptr", h)      ; (itemState of a static says "disabled" on Windows even when it is not)
        col := RoleColors(disabled && role = "btnprimary" ? "btn" : role, lk.hover)     ; a disabled gold button looks plain
        under := (role = "btnbanner" || role = "btndiscord" || SubStr(role, 1, 6) = "btnupd") ? "000000" : winBg
        ; the button itself may be smaller than the control (room for the "!" badge of the help button)
        fx := Round(lk.pad[1] * s), fy := Round(lk.pad[2] * s)
        fw := w - fx - Round(lk.pad[3] * s), fh := hh - fy - Round(lk.pad[4] * s)
        FillHex(mdc, 0, 0, w, hh, lk.round ? under : col[1])
        if (lk.round && GdipOn()) {
            d := Min(fh, Round(12 * s)) + 0.0
            gr := GrOn(mdc)
            b := Round(s)                                       ; border width
            if (col.Length >= 3) {
                FillRound(gr, fx, fy, fw, fh, d, col[3])        ; border = outer shape, fill = shape inside it
                FillRound(gr, fx + b, fy + b, fw - 2 * b, fh - 2 * b, Max(2, d - 2 * b), col[1])
            } else
                FillRound(gr, fx, fy, fw, fh, d, col[1])
            if (lk.badge && HelpBadgeOn)
                DrawBadge(gr, fx + fw, fy + 6 * s, 8 * s, under)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        } else if lk.round
            FillHex(mdc, fx, fy, fw, fh, col[1])
        txt := ""
        try txt := GuiCtrlFromHwnd(h).Text
        font := SendMessage(0x31, 0, 0, h)                      ; WM_GETFONT
        of := DllCall("SelectObject", "Ptr", mdc, "Ptr", font, "Ptr")
        DllCall("SetBkMode", "Ptr", mdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", mdc, "UInt", Bgr(disabled ? (DarkOn ? "6E7380" : "A0A0AA") : col[2]))
        NumPut("Int", fx, "Int", fy, "Int", fx + fw, "Int", fy + fh, r)
        if (role = "btndiscord") {                              ; Discord symbol + text, centred together
            sz := Buffer(8, 0)
            DllCall("GetTextExtentPoint32W", "Ptr", mdc, "WStr", txt, "Int", StrLen(txt), "Ptr", sz)
            ih := Round(fh * 0.4), iw := ih * 126.644 / 96, gap := Round(8 * s)
            x0 := Round(fx + (fw - iw - gap - NumGet(sz, 0, "Int")) / 2)
            if GdipOn() {
                gr := GrOn(mdc)
                DrawDiscord(gr, x0, fy + (fh - ih) / 2, ih, col[2])
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
            }
            NumPut("Int", Round(x0 + iw + gap), r)
            DllCall("DrawTextW", "Ptr", mdc, "WStr", txt, "Int", -1, "Ptr", r, "UInt", 0x824)
        } else if (StrLen(txt) = 1 && !lk.left && GlyphCenter(mdc, txt, fw, fh, &gx, &gy))
            DllCall("TextOutW", "Ptr", mdc, "Int", fx + gx, "Int", fy + gy, "WStr", txt, "Int", 1)   ; icon (?, arrow, ×): the drawn shape itself centred
        else
            DllCall("DrawTextW", "Ptr", mdc, "WStr", txt, "Int", -1, "Ptr", r, "UInt", 0x824 | (lk.left ? 0 : 1))   ; SINGLELINE VCENTER NOPREFIX (+CENTER)
        DllCall("SelectObject", "Ptr", mdc, "Ptr", of, "Ptr")
    }
    DllCall("BitBlt", "Ptr", dc, "Int", NumGet(lParam, rcOff, "Int"), "Int", NumGet(lParam, rcOff + 4, "Int"), "Int", w, "Int", hh, "Ptr", mdc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", obmp, "Ptr")
    DllCall("DeleteObject", "Ptr", bmp)
    DllCall("DeleteDC", "Ptr", mdc)
    return true
}

FillHex(dc, x, y, w, h, hex) {
    r := Buffer(16, 0)
    NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, r)
    br := DllCall("CreateSolidBrush", "UInt", Bgr(hex), "Ptr")
    DllCall("FillRect", "Ptr", dc, "Ptr", r, "Ptr", br)
    DllCall("DeleteObject", "Ptr", br)
}

GrOn(dc) {
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &gr := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)        ; anti-alias
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)      ; half-pixel: crisp straight edges
    return gr
}

; "new release notes" badge: gold circle with a dark "!", all drawn as shapes (sharp at any size / display scale).
; ring = colour of a thin outline that separates it from what it overlaps ("" = none)
DrawBadge(gr, cx, cy, ro, ring) {
    ri := ro
    if (ring != "") {
        FillRound(gr, cx - ro, cy - ro, 2 * ro, 2 * ro, 2 * ro, ring)
        ri := ro - 1.5 * A_ScreenDPI / 96
    }
    FillRound(gr, cx - ri, cy - ri, 2 * ri, 2 * ri, 2 * ri, "F2C94C")
    bw := Max(1.6, ri * 0.34)                                   ; the bar of the "!"
    FillRound(gr, cx - bw / 2, cy - ri * 0.62, bw, ri * 0.82, bw, "1B1B1F")
    dr := Max(0.9, ri * 0.19)                                   ; its dot
    FillRound(gr, cx - dr, cy + ri * 0.50 - dr, 2 * dr, 2 * dr, 2 * dr, "1B1B1F")
}

; the official Discord symbol (vector, from discord.com/branding), h pixels tall, top-left at x, y
DrawDiscord(gr, x, y, h, hex) {
    static shape := [[81.15, 0, 79.91, 2.2, 78.8, 4.47, 77.79, 6.79, 68.19, 5.35, 58.42, 5.35, 48.8, 6.79, 47.81, 4.47, 46.67, 2.2, 45.44, 0, 36.42, 1.54, 27.63, 4.24, 19.3, 8.06, 2.78, 32.53, -1.69, 56.37, 0.53, 79.89, 10.2, 87.03, 21.04, 92.49, 32.58, 95.97, 35.18, 92.49, 37.48, 88.78, 39.45, 84.91, 35.71, 83.52, 32.1, 81.78, 28.64, 79.76, 29.55, 79.1, 30.43, 78.42, 31.29, 77.76, 51.57, 87.31, 75.06, 87.31, 95.37, 77.76, 96.23, 78.47, 97.11, 79.15, 98.02, 79.76, 94.56, 81.81, 90.95, 83.52, 87.19, 84.94, 89.16, 88.8, 91.45, 92.51, 94.06, 96, 105.6, 92.51, 116.43, 87.08, 126.11, 79.94, 128.73, 52.66, 121.61, 29.02, 107.29, 8.08, 98.98, 4.27, 90.19, 1.57, 81.18, 0.05, 81.18, 0.05, 81.15, 0, 81.15, 0],
        [42.28, 65.41, 36.04, 65.41, 30.86, 59.76, 30.86, 52.76, 30.86, 45.76, 35.84, 40.08, 42.26, 40.08, 48.67, 40.08, 53.77, 45.79, 53.67, 52.76, 53.57, 59.73, 48.64, 65.41, 42.28, 65.41],
        [84.36, 65.41, 78.09, 65.41, 72.97, 59.76, 72.97, 52.76, 72.97, 45.76, 77.94, 40.08, 84.36, 40.08, 90.77, 40.08, 95.85, 45.79, 95.75, 52.76, 95.65, 59.73, 90.72, 65.41, 84.36, 65.41]]
    k := h / 96
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)        ; alternate fill: the eyes stay holes
    for sub in shape {
        pts := Buffer(sub.Length * 4)
        for i, v in sub
            NumPut("Float", (i & 1 ? x : y) + v * k, pts, (i - 1) * 4)
        DllCall("gdiplus\GdipAddPathBeziers", "Ptr", pa, "Ptr", pts, "Int", sub.Length // 2)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", pa)
    }
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" hex), "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; the badge as its own control (help window, release notes dialog)
AddBadge(g, opts) {
    c := g.AddText(opts " +0xD")
    Roles[c.Hwnd] := "badge"
    BtnLook[c.Hwnd] := {left: false, round: false, hover: false, badge: false, pad: [0, 0, 0, 0]}
    return c
}

; shows / hides the badge on the help button in the banner
SetHelpBadge(on) {
    global HelpBadgeOn
    HelpBadgeOn := on
    try DllCall("InvalidateRect", "Ptr", bHelp.Hwnd, "Ptr", 0, "Int", 0)
}

FillRound(gr, x, y, w, h, d, hex) {
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)
    x2 := x + w - d, y2 := y + h - d
    for a in [[x, y, 180], [x2, y, 270], [x2, y2, 0], [x, y2, 90]]
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pa, "Float", a[1], "Float", a[2], "Float", d, "Float", d, "Float", a[3], "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", pa)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" hex), "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; top-left text position that puts the visible shape of one character exactly in the middle of a w x h box
; (DrawText centres the character cell, whose empty space above / beside the shape differs per font)
GlyphCenter(dc, ch, w, h, &x, &y) {
    gm := Buffer(20, 0), mat := Buffer(16, 0)
    NumPut("Short", 0, "Short", 1, "Short", 0, "Short", 0, "Short", 0, "Short", 0, "Short", 0, "Short", 1, mat)   ; identity MAT2
    if (DllCall("GetGlyphOutlineW", "Ptr", dc, "UInt", Ord(ch), "UInt", 0, "Ptr", gm, "UInt", 0, "Ptr", 0, "Ptr", mat, "UInt") = 0xFFFFFFFF)
        return false
    bw := NumGet(gm, 0, "UInt"), bh := NumGet(gm, 4, "UInt")
    ox := NumGet(gm, 8, "Int"), oy := NumGet(gm, 12, "Int")       ; black box corner from the origin (y up)
    tm := Buffer(60, 0)
    DllCall("GetTextMetricsW", "Ptr", dc, "Ptr", tm)
    asc := NumGet(tm, 4, "Int")                                     ; baseline below the top of the cell
    x := Round((w - bw) / 2 - ox)
    y := Round((h - bh) / 2 + oy - asc)
    return bw > 0 && bh > 0
}

Bgr(hex) {
    v := Integer("0x" hex)
    return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
}

; GDI+ started once (also used for the list check boxes)
GdipOn() {
    static tok := 0
    if !tok {
        try {
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", 1, si)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
        }
    }
    return tok != 0
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
    ; Windows 11: title bar and border in the app's own colours (DWMWA_BORDER / CAPTION / TEXT_COLOR)
    if (VerCompare(A_OSVersion, "10.0.22000") >= 0) {
        for attr, col in Map(34, dark ? "2A2D35" : "D6D6DE", 35, win, 36, txt) {
            rgb := Integer("0x" col)
            NumPut("UInt", ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16), flag)     ; COLORREF = 0x00BBGGRR
            try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", attr, "Ptr", flag, "Int", 4)
        }
    }
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
                        c.SetFont("s9")                     ; colours: DrawBtn
                    } else
                        c.SetFont("c" (role = "hint" ? hint : txt))
                case "Edit":
                    c.Opt("Background" box)
                    if (ControlGetStyle(hwnd) & 0x4)               ; multi-line (help text, script, sequence): dark scroll bars too
                        SetTheme(hwnd, dark ? "DarkMode_Explorer" : "")
                    else
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
                case "ComboBox":                                   ; (the game field of the share form)
                    c.Opt("Background" box)
                    c.SetFont("c" txt)
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
    try {
        GdipOn()
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
    x1 := (sub = 4) ? Max(x0 + w, cw) : x0 + w
    st := SendMessage(0x102C, row, 0xF002, h)                 ; LVM_GETITEMSTATE
    sel := (st & 2) != 0
    if sel {
        bg := DarkOn ? 0x3A3626 : 0xF3E7C9
        fg := DarkOn ? 0xFFFFFF : 0x1B1B1F
    } else {
        bg := DarkOn ? 0x1F2127 : 0xFFFFFF
        fg := DarkOn ? 0xECECEF : 0x1B1B1F
    }
    bgc := ((bg & 0xFF) << 16) | (bg & 0xFF00) | (bg >> 16)
    fgr := ((fg & 0xFF) << 16) | (fg & 0xFF00) | (fg >> 16)
    r := Buffer(16)
    NumPut("Int", x0, "Int", top, "Int", x1, "Int", bot, r)
    br := DllCall("CreateSolidBrush", "UInt", bgc, "Ptr")
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
    if (sub = 4) {                                            ; share icon: gold = already in the macro library
        m := (row < View.Length) ? View[row + 1] : 0
        if (m && m["type"] != "script") {
            static icoFont := 0
            if !icoFont
                icoFont := DllCall("CreateFontW", "Int", -Round(16 * A_ScreenDPI / 96), "Int", 0, "Int", 0, "Int", 0, "Int", 400
                    , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0, "Str", "Segoe MDL2 Assets", "Ptr")
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", icoFont, "Ptr")
            DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
            ; green arrow = its author has a new version / dim arrow = downloaded, unchanged /
            ; gold = shared (with a dot: changed since, can be updated in Macro Hub) / grey = not shared
            newer := LibNew.Has(m), fromLib := !newer && LibFromLib(m), dot := !newer && !fromLib && LibSharedChanged(m)
            DllCall("SetTextColor", "Ptr", hdc, "UInt", newer ? 0x5AB91F : fromLib ? (DarkOn ? 0x80736E : 0xAAA0A0)
                : m["libshare"] != "" ? 0x6BAED0 : (DarkOn ? 0x9C8F8A : 0x867A7A))   ; (BGR: green / dim / gold / grey)
            NumPut("Int", x0, "Int", top, "Int", x0 + w, "Int", bot, r)
            DllCall("DrawTextW", "Ptr", hdc, "WStr", Chr(newer || fromLib ? 0xE896 : 0xE72D), "Int", 1, "Ptr", r, "UInt", 0x825)   ; centred
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            if (dot && GdipOn()) {
                gr := GrOn(hdc)
                ds := 7 * A_ScreenDPI / 96
                FillRound(gr, x0 + w / 2 + 6 * A_ScreenDPI / 96, top + (bot - top) / 2 - 10 * A_ScreenDPI / 96, ds, ds, ds, "F2C94C")
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
            }
        }
        return 4
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

; do two profile lists ("a|b") share a profile?
ProfOverlap(a, b) {
    for p in StrSplit(a, "|")
        if (p != "" && HasProf(b, p))
            return true
    return false
}

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
        b := AddBtn(g, "x1 y" y " w" W " h32 Left", "             " LangNames[code], SetLang.Bind(code), cur ? "btnprimary" : "btn", false)
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
        AddBtn(g, "x1 y" y " w" W " h32 Left", (cur ? "  ✓   " : "       ") pn, ProfPick.Bind(pn), cur ? "btnprimary" : "btn", false)
        y += 32
    }
    y += 1                                       ; 1px separator (the window colour shows through)
    AddBtn(g, "x1 y" y " w" W " h32 Left", "  +   " _T("New profile..."), (*) => (ClosePop(), NewProfile()), "btn", false)
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       " _T("Rename current..."), (*) => (ClosePop(), RenameProfile()), "btn", false)
    y += 32
    AddBtn(g, "x1 y" y " w" W " h32 Left", "       " _T("Delete current"), (*) => (ClosePop(), DeleteProfile()), "btndanger", false)
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
    if (ThemedAsk("ComboCrown", "", _T("Delete profile `"{1}`"?`n`nMacros that belong only to this profile are moved to the first remaining profile.", CurProfile), [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
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

; release notes of this version in a language (English when there is no translation)
NotesFor(lang) => (lang != "en" && ReleaseNotesL.Has(lang) && ReleaseNotesL[lang] != "") ? ReleaseNotesL[lang] : ReleaseNotes

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
    apps := p.AddListView("x10 y32 w380 r11 -Hdr -E0x200 -Multi", [_T("Application")])
    for it in items
        apps.Add("", it[1] "   -   " (StrLen(it[2]) > 45 ? SubStr(it[2], 1, 45) "..." : it[2]))
    apps.ModifyCol(1, 355)
    Choose(*) {
        n := apps.GetNext()
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
    apps.OnEvent("DoubleClick", Choose)
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

; HTTP request that waits with Sleep instead of blocking: hotkeys and running macros keep working meanwhile.
; returns Map(status, text, etag[, body]) or 0 (error / timeout).  body: text to send (POST), plain ASCII
HttpSend(url, hdrs, timeoutMs := 8000, wantBody := false, method := "GET", body := "") {
    r := 0
    try {
        r := ComObject("Msxml2.ServerXMLHTTP.6.0")          ; WinHTTP based, asynchronous, no browser cache
        r.setTimeouts(3000, 3000, 8000, 15000)
        r.open(method, url, true)
    } catch {
        r := 0
    }
    if !r
        return HttpSendSync(url, hdrs, wantBody, method, body)
    try {
        r.setRequestHeader("User-Agent", "MacroManager")
        for k, v in hdrs
            r.setRequestHeader(k, v)
        if (body = "")
            r.send()
        else
            r.send(body)
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
HttpSendSync(url, hdrs, wantBody, method := "GET", body := "") {
    try {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(3000, 3000, 8000, 15000)
        r.Open(method, url, false)
        r.SetRequestHeader("User-Agent", "MacroManager")
        for k, v in hdrs
            r.SetRequestHeader(k, v)
        if (body = "")
            r.Send()
        else
            r.Send(body)
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

; silent background check: keeps the banner arrow up to date while the app keeps running.
; At most every 15 minutes: GitHub allows 60 questions an hour per internet address - several copies of the app
; (or several people behind one address) would use that up, and then a new version shows up only minutes later.
; A click on the arrow always asks right away.
AutoCheck(minAge := 900000) {
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
    static apiPause := 0                          ; GitHub said "too many questions": skip its API for a while
    hdr := Map("Accept", "application/vnd.github.raw+json")
    if (UpdEtag != "")
        hdr["If-None-Match"] := UpdEtag
    st := 0, info := ""
    ; first the Macro Hub server: it reads GitHub for everybody (GitHub's API allows only 60 questions an hour per
    ; internet address - a few apps behind one connection used them up); GitHub itself when the server can't answer
    r := HttpSend(UpdServer "/version?branch=" UpdBranch, Map("Cache-Control", "no-cache"))
    if (r && r["status"] = 200 && InStr(r["text"], '"sha256"'))
        info := r["text"]
    if (info = "" && A_TickCount >= apiPause)
        info := HttpReq("https://api.github.com/repos/" UpdRepo "/contents/version.json?ref=" UpdBranch, hdr, &st, &et)
    if (st = 403 || st = 429)
        apiPause := A_TickCount + 1800000          ; 30 minutes (the limit resets within the hour)
    if (st = 304)
        info := UpdBody
    else if (st = 200 && info != "")
        UpdEtag := et, UpdBody := info
    else if (info = "")
        info := HttpGet(UpdateUrl "?t=" A_TickCount)      ; API unavailable or rate limited: use the (cached) raw file
    if (!RegExMatch(info, '"version"\s*:\s*"([^"]+)"', &mv)
        || !RegExMatch(info, '"url"\s*:\s*"([^"]+)"', &mu)
        || !RegExMatch(info, '"sha256"\s*:\s*"([0-9a-fA-F]{64})"', &ms))
        return "error"
    notes := ""                                   ; release notes in the app language, English if not translated
    for key in (Lang = "en" ? ["notes"] : ["notes_" Lang, "notes"])
        if (notes = "" && RegExMatch(info, '"' key '"\s*:\s*"((?:[^"\\]|\\.)*)"', &mn))
            notes := JsonUnesc(mn[1])
    UpdInfo := Map("ver", mv[1], "url", mu[1], "sha", StrLower(ms[1]), "notes", notes)
    UpdAvail := VerNewer(mv[1], AppVersion) && RegExMatch(mu[1], "^https://raw\.githubusercontent\.com/vavr0s/")
    SetUpdIcon()
    return UpdAvail ? "new" : "latest"
}

; a JSON string value as text: \n \" \\ \/ \t and \uXXXX (version.json keeps accented letters as \uXXXX, so the
; text arrives right whatever character set the answer is read with)
JsonUnesc(s) {
    out := "", i := 1, n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c != "\" || i = n) {
            out .= c, i++
            continue
        }
        e := SubStr(s, i + 1, 1)
        if (e = "u" && RegExMatch(SubStr(s, i + 2, 4), "^[0-9a-fA-F]{4}$")) {
            out .= Chr(Integer("0x" SubStr(s, i + 2, 4))), i += 6
            continue
        }
        out .= e = "n" ? "`n" : e = "t" ? "`t" : e = "r" ? "" : e, i += 2
    }
    return out
}

SetUpdIcon() {
    try {
        Roles[bUpd.Hwnd] := UpdAvail ? "btnupd1" : "btnupd0"
        PaintBtn(bUpd.Hwnd, false)
    }
    if !UpdAvail
        UpdPulseTick()                             ; hides the halo
    SetTimer(UpdPulseTick, UpdAvail ? 33 : 0)      ; new version: radar halo around the green icon
}

; one frame of the "radar" pulse: a soft green halo grows out of the icon's edge, a little past it, and fades.
; Drawn in a small transparent click-through window lying over the icon (so it can reach past the button).
UpdPulseTick() {
    static ov := 0, dc := 0, dib := 0, gr := 0, sz := 0, m := 0
    show := UpdAvail && DllCall("IsWindowVisible", "Ptr", Main.Hwnd) && !DllCall("IsIconic", "Ptr", Main.Hwnd)
        && IconUncovered(ov ? ov.Hwnd : 0)                               ; also when the window is not active
    if !show {
        if (ov && DllCall("IsWindowVisible", "Ptr", ov.Hwnd))
            ov.Hide()
        return
    }
    try {
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", bUpd.Hwnd, "Ptr", rc)
        bx := NumGet(rc, 0, "Int"), by := NumGet(rc, 4, "Int")
        bw := NumGet(rc, 8, "Int") - bx, bh := NumGet(rc, 12, "Int") - by
        if !ov {
            GdipOn()
            m := Round(9 * A_ScreenDPI / 96)                            ; how far the halo reaches past the button
            sz := Max(bw, bh) + 2 * m
            ov := Gui("-Caption +ToolWindow +Owner" Main.Hwnd " +E0x08080020")   ; NOACTIVATE LAYERED TRANSPARENT
            bi := Buffer(40, 0)
            NumPut("UInt", 40, "Int", sz, "Int", -sz, "UShort", 1, "UShort", 32, bi)   ; 32-bit, top-down
            dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
            dib := DllCall("CreateDIBSection", "Ptr", dc, "Ptr", bi, "UInt", 0, "Ptr*", 0, "Ptr", 0, "UInt", 0, "Ptr")
            DllCall("SelectObject", "Ptr", dc, "Ptr", dib)
            DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &gr)
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)
            DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)
        }
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", gr, "UInt", 0)
        d := Min(bh, Round(12 * A_ScreenDPI / 96))                       ; same corners as the button
        loop 2 {                                                          ; two waves, half a beat apart
            t := Mod(A_TickCount / 1600 + (A_Index - 1) / 2, 1)
            e := 1 + (m - 1) * (1 - (1 - t) ** 2)                         ; grows fast, slows down at the end
            a := Round(150 * (1 - t) ** 1.5)
            if (a < 3)
                continue
            DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)          ; alternate fill: ring between the two shapes
            RoundPath(pa, m - e, m - e, bw + 2 * e, bh + 2 * e, d + 2 * e)
            RoundPath(pa, m, m, bw, bh, d)
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", (a << 24) | 0x2FD26D, "Ptr*", &fb := 0)
            DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
            DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
        }
        pt := Buffer(8), size := Buffer(8), src := Buffer(8, 0), bl := Buffer(4)
        NumPut("Int", bx - m, "Int", by - m, pt)
        NumPut("Int", sz, "Int", sz, size)
        NumPut("UChar", 0, "UChar", 0, "UChar", 255, "UChar", 1, bl)     ; AC_SRC_OVER, alpha 255, AC_SRC_ALPHA
        if !DllCall("IsWindowVisible", "Ptr", ov.Hwnd)
            ov.Show("NA x" (bx - m) " y" (by - m) " w" sz " h" sz)
        DllCall("UpdateLayeredWindow", "Ptr", ov.Hwnd, "Ptr", 0, "Ptr", pt, "Ptr", size, "Ptr", dc, "Ptr", src, "UInt", 0, "Ptr", bl, "UInt", 2)
    }
}

; is the area around the update icon really showing the app (not covered by another window or one of the
; app's own dialogs)? The halo window is click-through, so WindowFromPoint looks through it.
IconUncovered(self := 0) {
    static m := Round(9 * A_ScreenDPI / 96)
    rc := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", bUpd.Hwnd, "Ptr", rc)
        return false
    l := NumGet(rc, 0, "Int") - m, t := NumGet(rc, 4, "Int") - m, r := NumGet(rc, 8, "Int") + m - 1, b := NumGet(rc, 12, "Int") + m - 1
    for p in [[(l + r) // 2, (t + b) // 2], [l, t], [r, t], [l, b], [r, b]] {
        h := DllCall("WindowFromPoint", "Int64", (p[2] << 32) | (p[1] & 0xFFFFFFFF), "Ptr")
        root := h ? DllCall("GetAncestor", "Ptr", h, "UInt", 2, "Ptr") : 0
        if (root != Main.Hwnd && !(self && root = self))                ; (the halo window itself does not count)
            return false
    }
    return true
}

RoundPath(pa, x, y, w, h, d) {
    DllCall("gdiplus\GdipStartPathFigure", "Ptr", pa)
    x2 := x + w - d, y2 := y + h - d
    for a in [[x, y, 180], [x2, y, 270], [x2, y2, 0], [x, y2, 90]]
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pa, "Float", a[1], "Float", a[2], "Float", d, "Float", d, "Float", a[3], "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", pa)
}

; click on the banner icon / tray item: check, and when there is a new version ask whether to install it
OnUpdIcon(*) {
    static busy := false
    if (busy || Rec.ih)
        return
    busy := true
    try {
        had := UpdAvail
        r := QueryUpdate()                            ; always fresh: a newer build may have been published since the last check
        if (r = "error" && had)
            r := "new"                                ; offline right now: offer what was found before (checksum still verified)
        if (r != "new") {
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
        if (ThemedAsk(_T("ComboCrown update"), _T("Version {1} is available (you have v{2}).", UpdInfo["ver"], AppVersion), msg
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
    try Download(UpdServer "/file?branch=" UpdBranch "&t=" A_TickCount, tmp)           ; the Macro Hub server (no GitHub limit) ...
    if (!FileExist(tmp) || Sha256(tmp) != sha) {
        try FileDelete tmp
        if !GhDownload("Macro%20Manager.ahk", tmp)                   ; ... else GitHub directly
            try Download(url "?t=" A_TickCount, tmp)
    }
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
        ThemedNote(_T("The downloaded file is not a valid ComboCrown script. Nothing was changed."), _T("Updates"), true)
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
    t["Release notes"] := _T("Version {1}", AppVersion) "`n`n" NotesFor(Lang)
    order.Push("Getting started")
    t["Getting started"] := _TL("hlp_start", "ComboCrown runs hotkey macros for you. Each macro has a trigger key; while you hold it (inside the chosen application) the macro plays.`n`n- Tick a macro in the list to turn it on, untick to turn it off.`n- The switch All macros in the banner turns every macro on or off at once.`n- Dark mode switches the look of the app.`n- The language button in the banner switches the app language (English, Čeština, Polski, Deutsch). The app restarts to apply it.`n- Double-click a row (or press Edit) to change a macro. Add creates a new one, Copy duplicates it, Delete removes it.`n- To select several macros drag the mouse over the rows (or Ctrl / Shift + click). Copy, Delete, Export, Move up / down and dragging out of the window work on all selected rows.`n- Closing the window keeps the app running in the tray. Right-click the tray icon for Open window / Uninstall / Exit.`n- The app always runs as administrator, so macros also work in games that run elevated.`n- The search box above the list shows only the macros whose name, key or application contains the text. The cross next to it clears it.")
    order.Push("Add / edit a macro")
    t["Add / edit a macro"] := _TL("hlp_edit", "Name - any text, shown in the list.`nProfiles - which profiles the macro belongs to (can be several).`nTrigger key - click the box, then press the key or a mouse button (right, middle, side buttons X1 / X2, mouse wheel). Hold Ctrl / Shift / Alt while pressing to make a combination, for example Ctrl+XButton1. Esc cancels.`nToggle - optional key that turns this macro on/off without opening the window. Backspace clears it.`nOnly in app (exe) - the macro works only while that program is in front. Press Select to pick a running application or browse for the .exe. Empty = works everywhere.`nType - Move + actions, Sequence or Script (.ahk). See the next topics.`nPress - how the trigger key has to be pressed. Normal: the macro starts as soon as the key goes down. Short tap: a quick press and release - the macro plays once after the release. Double tap: press the key twice quickly. Long press: hold the key for a moment (with Repeat it keeps playing while you hold it). One key can carry up to three macros this way: short tap, double tap and long press. A Normal macro on the same key takes the whole key. Mouse wheel macros always start at once.`nRun - Once per key press: plays one pass and waits until you release the key. Repeat while key is held: plays again and again until you release the key (it stops immediately). Not offered for Short tap - it always plays once.`nExact delays (bottom left) - the delays are kept to about a millisecond. On for new macros. Off = the older timing, where short delays often last 10-15 ms longer than written.`n`nSave stores the macro, Cancel throws changes away.")
    order.Push("Move + actions")
    t["Move + actions"] := _TL("hlp_move", "Made for games where you keep moving (for example A and D) and cast spells in between.`n`nDirections - the movement keys, in order, for example: a,d`nActions in order - the keys to press, one per cycle, for example: 1,2,1,F7,1,F8`n`nEvery cycle does this, with the delays you set:`n  1. direction down`n  2. (delay 1) action down`n  3. (delay 2) direction up`n  4. (delay 3) action up`n  5. (delay 4) pause, then the next direction + next action`n`nThe lists repeat from the start when they end. If Directions is empty, only the actions are pressed: hold time = delay 2, pause = delay 4.`nIf a game ignores the macro, raise the delays (20-30 ms is common).")
    order.Push("Sequence")
    t["Sequence"] := _TL("hlp_seq", "A free list of steps. Write one step per line:`n`n  down KEY PAUSE   - press and hold the key`n  up KEY PAUSE     - release the key`n  tap KEY PAUSE    - press and release at once`n`nPAUSE is the wait after the step in milliseconds (empty = 0).`n`nExample - quick A / D change:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nExample - attack and spells:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nExample - two keys together:`n  tap Shift+4 50`n`nWith Run = Repeat the lines play in a loop while the trigger key is held; with Once they play one time.`nKeys that are still held when you release the trigger are released automatically.")
    order.Push("Script (.ahk)")
    t["Script (.ahk)"] := _TL("hlp_script", "For anything the other types can not do. Paste or write your own AutoHotkey v2 script.`n`n- The script runs as its own process while the macro is ticked, and is stopped when you untick it.`n- It must be AutoHotkey v2 code (v1 scripts will not work).`n- Trigger key and application filter are not used, your script does that itself.`n- Imported .ahk files that were not made by ComboCrown become Script macros.`n- An imported script asks before it runs for the first time: it runs with administrator rights, so only turn it on if you trust where it came from. The window shows what the script does (for example starts programs or deletes files) and offers to show the code.")
    order.Push("Keys and recording")
    t["Keys and recording"] := _TL("hlp_keys", "Key names are the AutoHotkey names: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nA key can also be written as a scan code, for example sc002 - this is the physical key, regardless of layout. Keys like comma, plus, & and | are saved this way automatically.`n`nMouse: the trigger, toggle and All macros keys can also be a mouse button: RButton, MButton (wheel click), XButton1 / XButton2 (the two side buttons), or the wheel itself (WheelUp / WheelDown / WheelLeft / WheelRight). A wheel has no hold, so wheel macros always play once. The left button is not offered.`nGaming / MMO mice: windows only knows five mouse buttons, the extra side buttons are handled by the mouse software (G HUB, Synapse, iCUE, ...). Set them there to keys, best F13 - F24 (or Ctrl+Alt+number); ComboCrown then sees them as ordinary keys, so click the trigger box and press the side button.`n`nRecord (next to Directions and Actions): press Record, press the keys in the order you want, then press Done. The field fills in live. Macros are paused while recording.`n`nKeys at the same time: keys that you hold together are saved as one step joined with +, for example Shift+4. When the macro plays, all of them go down together and are released together (not Shift first and 4 afterwards).`nThe same works by typing it in the fields: a,Shift+4,d")
    order.Push("Profiles")
    t["Profiles"] := _TL("hlp_profiles", "Profiles keep different sets of macros apart (for example one per game).`n`n- The profile button in the banner shows the current profile. Click it to switch, or to create / rename / delete a profile.`n- The list shows only the macros of the current profile, and only those are active.`n- In the editor, Profiles lets you choose one or more profiles for the macro. When you change a macro that belongs to several profiles, the app asks: apply the change to all of them, or only to the current profile (the other profiles keep the old version).`n- Tick state of a macro stays the same in every profile; switching profile just changes which macros are in play.`n- Deleting a profile moves macros that belonged only to it to the first remaining profile.")
    order.Push("Toggle keys")
    t["Toggle keys"] := _TL("hlp_toggle", "Toggle (in the editor) - a key that switches that single macro on / off, same as ticking it in the list. A small tooltip shows ON / OFF.`nAll macros toggle key (button under the list) - switches the master switch. Works in every profile.`n`nClick the button, press the key. Esc cancels, Backspace removes the key.`nMacros of other profiles do not react to their toggle keys.")
    order.Push("Order, export, backup")
    t["Order, export, backup"] := _TL("hlp_order", "Move up / Move down change the order in the list. Clicking a column header sorts the list (click again to reverse).`n`nExport... saves the selected macro as a standalone AutoHotkey v2 .ahk file that also runs by itself (it asks for admin rights).`nImport... loads one or more .ahk files (or just drag them onto the main window). You can also drag a macro from the list onto the desktop / a folder / a chat window to export it as an .ahk file. The macro is named after the file; files made by ComboCrown come back as editable macros, other scripts become Script macros. Imports go to the current profile and start switched off.`nExport all... writes every macro to a folder, one file each.`n`nBackup... (next to Uninstall) saves everything - macros, profiles, settings and script files - into one .mmbackup file, and restores it on a new PC or after a reinstall. You can also drop the backup file onto the window. Before restoring, the current state is saved as config\backup-before-restore.mmbackup.`n`nUninstall deletes the whole app folder including all macros and settings. It offers to export all macros first.")
    order.Push("Updates")
    t["Updates"] := _TL("hlp_updates", "The arrow icon in the banner (next to the profile button) shows whether a new version exists: grey = you are up to date, green = a new version is available. Hover it for details.`n`nThe app checks a few seconds after it starts (can be turned off in the tray menu: Check for updates at start). Click the icon at any time to check again. Nothing is installed until you click the green icon and confirm.`n`nWhen you update, the app downloads the new file, checks its checksum, keeps the old one as Macro Manager.ahk.bak and restarts. Your macros, profiles and settings are stored separately in the config folder and stay exactly as they are.`n`nIf something goes wrong, close the app, delete Macro Manager.ahk and rename Macro Manager.ahk.bak back to Macro Manager.ahk.`n`nThe update needs internet access (Macro Hub server or github.com).")
    order.Push("Macro Hub")
    t["Macro Hub"] := _TL("hlp_hub", "Macro Hub (the button next to the search box) shows macros shared by players. It opens as a panel on the side of the main window.`n`n- Players' macros: macros of other players. My macros: the macros you shared, with their ratings and downloads.`n- Search with words from the name, the game or the author: every word must match. 4story finds all 4Story macros, 4story war only the warrior ones.`n- The game button filters one game, the sort button sorts by Top rated, Newest or Most downloaded.`n- Every macro shows its average rating in stars (1 = worst, 5 = best) with the number of ratings in brackets, its author, its game, its trigger key and how many times it was downloaded. A gold tick marks macros checked by the moderator - they come first.`n- The box under the list shows the description and what the macro does (keys, delays, sequence) - before you download it.`n- Download (or a double-click) adds the macro to the current profile, switched off. Check its key and application, then tick it.`n- Rate gives 1 to 5 stars - one rating per installation, you can change it later. Your own macros can't be rated.`n- Report sends a macro to be checked, for example a farm / AFK macro, which is not allowed. After several reports it is hidden.`n- Delete (My macros) removes a macro you shared from Macro Hub; your own copy in the list stays.`n`nSharing: click the share icon at the end of a row in the main list, then fill in the name, the game, a description and your nickname. The icon turns gold once the macro is shared. Macros downloaded from Macro Hub show a download arrow instead and can be shared only after you change them.`n`nUpdates: when you change a macro you shared, the app asks whether to update it in Macro Hub - its ratings and downloads stay (until then its icon has a dot; click it to update). When the author updates a macro you downloaded, a notice appears and its arrow in the list turns green: click it to see what changed and take the new version or keep yours. Shared: keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Script macros can't be shared.`n`nMacro Hub needs internet access. Nobody can see who rated or reported a macro. To recognise macros you downloaded with an older version, the app sends Macro Hub once what they do (keys, delays, sequence - not their names); nothing of it is stored.")
    order.Push("Tips and problems")
    t["Tips and problems"] := _TL("hlp_tips", "- The game does nothing: try raising the delays, make sure Only in app matches the game (use Select), and keep the app as administrator.`n- Character runs in one direction: keep direction pairs in Directions (a,d) and the delay between cycles small but not 0.`n- A macro does not start: check that it is ticked, All macros is on, it is in the current profile and the trigger key is set (not undefined).`n- Two macros with the same trigger key: only one of them works - use different keys, different profiles or different Press modes (short tap / double tap / long press).`n- Macros made before Exact delays existed keep their old timing. If you switch Exact delays on for one of them, it may play faster - then raise its delays a little.`n- Stuck key after an abort: press and release it once; the app releases keys it pressed when the macro stops.`n- Settings and scripts live in the config folder next to the app.")
    return [order, t]
}

OpenDiscord(*) {
    static last := 0
    if (A_TickCount - last < 800)                 ; click event + mouse polling may both fire
        return
    last := A_TickCount
    try {
        Run("discord://-/invite/" DiscordInvite)                ; the Discord app opens the invite to the server
        return
    }
    try {
        Run("https://discord.gg/" DiscordInvite)
        return
    }
    A_Clipboard := "https://discord.gg/" DiscordInvite
    ThemedNote(_T("Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}", "https://discord.gg/" DiscordInvite))
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
    dc := 0
    try {
        g.AddPicture("x10 y8 w640 h72", LogoFile)
        g.SetFont("s16 bold cD0AE6B", "Segoe UI")
        ttl := g.AddText("x100 y29 w300 BackgroundTrans", _T("Help"))
        Roles[ttl.Hwnd] := "skip"
        g.SetFont("s10 norm", "Segoe UI Semibold")
        dc := AddBtn(g, "x416 y27 w218 h36", _T("Join Discord"), OpenDiscord, "btndiscord")    ; support: like the button on the website
        OnMessage(0x20, HelpCur)                   ; WM_SETCURSOR: hand cursor over the button (else Windows resets it)
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
        HelpBadge := AddBadge(g, "x172 y101 w16 h16")
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
            SetHelpBadge(false)
        }
    }
    HelpCur(wp, *) {
        if (dc && wp = dc.Hwnd) {
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr"))     ; IDC_HAND
            return 1
        }
    }
    HelpClose(*) {
        global HelpGui
        OnMessage(0x20, HelpCur, 0)
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
    if (hit[1] >= 1 && hit[3] = 4 && hit[1] <= View.Length) {          ; the share icon at the end of the row
        if (msg = 0x201 && View[hit[1]]["type"] != "script")
            SetTimer(LibShareMacro.Bind(View[hit[1]]), -10)
        return 0
    }
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

; [row (1-based, 0 = none), hit flags, column (0-based)] for a point in list client coordinates
LvHit(x, y) {
    hti := Buffer(24, 0)
    NumPut("Int", x, "Int", y, hti)
    SendMessage(0x1039, 0, hti, LV)                    ; LVM_SUBITEMHITTEST (finds the row over any column)
    return [NumGet(hti, 12, "Int") + 1, NumGet(hti, 8, "UInt"), NumGet(hti, 16, "Int")]
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
        base := SafeFileName(m["name"]), nm := base, k := 1
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
            AddBadge(g, "x16 y" (heading = "" ? 16 : 17) " w16 h16")   ; the yellow !
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
ThemedNote(text, title := "ComboCrown", warn := false, heading := "") {
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
    path := FileSelect("S16", A_Desktop "\ComboCrown backup " FormatTime(, "yyyy-MM-dd") ".mmbackup", _T("Create backup"), _T("ComboCrown backup (*.mmbackup)"))
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
    t := "; ComboCrown backup - restore it with the Backup... button in the app (or drop this file onto its window)`n"
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
        throw Error("not a ComboCrown backup")
    return res
}

RestoreBackup(path := "") {
    if (path = "") {
        path := FileSelect(1, A_Desktop, _T("Restore from backup"), _T("ComboCrown backup (*.mmbackup)"))
        if (path = "")
            return
    }
    try b := ReadBackup(path)
    catch {
        ThemedNote(_T("This is not a ComboCrown backup file:`n{1}", path), , true)
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

; ============ macro library: macros shared by other users - browse, rate, report, download, share ============
; The library is a small web service (server/ in the repository, Cloudflare). This install is known there only by
; a random id (LibId, its hash is stored): it lets you rate a macro once and delete the macros you shared.
; The panel sticks to the right side of the main window (to the left side when the screen has no room there).

LibInstall() {
    global LibId
    if !RegExMatch(LibId, "^[0-9a-f]{32}$") {
        buf := Buffer(16)
        DllCall("advapi32\SystemFunction036", "Ptr", buf, "UInt", 16)       ; RtlGenRandom
        LibId := ""
        loop 16
            LibId .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
        Save()
    }
    return LibId
}

; one request to the library: returns the answer (Map), with "error" when something went wrong
LibCall(method, path, body := "", url := "") {
    hdr := Map("X-MM-Install", LibInstall(), "Accept", "application/json")
    if IsObject(body)
        hdr["Content-Type"] := "application/json"
    r := HttpSend(url != "" ? url : LibApi path, hdr, 10000, false, method, IsObject(body) ? JsonStr(body) : "")
    if !r
        return Map("error", "network")
    j := 0
    try j := JsonParse(r["text"])
    if !(j is Map)
        j := Map("error", "status " r["status"])
    else if (r["status"] != 200 && !j.Has("error"))
        j["error"] := "status " r["status"]
    return j
}

LibErr(code) {
    switch code {
        case "network": return _T("Can't reach Macro Hub. Check your internet connection and try again.")
        case "too_many": return _T("You have shared a lot of macros today. Please try again tomorrow.")
        case "own_macro": return _T("You can't rate your own macro.")
        case "not_found": return _T("This macro is no longer in Macro Hub.")
        case "not_owner": return _T("Only the author can delete this macro.")
        case "bad_text": return _T("Please check the name, game, description and nickname.")
    }
    return _T("Macro Hub could not do this ({1}).", code)
}

; game tags used in the library, the most used first (for the game filter and the share form)
LibGamesLoad(j := 0) {
    global LibGames
    if !j
        j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "games"))
    if (!j.Has("error") && j.Has("games")) {
        LibGames := []
        for g in j["games"]
            LibGames.Push(g)
    }
    return LibGames
}

; ---- the panel ----
ToggleLibrary(*) {
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        return CloseLibrary()
    OpenLibrary()
}

OpenLibrary() {
    global LibOpen
    if !LibGui
        BuildLibrary()
    LibOpen := true
    LibGui.Show("NA")                       ; (the first Show centres the window on the screen - placed right after)
    LibPlace()
    SetTimer(() => LibCheckUpdates(), -1000)
    if !LibItems.Length {
        LibLoad()
        if (LibWho != "mine") {             ; once: which macros of the list are shared (share icons)
            j := LibCall("GET", "?who=mine&sort=new")
            if !j.Has("error")
                LibSyncShared(j["items"], !j["more"])
        }
    }
}

; marks the macros of the list that are in the library (gold share icon) by comparing what is shared;
; complete = these are all my shared macros: a macro whose library entry is gone loses the mark
LibSyncShared(items, complete) {
    ids := Map(), byData := Map()
    for it in items {
        ids[String(it["id"])] := it
        if it.Has("data")
            byData[JsonStr(it["data"])] := it["id"]
    }
    changed := false
    for m in Macros {
        if (m["type"] = "script")
            continue
        if (m["libshare"] = "") {
            k := JsonStr(LibData(m))
            if byData.Has(k)
                m["libshare"] := byData[k], m["libsharehash"] := LibHash(m), changed := true
        } else if (complete && !ids.Has(String(m["libshare"])))
            m["libshare"] := "", m["libsharehash"] := "", changed := true
        else if (m["libsharehash"] = "" && ids.Has(String(m["libshare"])) && ids[String(m["libshare"])].Has("data"))
            m["libsharehash"] := LibHashData(ids[String(m["libshare"])]["data"]), changed := true    ; shared before 1.22.7
    }
    if changed {
        Save()
        RedrawList()
    }
}

CloseLibrary(*) {
    global LibOpen
    LibOpen := false
    try LibGui.Hide()
}

; the panel follows the main window (WM_MOVE of the main window)
LibFollow(wp, lp, msg, hwnd) {
    if (LibGui && hwnd = Main.Hwnd && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        LibPlace()
}

; visible frame of the main window (without the invisible resize border of Windows 10 / 11)
MainFrame(&L, &T, &R, &B) {
    rc := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", Main.Hwnd, "UInt", 9, "Ptr", rc, "UInt", 16) {     ; DWMWA_EXTENDED_FRAME_BOUNDS
        WinGetPos(&x, &y, &w, &h, Main.Hwnd)
        NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rc)
    }
    L := NumGet(rc, 0, "Int"), T := NumGet(rc, 4, "Int"), R := NumGet(rc, 8, "Int"), B := NumGet(rc, 12, "Int")
}

LibPlace() {
    MainFrame(&L, &T, &R, &B)
    w := Round(LibW * A_ScreenDPI / 96) + 2
    ml := 0, mr := A_ScreenWidth
    loop MonitorGetCount() {                     ; (names differ from L T R B - AutoHotkey ignores the case of names)
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        if ((L + R) // 2 >= wl && (L + R) // 2 < wr && (T + B) // 2 >= wt && (T + B) // 2 < wb)
            ml := wl, mr := wr
    }
    x := (R + w <= mr || L - w < ml) ? R : L - w
    DllCall("SetWindowPos", "Ptr", LibGui.Hwnd, "Ptr", 0, "Int", x, "Int", T, "Int", w, "Int", B - T, "UInt", 0x14)   ; NOZORDER | NOACTIVATE
    LibFit(B - T)
}

; the main window has another height (for example after the language changed): the list of the panel too, the parts below it move
LibFit(h) {
    global LibH
    d := h - LibH
    LibH := h
    if !d
        return
    ControlGetPos(, &ly, , &lh, LibLV)
    for hwnd, c in LibGui {
        ControlGetPos(&cx, &cy, , , c)
        if (cy > ly + 4 && cy > -500 && !LibOff.Has(hwnd))  ; (hidden font controls and the "no connection" parts stay)
            ControlMove(, cy + d, , , c)
    }
    ControlMove(, , , lh + d, LibLV)
    DllCall("RedrawWindow", "Ptr", LibGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)     ; no copies of moved buttons left behind
    if LibIsOff
        LibOffline(true)                                    ; centred again in the new list area
}

; ---- no internet: instead of the list, a "No connection" sign in the middle; tried again every 15 seconds ----
LibOffline(on) {
    global LibIsOff
    if !LibGui
        return
    LibIsOff := on
    LibLV.Visible := !on
    if on {
        ControlGetPos(&lx, &ly, &lw, &lh, LibLV)
        s := A_ScreenDPI / 96
        top := ly + Max(0, (lh - Round(190 * s)) // 2)
        for hwnd, c in LibOff {
            k := c.Name
            ControlGetPos(, , &cw, &ch, c)
            y := top + Round((k = "pic" ? 0 : k = "ttl" ? 86 : k = "sub" ? 120 : 158) * s)
            ControlMove(lx + (lw - cw) // 2, y, , , c)
        }
        SetTimer(LibRetry, 15000)
    } else
        SetTimer(LibRetry, 0)
    for hwnd, c in LibOff
        c.Visible := on
    if on
        LibInfo.Text := ""
}

LibRetry(*) {
    if (!LibGui || !DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd))
        return SetTimer(LibRetry, 0)
    LibLoad()
}

; an action failed: no internet = the panel shows it too
LibFail(j) {
    if (j["error"] = "network")
        LibOffline(true)
    ThemedNote(LibErr(j["error"]), , true)
}

; the "!" in a circle (gold, transparent) for the "No connection" sign - drawn once into the assets folder
LibOfflinePng() {
    f := AssetsDir "\offline.png"
    if (FileExist(f) || !GdipOn())
        return f
    sz := 96
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", sz, "Int", sz, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &gr := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)
    DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFD0AE6B, "Float", 7, "Int", 2, "Ptr*", &pen := 0)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", gr, "Ptr", pen, "Float", 5, "Float", 5, "Float", sz - 10, "Float", sz - 10)
    FillRound(gr, sz / 2 - 5, 22, 10, 36, 10, "D0AE6B")         ; the bar of the "!"
    FillRound(gr, sz / 2 - 6, 64, 12, 12, 12, "D0AE6B")         ; its dot
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)    ; PNG encoder
    DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "WStr", f, "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    return f
}

; Macro Hub can be reached (also loads the games for the share form)
LibOnline() {
    j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "games"))
    if (j.Has("error") && j["error"] = "network")
        return false
    LibGamesLoad(j)
    return true
}

BuildLibrary() {
    global LibGui, LibLV, LibSearch, LibDesc, LibInfo, LibBtn, LibH
    MainFrame(&L, &T, &R, &B)
    LibH := B - T                                           ; the height the layout is made for (LibFit)
    W := LibW, H := Round((B - T - 2) * 96 / A_ScreenDPI)
    g := Gui("-Caption +Border +Owner" Main.Hwnd, _T("Macro Hub"))
    LibGui := g
    ; title strip: drawn like a button (DrawBtn) but without click events, so clicks reach the close button on it
    g.SetFont("s14 bold", "Segoe UI")
    hd := g.AddText("x8 y8 w" (W - 16) " h48 +0xD", "   " _T("Macro Hub"))
    Roles[hd.Hwnd] := "libhead"
    BtnLook[hd.Hwnd] := {left: true, round: true, hover: false, badge: false, pad: [0, 0, 0, 0]}
    g.SetFont("s15 norm", "Segoe UI")
    AddBtn(g, "x" (W - 48) " y16 w32 h32", Chr(0xD7), CloseLibrary, "btnbanner")
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn := Map()
    tw := (W - 24) // 2                                         ; tabs: macros of other players / my shared macros
    LibBtn["others"] := AddBtn(g, "x8 y64 w" tw " h30", _T("Players' macros"), (*) => LibSetWho("others"))
    LibBtn["mine"] := AddBtn(g, "x" (16 + tw) " y64 w" tw " h30", _T("My macros"), (*) => LibSetWho("mine"))
    LibSearch := g.AddEdit("x8 y102 w" (W - 62) " h26")
    SendMessage(0x1501, 1, StrPtr(_T("Search: name, game or author")), LibSearch)
    LibSearch.OnEvent("Change", (*) => SetTimer(LibLoad, -600))
    g.SetFont("s10 norm", "Segoe MDL2 Assets")
    AddBtn(g, "x" (W - 46) " y102 w38 h26", Chr(0xE72C), (*) => LibLoad())         ; refresh
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn["game"] := AddBtn(g, "x8 y134 w" (W - 180) " h26", LibGameText(), LibGameMenu)
    LibBtn["sort"] := AddBtn(g, "x" (W - 164) " y134 w156 h26", LibSortText(), LibSortMenu)
    yBtn := H - 40, yInfo := yBtn - 26, yDesc := yInfo - 128
    LibLV := g.AddListView("x8 y168 w" (W - 16) " h" (yDesc - 176) " -Hdr -E0x200 -Multi", [""])
    LibLV.SetFont("s10")
    LibLV.Opt("+LV0x10020")                                     ; double buffer, full-row select
    LibLV.ModifyCol(1, (W - 16) * A_ScreenDPI / 96 - 24)
    il := DllCall("comctl32\ImageList_Create", "Int", 1, "Int", Round(52 * A_ScreenDPI / 96), "UInt", 0x20, "Int", 1, "Int", 0, "Ptr")
    SendMessage(0x1003, 1, il, LibLV.Hwnd)                       ; LVM_SETIMAGELIST, LVSIL_SMALL: sets the row height
    LibLV.OnNotify(-12, LibDraw)
    LibLV.OnEvent("ItemSelect", (*) => LibShowSel())
    LibLV.OnEvent("DoubleClick", (*) => LibDownload())
    SendMessage(0x127, 0x10001, 0, LibLV.Hwnd)
    ; "No connection" sign, shown instead of the list (LibOffline places it in the middle)
    p := g.AddPicture("vpic x0 y0 w64 h64 Hidden BackgroundTrans", LibOfflinePng())
    g.SetFont("s14 bold", "Segoe UI")
    t1 := g.AddText("vttl x0 y0 w" (W - 40) " Center Hidden", _T("No connection"))
    g.SetFont("s9 norm", "Segoe UI")
    t2 := AddHint(g, "vsub x0 y0 w" (W - 40) " h34 Center Hidden", _T("Macro Hub needs the internet. It tries again by itself every few seconds."))
    b := AddBtn(g, "vbtn x0 y0 w130 h30 Hidden", _T("Try again"), (*) => LibLoad(), "btnprimary")
    for c in [p, t1, t2, b]
        LibOff[c.Hwnd] := c
    LibDesc := g.AddEdit("x8 y" yDesc " w" (W - 16) " h122 Multi ReadOnly", "")     ; description + what the macro does
    LibInfo := AddHint(g, "x8 y" yInfo " w" (W - 126) " h20", "")
    LibBtn["more"] := AddBtn(g, "x" (W - 112) " y" (yInfo - 3) " w104 h24", _T("Load more"), (*) => LibLoad(true), "btnghost")
    LibBtn["dl"] := AddBtn(g, "x8 y" yBtn " w130 h32", _T("Download"), (*) => LibDownload(), "btnprimary")
    LibBtn["rate"] := AddBtn(g, "x+8 yp w110 h32", _T("Rate") "  ▾", LibRateMenu)
    LibBtn["report"] := AddBtn(g, "x+8 yp w90 h32", _T("Report"), (*) => LibReport())
    LibBtn["del"] := AddBtn(g, "x+8 yp w" (W - 370) " h32", _T("Delete"), (*) => LibDelete(), "btndanger")
    ; hidden: fonts for the rows (asked for at every paint - re-theming makes new ones)
    g.SetFont("s10 bold", "Segoe UI")
    LibBtn["fontB"] := g.AddText("x-900 y-900 w10 h10", "")
    g.SetFont("s9 norm", "Segoe UI")
    LibBtn["fontS"] := g.AddText("x-900 y-900 w10 h10", "")
    g.OnEvent("Escape", CloseLibrary)
    g.OnEvent("Close", CloseLibrary)
    ApplyTheme(g)
    LibTabs()
    LibShowSel()
}

; ---- tabs, game filter, sort ----
LibTabs() {
    for k in ["others", "mine"] {
        Roles[LibBtn[k].Hwnd] := (k = LibWho) ? "btnprimary" : "btn"
        PaintBtn(LibBtn[k].Hwnd, false)
    }
}

LibSetWho(who) {
    global LibWho
    if (who = LibWho)
        return
    LibWho := who
    LibTabs()
    LibLoad()
}

LibGameText() => (LibGameF = "" ? _T("All games") : _T("Game: {1}", LibGameF)) "  ▾"

LibGameMenu(ctrl, *) {
    m := Menu()
    m.Add(_T("All games"), LibSetGame.Bind(""))
    if (LibGameF = "")
        m.Check(_T("All games"))
    games := LibGamesLoad()
    if games.Length
        m.Add()
    for g in games {
        label := g["game"] "   (" g["count"] ")"
        m.Add(label, LibSetGame.Bind(g["game"]))
        if (g["game"] = LibGameF)
            m.Check(label)
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibSetGame(game, *) {
    global LibGameF
    LibGameF := game
    LibBtn["game"].Text := LibGameText()
    PaintBtn(LibBtn["game"].Hwnd, false)
    LibLoad()
}

LibSortText() => (LibSort = "new" ? _T("Newest") : LibSort = "dl" ? _T("Most downloaded") : _T("Top rated")) "  ▾"

LibSortMenu(ctrl, *) {
    m := Menu()
    for o in [["top", _T("Top rated")], ["new", _T("Newest")], ["dl", _T("Most downloaded")]] {
        m.Add(o[2], LibSetSort.Bind(o[1]))
        if (o[1] = LibSort)
            m.Check(o[2])
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibSetSort(k, *) {
    global LibSort
    LibSort := k
    LibBtn["sort"].Text := LibSortText()
    PaintBtn(LibBtn["sort"].Hwnd, false)
    LibLoad()
}

; (re)loads the list from the library; append = the next page ("Load more")
LibLoad(append := false) {
    global LibItems, LibMore, LibBusy
    if (!LibGui || LibBusy)
        return
    LibBusy := true
    if !LibIsOff                                            ; (while "No connection" shows, it just tries again quietly)
        LibInfo.Text := _T("Loading...")
    off := append ? LibItems.Length : 0
    j := LibCall("GET", "?who=" LibWho "&sort=" LibSort "&offset=" off "&game=" UriEnc(LibGameF) "&q=" UriEnc(Trim(LibSearch.Value)))
    LibBusy := false
    if j.Has("error") {
        if (j["error"] = "network")
            return LibOffline(true)
        LibInfo.Text := LibErr(j["error"])
        return
    }
    if LibIsOff
        LibOffline(false)                                   ; back online
    if !append
        LibItems := []
    for it in j["items"]
        LibItems.Push(it)
    LibMore := j["more"]
    if (LibWho = "mine" && !append && Trim(LibSearch.Value) = "" && LibGameF = "")
        LibSyncShared(LibItems, !LibMore)
    LibLV.Opt("-Redraw")
    LibLV.Delete()
    for it in LibItems
        LibLV.Add(, it["name"])
    LibLV.Opt("+Redraw")
    LibShowSel()
    if !LibItems.Length
        LibInfo.Text := LibWho = "mine" ? _T("You have not shared any macro yet - use the share icon in your list.")
            : (Trim(LibSearch.Value) = "" && LibGameF = "") ? _T("Macro Hub is empty so far - share the first macro!") : _T("No macros found.")
}

LibSel() {
    r := LibLV.GetNext(0)
    return (r && r <= LibItems.Length) ? LibItems[r] : 0
}

; description, details and buttons of the selected macro
LibShowSel() {
    it := LibSel()
    LibBtn["more"].Visible := LibMore
    mineTab := (LibWho = "mine")
    LibBtn["dl"].Enabled := !!it
    LibBtn["rate"].Visible := LibBtn["report"].Visible := !mineTab        ; own macros: download back or delete
    LibBtn["rate"].Enabled := it && !it["mine"]
    LibBtn["report"].Enabled := !!it
    LibBtn["del"].Visible := it && it["mine"]
    for k in ["dl", "rate", "report", "del"]
        PaintBtn(LibBtn[k].Hwnd, false)
    if !it {
        LibDesc.Value := ""
        LibInfo.Text := LibItems.Length ? _T("Pick a macro to see its description.") : ""
        return
    }
    ; the description, then what the macro does (asked for once per macro and version)
    d := LibDetail(it)
    LibDesc.Value := StrReplace((it["descr"] = "" ? _T("(no description)") : it["descr"])
        . (d ? "`n`n" _T("What it does:") "`n" LibDescribe(d) : ""), "`n", "`r`n")
    t := it["mine"] ? _T("your macro") : _T("by {1}", it["author"])         ; (type and key are in the preview)
    t := (it["game"] = "" ? "" : it["game"] "  ·  ") t
    if (it.Has("updated") && it["updated"])
        t .= "  ·  " _T("updated {1}", LibDate(it["updated"]))
    if (it.Has("verified") && it["verified"])
        t := Chr(0x2714) " " _T("verified") "  ·  " t
    if it["hidden"]
        t .= "  ·  " _T("hidden after reports")
    else if (!it["mine"] && it["my"])
        t .= "  ·  " _T("your rating: {1}", it["my"]) Chr(0x2605)
    LibInfo.Text := t
}

; the shared data of a hub macro (for the preview); remembered per id and version
LibDetail(it) {
    static cache := Map()
    k := it["id"] "/" (it.Has("version") ? it["version"] : 1)
    if cache.Has(k)
        return cache[k]
    if it.Has("data")                                           ; (my own macros come with it)
        return cache[k] := it["data"]
    j := LibCall("GET", "/" it["id"])
    if (j.Has("error") || !j.Has("data"))
        return 0
    return cache[k] := j["data"]
}

; what a macro does, in plain lines (the preview before a download)
LibDescribe(d) {
    pr := d["press"] = "tap" ? _T("Short tap") : d["press"] = "double" ? _T("Double tap") : d["press"] = "hold" ? _T("Long press") : _T("Normal")
    t := TypeLabel(d["type"]) "`n" _T("Trigger key") ": " (d["hotkey"] = "" ? Chr(0x2014) : d["hotkey"]) "  ·  " _T("Press") ": " pr
        . "`n" _T("Run") ": " (d["repeat"] ? _T("Repeat while key is held") : _T("Once per key press"))
    if (d["app"] != "")
        t .= "`n" _T("Only in app (exe)") ": " d["app"]
    if (d["type"] = "seq") {
        t .= "`n" _T("Sequence") ":"
        for l in StrSplit(d["seq"], "|")
            t .= "`n    " l
    } else
        t .= "`n" _T("Directions (optional)") ": " (d["dirs"] = "" ? Chr(0x2014) : d["dirs"])
            . "`n" _T("Actions in order") ": " d["actions"]
            . "`n" _T("Delays (ms)") ": " d["g1"] " / " d["g2"] " / " d["g3"] " / " d["ge"]
    return t
}

; ---- one row: name (bold), stars + (number of ratings) + author below; key and downloads on the right ----
LibDraw(ctrl, lp) {
    static ps := A_PtrSize
    stage := NumGet(lp, 24 - (ps = 8 ? 0 : 12), "UInt")
    hdc := NumGet(lp, ps = 8 ? 32 : 16, "Ptr")
    h := ctrl.Hwnd
    if (stage = 1)
        return 0x30                                             ; items + post-paint
    if (stage = 2) {                                            ; below the last row: the list colour
        cl := Buffer(16)
        DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
        n := SendMessage(0x1004, 0, 0, h)
        if n {
            ir := Buffer(16, 0)
            SendMessage(0x100E, n - 1, ir, h)
            NumPut("Int", NumGet(ir, 12, "Int"), cl, 4)
        }
        FillHex(hdc, 0, NumGet(cl, 4, "Int"), NumGet(cl, 8, "Int"), NumGet(cl, 12, "Int") - NumGet(cl, 4, "Int"), DarkOn ? "1F2127" : "FFFFFF")
        return 0
    }
    if (stage != 0x10001)
        return 0
    row := NumGet(lp, ps = 8 ? 56 : 36, "UPtr")
    if (row >= LibItems.Length)
        return 4
    it := LibItems[row + 1]
    s := A_ScreenDPI / 96
    rc := Buffer(16, 0)
    SendMessage(0x100E, row, rc, h)                             ; LVM_GETITEMRECT
    top := NumGet(rc, 4, "Int"), bot := NumGet(rc, 12, "Int")
    cl := Buffer(16)
    DllCall("GetClientRect", "Ptr", h, "Ptr", cl)
    cw := NumGet(cl, 8, "Int")
    sel := (SendMessage(0x102C, row, 2, h) & 2) != 0
    bg := sel ? (DarkOn ? "3A3626" : "F3E7C9") : (DarkOn ? "1F2127" : "FFFFFF")
    fg := DarkOn ? "ECECEF" : "1B1B1F"
    hint := DarkOn ? "A9ADB8" : "6A6A74"
    FillHex(hdc, 0, top, cw, bot - top, bg)
    FillHex(hdc, Round(8 * s), bot - 1, cw - Round(16 * s), 1, DarkOn ? "2A2D35" : "ECECF0")     ; separator
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    r := Buffer(16)
    rw := Round(96 * s)                                         ; right column
    ; name
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, LibBtn["fontB"]), "Ptr")
    nx := Round(10 * s)
    if (it.Has("verified") && it["verified"]) {                 ; verified by the moderator: a gold tick before the name
        DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr("D0AE6B"))
        NumPut("Int", nx, "Int", top + Round(5 * s), "Int", cw - rw, "Int", top + Round(27 * s), r)
        DllCall("DrawTextW", "Ptr", hdc, "WStr", Chr(0x2714), "Int", 1, "Ptr", r, "UInt", 0x824)
        tw := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "Ptr", hdc, "WStr", Chr(0x2714) "  ", "Int", 3, "Ptr", tw)
        nx += NumGet(tw, 0, "Int")
    }
    DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr(fg))
    NumPut("Int", nx, "Int", top + Round(5 * s), "Int", cw - rw - Round(8 * s), "Int", top + Round(27 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", it["name"], "Int", -1, "Ptr", r, "UInt", 0x8824)
    ; key (right, top)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, LibBtn["fontS"]), "Ptr")
    DllCall("SetTextColor", "Ptr", hdc, "UInt", Bgr(hint))
    NumPut("Int", cw - rw, "Int", top + Round(5 * s), "Int", cw - Round(10 * s), "Int", top + Round(27 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", it["hotkey"] = "" ? Chr(0x2014) : it["hotkey"], "Int", -1, "Ptr", r, "UInt", 0x8826)
    ; downloads (right, bottom)
    NumPut("Int", cw - rw, "Int", top + Round(27 * s), "Int", cw - Round(10 * s), "Int", top + Round(48 * s), r)
    DllCall("DrawTextW", "Ptr", hdc, "WStr", Chr(0x2193) " " it["downloads"], "Int", -1, "Ptr", r, "UInt", 0x8826)
    ; stars: the average rounded to quarters of a star
    sz := 14 * s, x := 10 * s, cy := top + 37.5 * s
    q := Round(it["rating"] * 4) / 4
    if GdipOn() {
        gr := GrOn(hdc)
        loop 5 {
            cx := x + sz / 2 + (A_Index - 1) * (sz + 2 * s)
            LibStar(gr, cx, cy, sz / 2, DarkOn ? "3A3E49" : "D3D3DB")
            f := Min(1, Max(0, q - (A_Index - 1)))
            if (f > 0) {
                DllCall("gdiplus\GdipSetClipRect", "Ptr", gr, "Float", cx - sz / 2, "Float", cy - sz / 2, "Float", sz * f, "Float", sz, "Int", 0)
                LibStar(gr, cx, cy, sz / 2, "D0AE6B")
                DllCall("gdiplus\GdipResetClip", "Ptr", gr)
            }
        }
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    }
    ; (number of ratings) and the author
    tx := Round(x + 5 * (sz + 2 * s) + 4 * s)
    NumPut("Int", tx, "Int", top + Round(27 * s), "Int", cw - rw - Round(8 * s), "Int", top + Round(48 * s), r)
    who := it["mine"] ? (it["hidden"] ? _T("hidden after reports") : _T("your macro")) : _T("by {1}", it["author"])
    DllCall("DrawTextW", "Ptr", hdc, "WStr", "(" it["count"] ")   " who (it["game"] = "" ? "" : "  ·  " it["game"]), "Int", -1, "Ptr", r, "UInt", 0x8824)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    return 4                                                    ; CDRF_SKIPDEFAULT
}

; five-pointed star around (cx, cy)
LibStar(gr, cx, cy, ro, hex) {
    pts := Buffer(80)
    loop 10 {
        a := (-90 + (A_Index - 1) * 36) * 0.017453292519943
        rr := Mod(A_Index, 2) ? ro : ro * 0.45
        NumPut("Float", cx + rr * Cos(a), "Float", cy + rr * Sin(a), pts, (A_Index - 1) * 8)
    }
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pa := 0)
    DllCall("gdiplus\GdipAddPathPolygon", "Ptr", pa, "Ptr", pts, "Int", 10)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" hex), "Ptr*", &fb := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", fb, "Ptr", pa)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", fb)
    DllCall("gdiplus\GdipDeletePath", "Ptr", pa)
}

; ---- actions ----
; the selected macro goes into the current profile, switched off (the user checks the key and turns it on)
LibDownload() {
    global LibBusy
    it := LibSel()
    if (!it || LibBusy)
        return
    LibBusy := true
    j := LibCall("POST", "/" it["id"] "/download", Map())
    LibBusy := false
    if j.Has("error")
        return LibFail(j)
    d := j.Has("data") ? j["data"] : 0
    if !(d is Map && d.Has("type") && (d["type"] = "move" || d["type"] = "seq"))      ; never a script from the library
        return ThemedNote(LibErr("bad_macro"), , true)
    m := Defaults()
    for k in ["type", "hotkey", "app", "dirs", "actions", "seq", "press", "g1", "g2", "g3", "ge", "repeat", "exact"]
        if d.Has(k)
            m[k] := (k ~= "^(g\d|ge|repeat|exact)$") ? Integer(Num(d[k])) : String(d[k])
    if (Trim(m["hotkey"]) = "")
        m["hotkey"] := "undefined"
    m["name"] := LibFreeName(j["name"])
    if it["mine"]                                               ; my own macro back from the library: shared (gold icon)
        m["libshare"] := it["id"], m["libsharehash"] := LibHash(m)
    else                                                        ; someone else's: not shared again unchanged
        m["libsrc"] := it["id"], m["libsrcby"] := it["author"], m["libsrchash"] := LibHash(m)
            , m["libsrcver"] := j.Has("version") ? j["version"] : 1
    m["profiles"] := CurProfile
    m["enabled"] := 0
    m["tkey"] := "", m["file"] := "", m["trusted"] := 1
    Macros.Push(m)
    Save()
    Refresh()
    for i, v in View
        if (v == m)
            LV.Modify(i, "Select Focus Vis")
    if (j.Has("counted") && j["counted"]) {                     ; first download from this install
        it["downloads"] += 1
        LibLV.Modify(LibLV.GetNext(0), , it["name"])
    }
    Toast(_T("`"{1}`" added to profile {2} - switched off, tick it to turn it on.", m["name"], CurProfile), 3000)
}

LibFreeName(base) {
    base := CleanName(base) = "" ? _T("Downloaded macro") : CleanName(base)
    nm := base, n := 1
    loop {
        taken := false
        for m in Macros
            if (m["name"] = nm)
                taken := true
        if !taken
            return nm
        nm := base " (" n++ ")"
    }
}

LibRateMenu(ctrl, *) {
    it := LibSel()
    if (!it || it["mine"])
        return
    m := Menu()
    loop 5 {
        n := 6 - A_Index
        label := StrReplace(Format("{:" n "}", ""), " ", Chr(0x2605)) StrReplace(Format("{:" (5 - n) "}", ""), " ", Chr(0x2606)) "   " n
        m.Add(label, LibRate.Bind(n))
        if (it["my"] = n)
            m.Check(label)
    }
    ControlGetPos(&x, &y, , &h, ctrl)
    m.Show(x, y + h)
}

LibRate(n, *) {
    it := LibSel()
    if !it
        return
    j := LibCall("POST", "/" it["id"] "/rate", Map("stars", n))
    if (j.Has("error") && j["error"] = "too_many")
        return ThemedNote(_T("This macro already has several ratings from your internet connection, so another one is not counted."), _T("Macro Hub"), true)
    if j.Has("error")
        return LibFail(j)
    it["rating"] := j["rating"], it["count"] := j["count"], it["my"] := j["my"]
    LibLV.Modify(LibLV.GetNext(0), , it["name"])                ; repaint the row
    LibShowSel()
    Toast(_T("Thank you for rating!"))
}

LibReport() {
    it := LibSel()
    if !it
        return
    why := ThemedInput(_T("Report macro"), _T("Why should `"{1}`" be removed from Macro Hub? For example: a farm / AFK macro (not allowed), it does not work, or spam.", it["name"]))
    if (why = false || Trim(why) = "")
        return
    j := LibCall("POST", "/" it["id"] "/report", Map("reason", SubStr(Trim(why), 1, 200)))
    if j.Has("error")
        return LibFail(j)
    ThemedNote(_T("Thank you. The macro will be checked."))
}

LibDelete() {
    it := LibSel()
    if (!it || !it["mine"])
        return
    if (ThemedAsk(_T("Macro Hub"), _T("Delete from Macro Hub?"), _T("`"{1}`" will be removed from Macro Hub for everyone, with its ratings. Your own copy in the list stays.", it["name"]), [[_T("Delete"), "yes", "btndanger"], [_T("Cancel"), "", "btnprimary"]]) != "yes")
        return
    j := LibCall("DELETE", "/" it["id"])
    if j.Has("error")
        return LibFail(j)
    for m in Macros                                             ; the share icon of the own copy turns grey again
        if (m["libshare"] = it["id"])
            m["libshare"] := ""
    Save()
    RedrawList()
    LibLoad()
}

; fingerprint of what a macro shares (CRC32 of its library data)
LibHash(m) => LibHashData(LibData(m))
LibHashData(d) {
    s := JsonStr(d)
    buf := Buffer(StrPut(s, "UTF-8"))
    n := StrPut(s, buf, "UTF-8") - 1
    return Format("{:08x}", DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", buf, "UInt", n, "UInt"))
}

; downloaded from the library and not changed since: it can't be shared (it is someone else's macro)
LibFromLib(m) => (m["libsrc"] != "" && m["libsrchash"] = LibHash(m))

; shared by me and changed since (Macro Hub still has the old version)
LibSharedChanged(m) => (m["libshare"] != "" && m["libsharehash"] != "" && m["type"] != "script" && m["libsharehash"] != LibHash(m))

; ---- sharing: the share icon at the end of a row in the main list ----
LibShareMacro(m) {
    global LibAuthor, LibGame, LibSort, LibWho
    if !IndexOf(m)
        return
    if (m["type"] = "script")
        return ThemedNote(_T("Script macros can't be shared - only Move + actions and Sequence macros."), , true)
    if LibNew.Has(m)                                            ; downloaded, and its author has a newer version
        return LibShowUpdate(m)
    if LibFromLib(m)
        return ThemedNote(_T("`"{1}`" comes from Macro Hub (author: {2}), so it can't be shared again as it is. Change it first - for example a delay or a key - and then share your own version.", m["name"], m["libsrcby"]), _T("Share macro"))
    if LibSharedChanged(m)
        return LibOfferUpdate(m)
    if (m["libshare"] != "")
        return ThemedNote(_T("`"{1}`" is in Macro Hub and up to date. When you change it, you can update it there.", m["name"]), _T("Share macro"))
    if !LibOnline()                                             ; know it before the form is filled in
        return ThemedNote(_T("No connection to Macro Hub. Sharing needs the internet - try again when you are online."), _T("Share macro"), true)
    f := LibShareForm(m)
    if !f
        return
    j := LibCall("POST", "", Map("name", f["name"], "descr", f["descr"], "author", f["author"], "game", f["game"], "data", LibData(m)))
    if (j.Has("error") && j["error"] = "duplicate") {          ; exactly this macro is in the library already
        if j["mine"] {
            m["libshare"] := j["id"], m["libsharehash"] := LibHash(m)
            Save()
            RedrawList()
            return ThemedNote(_T("You have already shared this macro as `"{1}`". Change it to share a new version.", j["name"]), _T("Share macro"))
        }
        return ThemedNote(_T("This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version.", j["name"], j["author"]), _T("Share macro"), true)
    }
    if j.Has("error")
        return LibFail(j)
    m["libshare"] := j["id"], m["libsharehash"] := LibHash(m)
    LibAuthor := f["author"], LibGame := f["game"]
    Save()
    RedrawList()
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd)) {      ; the panel is open: show it among my macros
        LibWho := "mine", LibSort := "new"
        LibTabs()
        LibBtn["sort"].Text := LibSortText()
        PaintBtn(LibBtn["sort"].Hwnd, false)
        LibSearch.Value := ""
        LibLoad()
    }
    ThemedNote(_T("Thank you for sharing! `"{1}`" is now in Macro Hub.", f["name"]))
}

; ---- my shared macro was changed: update it in Macro Hub (ratings and downloads stay) ----
LibOfferUpdate(m) {
    if !(IndexOf(m) && LibSharedChanged(m))
        return
    if (ThemedAsk(_T("Macro Hub"), _T("Update in Macro Hub?"), _T("`"{1}`" is shared in Macro Hub. Update it there with your changes? Its ratings and downloads stay, and Macro Hub shows it as updated. Players who downloaded it get a notice.", m["name"]), [[_T("Not now"), "", "btn"], [_T("Update"), "yes", "btnprimary"]], false) = "yes")
        LibUpdateShared(m)
    else
        RedrawList()                                            ; the share icon keeps its dot: it can be updated later
}

; quiet = sent by itself later (it was asked for while offline): no messages, only a short notice when done
LibUpdateShared(m, quiet := false) {
    j := LibCall("PUT", "/" m["libshare"], Map("data", LibData(m)))
    if (j.Has("error") && j["error"] = "too_many") {            ; updated a moment ago: sent again by itself in a while
        m["libpend"] := 1
        Save()
        if !quiet
            ThemedNote(_T("You updated this macro a moment ago. The app sends this change by itself in a few minutes."), _T("Macro Hub"))
        return
    }
    if (j.Has("error") && j["error"] = "network") {             ; no internet: kept, sent when online again
        m["libpend"] := 1
        Save()
        if !quiet
            ThemedNote(_T("No connection to Macro Hub. Your change is kept - the app sends the update by itself as soon as you are online again."), _T("Macro Hub"), true)
        return
    }
    m["libpend"] := ""
    if (quiet && j.Has("error"))                                ; refused meanwhile: the dot stays, the user decides
        return Save()
    if (j.Has("error") && j["error"] = "duplicate")
        return ThemedNote(_T("This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version.", j["name"], j["author"]), _T("Macro Hub"), true)
    if (j.Has("error") && (j["error"] = "not_found" || j["error"] = "not_owner")) {     ; deleted from Macro Hub meanwhile
        m["libshare"] := "", m["libsharehash"] := ""
        Save()
        RedrawList()
        return ThemedNote(_T("`"{1}`" is no longer in Macro Hub. Share it again with the share icon.", m["name"]), _T("Macro Hub"), true)
    }
    if j.Has("error")
        return LibFail(j)
    m["libsharehash"] := LibHash(m)
    Save()
    RedrawList()
    if (LibGui && DllCall("IsWindowVisible", "Ptr", LibGui.Hwnd) && LibWho = "mine")
        LibLoad()
    Toast(_T("`"{1}`" is updated in Macro Hub.", m["name"]), 2500)
}

; ---- macros downloaded from Macro Hub: did their authors update them? ----
LibCheckUpdates(force := false) {
    static told := Map()                                        ; versions already announced in this session
    static last := -1000000
    if (!force && A_TickCount - last < 60000)                   ; (window shown again and again: once a minute is enough)
        return
    last := A_TickCount
    for m in Macros                                             ; updates of my shared macros asked for while offline
        if (m["libpend"] != "")
            LibSharedChanged(m) ? LibUpdateShared(m, true) : (m["libpend"] := "")
    LibLinkOld()
    ids := ""
    for m in Macros
        if (m["libsrc"] != "" && m["type"] != "script")
            ids .= (ids = "" ? "" : ",") m["libsrc"]
    if (ids = "")
        return
    j := LibCall("GET", "", "", RegExReplace(LibApi, "macros$", "versions") "?ids=" ids)
    if (j.Has("error") || !j.Has("items"))
        return
    byId := Map()
    for it in j["items"]
        byId[String(it["id"])] := it
    LibNew.Clear()
    fresh := []
    for m in Macros {
        if (m["libsrc"] = "" || !byId.Has(String(m["libsrc"])))
            continue
        it := byId[String(m["libsrc"])]
        if (it["version"] > Num(m["libsrcver"] = "" ? 1 : m["libsrcver"]) && it["data"]["type"] != "script") {
            LibNew[m] := it
            if !told.Has(it["id"] "/" it["version"])
                fresh.Push(m), told[it["id"] "/" it["version"]] := true
        }
    }
    RedrawList()
    if fresh.Length
        TrayTip(fresh.Length = 1 ? _T("`"{1}`" has a new version in Macro Hub. Click its green arrow in the list to see the changes.", fresh[1]["name"])
            : _T("{1} downloaded macros have a new version in Macro Hub. Click their green arrows in the list to see the changes.", fresh.Length), "ComboCrown", 0x24)
}

; macros downloaded before the app remembered where they came from (or shared from another install): asked once,
; Macro Hub finds them by what they do - also an older version - so they get update notices / the gold icon
LibLinkOld() {
    ask := [], body := []
    for m in Macros
        if (m["type"] != "script" && m["libsrc"] = "" && m["libshare"] = "" && m["libchk"] = "" && body.Length < 100)
            ask.Push(m), body.Push(LibData(m))
    if !ask.Length
        return
    j := LibCall("POST", "", Map("items", body), RegExReplace(LibApi, "macros$", "match"))
    if (j.Has("error") || !j.Has("items"))
        return                                                  ; offline: asked again next time
    for it in j["items"] {
        m := ask[it["index"] + 1]
        if it["mine"] {
            if (it["version"] = it["latest"])
                m["libshare"] := it["id"], m["libsharehash"] := LibHash(m)
        } else
            m["libsrc"] := it["id"], m["libsrcby"] := it["author"], m["libsrcver"] := it["version"], m["libsrchash"] := LibHash(m)
    }
    for m in ask
        m["libchk"] := 1
    Save()
}

; the new version of a downloaded macro: what changed, take it or keep mine
LibShowUpdate(m) {
    if !LibNew.Has(m)
        return
    it := LibNew[m]
    mine := m["libsrchash"] != LibHash(m)                       ; the user changed the downloaded macro himself
    done := false, res := ""
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Macro Hub"))
    g.SetFont("s10 bold", "Segoe UI")
    hc := DlgText(g, "x16 y14 w528", _T("New version of `"{1}`" by {2}", m["name"], it["author"]) (it["updated"] ? " (" LibDate(it["updated"]) ")" : ""))
    hc.GetPos(, &hy, , &hh)
    y := hy + hh + 6
    g.SetFont("s9 norm", "Segoe UI")
    if mine {
        wc := DlgText(g, "x16 y" y " w528", _T("You changed this macro yourself - updating replaces your changes with the new version."))
        wc.GetPos(, &wy, , &wh)
        y := wy + wh + 6
    }
    g.AddText("x16 y" y " w528", _T("Changes (yours → new):"))
    g.SetFont("s10 norm", "Consolas")
    ed := g.AddEdit("x16 y" (y + 20) " w528 h220 Multi ReadOnly", StrReplace(LibDiff(LibData(m), it["data"]), "`n", "`r`n"))
    Roles[ed.Hwnd] := "code"
    g.SetFont("s9 norm", "Segoe UI")
    btnY := y + 20 + 220 + 16
    Pick(v, *) {
        res := v
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
    AddBtn(g, "x184 y" btnY " w110 h32", _T("Later"), Close)
    AddBtn(g, "x304 y" btnY " w110 h32", _T("Keep mine"), Pick.Bind("keep"))
    AddBtn(g, "x424 y" btnY " w120 h32", _T("Update"), Pick.Bind("update"), "btnprimary")
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w560 h" (btnY + 46), oh)
    SendMessage(0xB1, 0, 0, ed)                                 ; EM_SETSEL: nothing selected
    while !done
        Sleep 50
    if (res = "")
        return
    if (res = "update") {
        d := it["data"]
        for k in ["type", "hotkey", "app", "dirs", "actions", "seq", "press", "g1", "g2", "g3", "ge", "repeat", "exact"]
            if d.Has(k)
                m[k] := (k ~= "^(g\d|ge|repeat|exact)$") ? Integer(Num(d[k])) : String(d[k])
        if (Trim(m["hotkey"]) = "")
            m["hotkey"] := "undefined"
        m["libsrchash"] := LibHash(m)
    }
    m["libsrcver"] := it["version"]                             ; this version is dealt with (also "keep mine")
    LibNew.Delete(m)
    Save()
    Apply()
    Refresh()
    if (res = "update")
        Toast(_T("`"{1}`" is updated to the new version.", m["name"]), 2500)
}

; what differs between two versions of a macro, one line per change; a sequence line by line (- removed, + added)
LibDiff(a, b) {
    out := ""
    lab := Map("type", _T("Type"), "hotkey", _T("Trigger key"), "press", _T("Press"), "repeat", _T("Run"), "app", _T("Only in app (exe)")
        , "dirs", _T("Directions (optional)"), "actions", _T("Actions in order"), "exact", _T("Exact delays"))
    Val(k, v) {
        switch k {
            case "type": return TypeLabel(v)
            case "press": return v = "tap" ? _T("Short tap") : v = "double" ? _T("Double tap") : v = "hold" ? _T("Long press") : _T("Normal")
            case "repeat": return v ? _T("Repeat while key is held") : _T("Once per key press")
            case "exact": return v ? _T("ON") : _T("OFF")
        }
        return v = "" ? Chr(0x2014) : v
    }
    for k in ["type", "hotkey", "press", "repeat", "app", "dirs", "actions"]
        if (a[k] != b[k])
            out .= lab[k] ":`n    " Val(k, a[k]) "  →  " Val(k, b[k]) "`n"
    for i, k in ["g1", "g2", "g3", "ge"]
        if (a[k] != b[k])
            out .= _T("Delays (ms)") " " i ":  " a[k] "  →  " b[k] "`n"
    if (a["exact"] != b["exact"])
        out .= lab["exact"] ":  " Val("exact", a["exact"]) "  →  " Val("exact", b["exact"]) "`n"
    if (a["seq"] != b["seq"]) {
        out .= _T("Sequence") ":`n"
        x := StrSplit(a["seq"], "|"), y := StrSplit(b["seq"], "|")
        ; longest common subsequence: unchanged lines stay, the others are marked
        n := x.Length, mm := y.Length
        L := []
        loop n + 1 {
            row := []
            loop mm + 1
                row.Push(0)
            L.Push(row)
        }
        i := n
        while (i >= 1) {
            j := mm
            while (j >= 1) {
                L[i][j] := (x[i] = y[j]) ? L[i + 1][j + 1] + 1 : Max(L[i + 1][j], L[i][j + 1])
                j--
            }
            i--
        }
        i := 1, j := 1
        while (i <= n || j <= mm) {
            if (i <= n && j <= mm && x[i] = y[j])
                out .= "    " x[i] "`n", i++, j++
            else if (i <= n && (j > mm || L[i + 1][j] >= L[i][j + 1]))
                out .= "  - " x[i] "`n", i++                       ; removed lines first, then the added ones
            else
                out .= "  + " y[j] "`n", j++
        }
    }
    return out = "" ? _T("(no difference)") : RTrim(out, "`n")
}

LibDate(unix) => FormatTime(DateAdd("19700101000000", unix, "Seconds"), "ShortDate")

; what is shared of a macro (not its toggle key, profiles or on / off state)
LibData(m) {
    d := Map()
    for k in ["type", "hotkey", "app", "dirs", "actions", "seq"]
        d[k] := String(m[k])
    for k in ["g1", "g2", "g3", "ge", "repeat", "exact"]
        d[k] := Integer(Num(m[k]))
    d["press"] := PressOf(m)
    if (Trim(d["hotkey"]) = "undefined")
        d["hotkey"] := ""
    return d
}

; name, game, description and nickname for sharing; returns a Map or false
LibShareForm(m) {
    res := false, done := false
    games := []                                                 ; games already in the library (+ the last one used)
    for x in LibGames                                           ; (loaded by LibOnline just before)
        games.Push(x["game"])
    if (LibGame != "") {
        known := false
        for x in games
            known := known || (x = LibGame)
        if !known
            games.InsertAt(1, LibGame)
    }
    oh := DlgOwner()
    g := Gui((oh ? "+Owner" oh " " : "") "+ToolWindow +AlwaysOnTop", _T("Share macro"))
    g.SetFont("s10 bold", "Segoe UI")
    DlgText(g, "x16 y14 w388", _T("Share `"{1}`" in Macro Hub", m["name"]))
    g.SetFont("s9 norm", "Segoe UI")
    g.AddText("x16 y48 w388", _T("Name"))
    eN := g.AddEdit("x16 y66 w388 h26 Limit40", m["name"])
    g.AddText("x16 y100 w388", _T("Game (people filter and search by it, for example 4Story)"))
    eG := g.AddComboBox("x16 y118 w388", games)
    eG.Text := LibGame
    SendMessage(0x141, 30, 0, eG)                               ; CB_LIMITTEXT
    g.AddText("x16 y152 w388", _T("Description (optional): what it does, for which class"))
    eD := g.AddEdit("x16 y170 w388 h70 Multi Limit300", "")
    g.AddText("x16 y248 w388", _T("Your nickname"))
    eA := g.AddEdit("x16 y266 w388 h26 Limit24", LibAuthor)
    hc := DlgText(g, "x16 y302 w388", _T("Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."))
    Roles[hc.Hwnd] := "hint"
    hc.GetPos(, &hy, , &hh)
    btnY := hy + hh + 16
    Ok(*) {
        nm := Trim(eN.Value), au := Trim(eA.Value), gm := Trim(eG.Text)
        if (nm = "" || au = "" || gm = "") {
            ThemedNote(_T("Please fill in the name, the game and your nickname."), , true)
            return
        }
        res := Map("name", nm, "game", gm, "descr", Trim(StrReplace(eD.Value, "`r", "")), "author", au)
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
    AddBtn(g, "x194 y" btnY " w100 h32", _T("Share"), Ok, "btnprimary")
    AddBtn(g, "x304 y" btnY " w100 h32", _T("Cancel"), Close)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)
    ApplyTheme(g)
    if oh
        DllCall("EnableWindow", "Ptr", oh, "Int", 0)
    ShowOver(g, "w420 h" (btnY + 46), oh)
    if (LibGame = "")
        eG.Focus()
    else if (LibAuthor = "")
        eA.Focus()
    else
        eD.Focus()
    while !done
        Sleep 50
    return res
}

; ---- JSON (answers of the library) ----
JsonParse(s) {
    i := 1
    return JsonVal(s, &i)
}

JsonVal(s, &i) {
    JsonWs(s, &i)
    c := SubStr(s, i, 1)
    if (c = "{" || c = "[") {
        obj := c = "{" ? Map() : []
        end := c = "{" ? "}" : "]"
        i++
        JsonWs(s, &i)
        if (SubStr(s, i, 1) = end) {
            i++
            return obj
        }
        loop {
            if (end = "}") {
                k := JsonVal(s, &i)
                JsonWs(s, &i)
                if (SubStr(s, i++, 1) != ":")
                    throw Error("json")
                obj[k] := JsonVal(s, &i)
            } else
                obj.Push(JsonVal(s, &i))
            JsonWs(s, &i)
            c := SubStr(s, i++, 1)
            if (c = end)
                return obj
            if (c != ",")
                throw Error("json")
        }
    }
    if (c = '"') {
        if !RegExMatch(s, '\G"((?:[^"\\]|\\.)*)"', &mm, i)
            throw Error("json")
        i += mm.Len
        return JsonUnesc(mm[1])
    }
    if RegExMatch(s, "\G-?\d+(\.\d+)?([eE][-+]?\d+)?", &mm, i) {
        i += mm.Len
        return (mm[1] = "" && mm[2] = "") ? Integer(mm[0]) : Float(mm[0])
    }
    for w, v in Map("true", 1, "false", 0, "null", "") {
        if (SubStr(s, i, StrLen(w)) == w) {
            i += StrLen(w)
            return v
        }
    }
    throw Error("json")
}

JsonWs(s, &i) {
    while (i <= StrLen(s) && InStr(" `t`r`n", SubStr(s, i, 1)))
        i++
}

; JSON text of a Map / Array / number / string; every letter outside plain ASCII as \uXXXX
JsonStr(v) {
    if (v is Map) {
        t := ""
        for k, x in v
            t .= (t = "" ? "" : ",") JsonStr(String(k)) ":" JsonStr(x)
        return "{" t "}"
    }
    if (v is Array) {
        t := ""
        for x in v
            t .= (A_Index = 1 ? "" : ",") JsonStr(x)
        return "[" t "]"
    }
    if (v is Number)
        return String(v)
    out := '"', p := StrPtr(v)
    loop StrLen(v) {
        o := NumGet(p, (A_Index - 1) * 2, "UShort")
        out .= o = 34 ? '\"' : o = 92 ? "\\" : o = 10 ? "\n" : o = 13 ? "\r" : o = 9 ? "\t"
            : (o < 32 || o > 126) ? Format("\u{:04x}", o) : Chr(o)
    }
    return out '"'
}

; text for a URL query (UTF-8, %XX)
UriEnc(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    n := StrPut(s, buf, "UTF-8") - 1
    out := ""
    loop n {
        b := NumGet(buf, A_Index - 1, "UChar")
        out .= (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b = 45 || b = 46 || b = 95 || b = 126 ? Chr(b) : Format("%{:02X}", b)
    }
    return out
}

; ============ embedded images (base64, written to config\assets by EnsureAssets) ============
IconB64() {
    return "
(Join
AAABAAQAEBAAAAEAIADSAgAARgAAACAgAAABACAAmAcAABgDAAAwMAAAAQAgAGkNAACwCgAAAAAAAAEA
IABFTwAAGRgAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAplJREFUeJyNk8tLlGEU
xn/v+346po0zw1RqNU3ZlBd0EURFtiqiaNEiwi5Q2LJ/oWWrFm2KtuEmItxOVFDRKqlwKssuoualSSa8
NKLjN9N873tajEpBCx84cOAcHh6e5xzV19dnuru7bX9/JpVMbj9rjImUSkWllOZ/UEoF+fzC487O1pci
UlkaHR2/4PvFWVknfL9os9ncDQAymUzK94tLK7OyiATrKCciMjw8fl7H4w3na2pCdTgXAN7E4EMz/fWF
AUxhPmvyuWEDmPnpz2bk1T0DGOesA1w0Gr6qjfHqAXGgQGhKdTH58RHiAr68vMu7RxWlo28esCm5v2KE
oACttdroiTgLKK01MxMDzE9/QptqPjy7TV10OxvCWxhIX8erqmF26i1Lc5MkOk5UeASrAbXqcP2WFBOD
abQx5Mb6SR04x95Dl8iN9rN5535GXt+nfnPzP6F4q52zAaHaKIn24zTsPszWllmmhp4Qju+k5fBlNu3Y
R2Oqi0jDHpyzaG0AWAtbK42II9Fxkg/PbiHOMv31BUPP7xCqjZFJX2db61FEHIisSVhTgNYoIBxP0trV
w+/CHNvajhGUCnhVIZKdp2hoPljRbfRfBOIAKPkLuHIRpQ2xpjZCdTFKy3kWfo4QbWzBln2WF3KUS4uE
47vQxlshUBoRwTNVfBtMU/j1ncW5KWJNLdggICgtMjs5gFe9AWcD/KU5WruuUBtpBAQPEKUUprqWRMdJ
fnx+SrSpHWOqsIFPXTQBwFL+BxtjCfK5YawtAzgEeP9+6Ii1TlbOMxARu476LSIyPv79GgDZbO7Geh9p
FTMz8097e3trlIhopZQbG5u6GItFeoxSkbINlHOydmCVkNRKdiooFJbTZ86cvpnJZMp/AN7Ez4l0uUcz
AAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAHX0lEQVR4nLWXa2xU
1xHHf+fuy8bG+AnYDq4NwcaAiXkaUAguiBBoSVUkSCmUNlVUoSqlVR+kqlq5VFU+JKqIokoENYE2RbQN
AbXIiQtJQ4mBGjDYvGzHGD/A78eu8fqx3t17ph/uelnjhbRRMtLV1T1nzvn/Z87MnLkwXpSI2PiCRESU
iKjIMXvkpGEoUUqZFy5UzcvMTN8cE+NcoZSyay2fGdRut4vf77/R23uvTCn1IUBJSYmxd+9ePYHZ4sXf
c3R0dO0bGfH55QuQ3l5P2alTZzMszBIjEtyA1faenr4zEfoBEQl+Tk9AREwRkcHB4bby8oszlQIRMRg7
8/b2rn0hYL+I6Ejm2gyK1mZ0s7SONijaDEab84uIuN33LmzZUuK0DAeuXLkx1+cbNUNso+34eUpARKSh
oeU7AAZAWlrKcy6X0wAECEWpFXgBn5e6swfp76ofO7Jw7Oign4DPCyKWvlhP0D9M3blDeDpqJ6wJ7a8T
EyfvFBFlAMTEuJaGlFSknohgc8TQfPU9zv/tZ4hoQBBtAtBy7T0qT/wGlKUrokEpassPcrn0ZRyuuLEw
v09aawMwHA7n3P37jyQaoXGHUuPS01qmTQzDTtHml3G336Tl2vsoizPa9FN3/jANV/6Op6MWpQyUMvB5
e7h55g8Urv8p8clZaDMQXjPODQq7w+EIz0RJdMGw2UEpktLzyC7cRPXJ3xEMjKAMG7cr38Xb10J88gyu
nnotvOv10/uxuyaRu2I7AIbNMXFrQMTCnEgtBK7NALcqDtPVWAEIy772a3yDfTRWHiPoH+ZK2avkLt/G
U9v20XK9jJ47VfgGe6k79zaLNuzB4YrH29tE3dmDDHnawqgPin3CCCBaY9ic+IYHqDiwndSsQrILNpCe
u4rac38kKT2f2PhUcpd/k0lT0smcU0xV2avETk4jZUYByen5fPjmt+m9U01yRj65K3Za4Fbyj8OK6oGx
M8tbsYO4pMcYHeqnofId2j8px9NRT+ft86x94W1iJ08FERZt2EN/Zz1NV9+noHgX9RWHGb7XQTDoZ17x
LgybPRTAEyX6ESiFaBNnbAJZ85/GsNl55vvHWL3jdXIKv0rN2T9hs9lRykCA5Mz5xKfMIH1WEdNmrWDB
uh+RmbeaKalfIn32k4CgjOh33ENiwCIBMGflt/D2tXC35l9k5BWzattrOJyxVJ/aB0qhgPb6j3G33qRg
7Ys4YxMQ4JOKI+St3GlZr6Nb/0gCShmIaOKTs8ia/zS15W+hTT+GzcET63bTcOko97obQCmqyl4hI28V
02cVAVB//s84Y+LJKXw2vNf/TQAIJ2f+k8/j6ayju/kyKMWsJVtInDabG/9+g7s3TuJur2PJpl8CCjPg
o+HSUR5fuhVHTLxVtKLUmDGJmgVhLxiWF1KzFjJtZhFnDr/IlLTHSXlsLgvW7eb80Z9z5/oHzF31PL13
qij/y4/RwQAB/zCzl33DsuAR4J/ugQgpXPdDsuauIXFaDsFRL0kZ+UyfWYRIkNzl2xnytJI4NZuUzDks
3riHuKRMy4hHuP+RHhDRofJq5W5a9lLSspeO05m97DmmTJ3J5NRsCtbujrJehdPPKvUTvRG9EIXAw8Vj
7H7UJsqwhd+Z+WvIzF8zcV2E5dHumIcS0NrEMGx4OmppqS5l4caXaLz8Lq5JyfR31pExZw1NV46z6Cu/
oLHqH7hiJ9NWdwZtBjCDo6zc8goNlUdpvlrKvNUvkDpjITc++j0imnnFu3DFJU8gMO6ADMOGiCYpPZ/A
qJf6iiOMDnkY6m+jofIYXbf/g90VR83Hb+If7sfdVoNhs5OWtRDRJl1NF+m4VU7h+p/QVHWChkt/pa/9
JlNzlmEPX83RCYQLtFIKpRRLni2hp+kirXWnccZOITk9j5ryt0hKz8fn7aG5+gSu+BRccUl0N18k+4lN
BEaHcE1KInXGAszAKFNzipi1aDPN1SfovVMdPibrLfcJKEVEnbSaC8PmoHDjSwR8AyjDhtd9l6Kv/5aW
q6Vkzim2SqsIOuhn/pofcLvyHVIy5yNi8tGh75KQloMrNgF3+038o0MERgfHW24o5fPZrQBpbe1+PdQL
BsKdW6ih9I8MiG/ILcMDXSIiMjzQLSPeXgn6R2R0yCMjg33W+L1O8fsGxQz6pavx4tgm0t18WdxtNZE9
YVBEdF9ff+WBAwesZuH69VtfDuEFx7WPD3S1D+uMddTOeILSuKa0tbXzV2NnYQPo6XGfDCn4Jy7U90G0
Do+J6PsbhwH0OKJam+Fv0zSDIqIHB4e6jh//IEVEFCJiiIgqLT09fWBgqDOCZdA0TW2aoq33Z3tERJum
aY5ZHgyaUlNTvy7SeCT0w3jhQnWux9N/7tP9+dnE6x1ur61tXB/CtBJgLCpFxFBKacDe1NSyIyEhYZvT
6SxQCrsIaC2PLmnRctxADMMmgUDw9uDg0D+vXavfv3HjUz0RWOOLc+QEwL59hxLj4+P+5wvrQQkEApKa
mqK2bn3GHYFhU0qZY9//Bc39fIRPn3m9AAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAADAAAAAw
CAYAAABXAvmHAAANMElEQVR4nM2ae3TV1ZXHP+f3u4/c3ITkJiYpEEyAUALEIIaHCvKoiNKO1vFdxTpV
dKmtrr7WzHS6XHTWrFldLot1arVFxzowUx0D9YEORSwCQgAhBiUPAnkR8iIP8rpJbu69v99vzx+/302D
5IVW273WWVk395x9vt9z9tl7n30ujCEiovbs2eMaq88XKSKii4g2Vp9RwYmIrpQyAQPQd+zYM9nnS8gZ
HBzE9QVRMgxISEigv7/77Lvvbq9XSoViWABLKSWfHqNGAa+UUvLMMy9mXHvtykcSE313xMf7spKTk+NF
BDXiqM8vIqBpiu7uHnNgINzc39+/q6am5pkbb7y+bDiuMRSIim3Z0aPHH2trO9cq54v5JbUh6ezsDldU
VP/qscc2THIwjmpSQ+DLy0+9MExH1FFqWZYlX0YTEcs0TcuZW0RE6uoaPtywYWMKwIYNGy4k4djZcPAR
R8lfWywRiYiINDS0HNm48cUUEdFERF0Avqio+LvOoIizEn9LEhEROX68stDGXKgPt3v1i19suqSlpa1T
RIzxVt6yTLEsU+zF+fzyZ31j9bFERKLhcER27ty7amjhRcQF8NFHpT9z+kZH1XLx0OQvRdIRQ0Ssysqa
Pc6Z1V2A+dBDm9wJCf51gABjBg7LMuhtrwURElKm4fL4Yj5gJL8QM9JRvhdELILtdZhmlMTULFye+DHm
Fl3TlKSmBq7Ztu3tHKVUlaaUkqVLA5OTkydNsTtZo3p5EQuA0t3P8tbGNRzb+RSgEDnfNYtl92s5tZ9T
B7c4faxP9TEBRe1Hr7P96bUc3vbPWGbUJisju3on/liBQLKelpaRD85qZ2ZOzUlJCfgAUWrsMKVpLuat
fBhvfAo1xW/S2ViKUtoQaHsmAKFi/0t88v7zhAe6UcOIighKaURCPVTsfxnTsshddj8eX5KtZxQIDjTR
dYXfH583RMCyT8hYuB0FGiIWKVPmMXPBTYT6zlG274VhoO2VVUqjqXIPbaePEQkFOVm02QYV2wWxQVYd
eY1zTeVMybmSrPyvgwhKG9OCh0REzCECExtg/dkMRMi95n4SUzNpqHifs1UHnF0wQSksI0LZ3k1YloHS
3VQdLaS/q3Goj1Iaod5WTh1+FZfbx9zl69F0tzMHF5jbyItpb8eECSilDTXLMkhMzWLWotuJDvZRtu9F
LMsY6lf38XbO1hwlMHk2GdkFBDubqPjgP0E5ZqQUJ4o2091azbQ5q5gye4Vt/0qhlEKpCcOaAAERQGg5
tZ9zDZ/Yg3Q3ALOvXkdS+gyaqw5ypnQnStMJD3Rx4sB/ARbzlj/A4m8+gTc+idpjb9PZXI6mu+hpq6Km
+A/E+QPMXb4epTQ03Y1SGsFz9Zwp2+kc6L8AAftsKEwzwq5Nd7P7pe9w8uBmgh2niUtIY/51j4MI5Xs3
IWJRV/Im7Q3HmTzzKjLnriYxNZsZC25ioLeN8r32ean44CX6uprJzl9LWnYBod5WakveYP8rj/POM39H
V0ulbVKWOS6BcTN7pWkgQuaca0nLKqDx5H5aag7j9T1HxowlTJ61lKSMmXQ0llP70RtkzLwSXdeZu3w9
ussLIsxdvp4zZbtoqT5I6e5naaz8AF9iKvPX/IDaktcpfufnRMP9WJaFf1I6uVd/Ozb5uAQmZGyxQ5Wz
+HZcbg9x/lRQOrUlb1G09SeE+7uJ86dQuud5EgKZLLtzI5NnLR0am5iaRc6i2wj3d1NxYDODwQ5mX3kP
mu7h4LZ/wTSi+BLSUCiy8tfi9acglsU4Hn3iBGzXJmTOWU1yRg6hYDt5Kx9kxbpfMW3OKgQLIzpIX2cj
FftfYkbBLWi6xx6r7B2cs+x+kjNysEyT+KR05q5YT/3xd8hb8SDX3PkURnQQT5yfnEW3O5NOBNmEvZBC
LAuXx8eMBTdjREOcrfmQ6Qtu5tr7f8cND79K3or16G4fVUe20neuHqWc6Ousojc+mbjESwgPdJF71Tq8
8QFmLryNy6//EZ0tlfR1NZI5ZxVJ6TmIWBP2RBP3V47C6ZffSHL6TJpOfsDZ6oMgQlJ6DvPXfJ/M2csJ
nmuwvZADPBYb6j7eTkvVIVKmzGHWld9CRHB54hnoOUt18Ta88cnkLLrTnmv8mHrxBJSydyEuMY2s/LVE
B4NUF28bClwiwryVD+FLTKXm2Ha6miuG4kY03M+JAy8jYjFn6X12yuC4yfpP/o+e9jqm5FxFenaBnWZM
MBpfFAGbhf0nZ+Gt+JMn01S5j+6zpxyXZ5AyNY/p879BqLeN8n0vAnbQqineSntDKenZVzB9wU12NNZd
GJEBao69he7yMHPRbeenG18EgVguNCltJpm5qxjobaO6uBCUGgpuc5evJyEwlfqyXbTXl2AaYSqLtqDr
buYufwCXJx6l6Sil0VjxJzqbyki7dD5Tc1cCgtL0L44AMGSfOYtux+ObREO5DSLU20pf5xkSL8lm1pI7
CId6OLH/ZUr/9CzdrTVM+epSsi5bS393s926mqg+ug3Lsph5xd+ju+LOz2gnKBddolKahoiQll1AxoyF
tFQdZvfvHkDT3YQHusldei/5X/setR+9SdPJA7RUH8Idl8CCNT+koXwXB179IZ74ZMQyCQ8GSUqbTlb+
NwC5qBwoJhc/AsBxc7OX3I03PgnNHY8oDU98gNqSt4gMBpm3Yj2mGcY0olw6bzWBqXMp3/sCmicBlI5y
eXG54shZeCtefwCxZNR7wFjymYqEMTudlnc9adkLGX5ltCwDT1wiMwpu5eShV+jraiRv1cMgcM26Z530
wiJ2S4vzB7Bt/7Ot5fgERBxsw++3sc9CXELqKGMUsxbfwbmmUgKT5yCWiT9p8sRQycR3Y3wC6tMX8+GK
1XlRU5yVjeUws5bcRY5lpwbneRexL/Ox/w3piAGPzTkBIuPu20DPWSzTGAIeHewjGu5HLBPTiKCUxkBv
K0Yk5AQuhRENERkM4vL4sCyDULCdgd42QsF2TCMyRCjc30Wot/V88ECor+NTize6jFFet1el8uAWWms/
ZM1Dv0dzeSn541N4E1KYknM1Ra/9mOsfLeRs9SE+2fVLrn+0kPhJ6VQfeY3O5gouW/Uouzbdg8vjQ/fE
EQp2ULD2H5lRcAunDr9C6fvPIZbJV6+8m/zVj9Pf1cTh139KT2sV/kAmy+56Gn9gqlMEGJnM6JVe5/o3
f/XjmEaEQ3/4KUopouF+jEgIy4zS2XKSD/77u8y44mZSpuaxb8sjgMIyoxiRAQwjjKbrXPvAyyxY8wPC
/Z34A1MJdpymZMeTLLzxCVase47yfS9yrrGUyoNbCId6WfvYm+QsvgPd7R13I8YwIfuQ6u44Vn77tzSU
v0d96R/xJV6CQmFEBpiauwLd4+PQtp+w4t7nGAi2U7bnN3jjk520QHD7EnF5/Rzf/Rx5qx4hLauAiv0v
kZZ1BVmX3UBadgHT5q3mTNku0i5dQH9nAx+/+zS+SRnEJVzC6EWxYQScst0Iu2BXERICU1n2racpfvvf
aa07gjsuAQAjGkLTPVQWbaHu4+2sfbSQyqIt1BS/jteXhFgmuu6ht72Wc80VZExfhKa7cHsTMCL9Q/PY
Oxrh0stuYOV9v8XrD1D0vz/i5KH/wU7lL7xaxgBrAC6X7tL1kXMQpemIZTJt7mpmX3UPZ8reA0B3eWiu
3Ifb6+e6BzdT9NqPGezvZMkt/8bp0p2YRhRBGOhtJT17IUu++TP2bnmE3vZa5iz7Dj0dp/nkvWc4eej3
tFQdJGfRHbSdLqah/D1mLb6L+Enp9LRVj77ymuYG5xB3d3c1B4PBSHLyJPeoJMQib9Uj9Hacxp/0FVxe
P9n5a1l00xP4EtOYf933Kd39a1bc+xsW3/QEmu7G60viKzOuwjQizFpyFz3tNVQf3coVX/8nlt/9H5Ts
eBIzGubq235OUvpMOptP0NFYSn3pvaRMySP/a99jhBRDiUAkEjkd2wp1330b4qqqTrc4Jeyx69wjSKw0
bpnG6GXy4e8NI7w9DH+PiIYHRlFhv9709PTJG2+8e3nMhPTNm/91cGAgvMNxVWOmhHawip0XuxAbS7Nj
afJ5fWJnSw0r8Krzi722y3aKXiJ2xVsuLPKKM6i9vePk++9XnhARbejRbNu2nbmdnd1RmcADxxcvo+5Q
VERk377if3AIuRxm9nNNSUn5r53+kS8N68QlKiJSXV1/7IYbHvOKiKb+nHLYz6tPPvlkYl1d4xFnwN/S
O1lURKSjo7tz69Yd+Y65aZ+2L6WU4vnnnw/U1zfFSBhOs75MMpZlm4xpmmYMfFtbR+eOHXsXOVhHDsCx
LzZs2JhSWVn7ajh83nOZ4Sj7Mpohww7CmTNnD2/dumOBg3HsS/PwR+Tduw+vqa1teK+1teOiXevnle7u
oNTXN5ceOXL8fsANUFhYeAH4UX8rgf2GYAFs374nNz09NTcuznWZYRh81pvoeCIi4vV6VTgcru/q6qlY
s2bZMcB0vtNieCYshYWFugx/Ef8riPNzn1Ex/D9FgIWTMgEZOgAAAABJRU5ErkJggolQTkcNChoKAAAA
DUlIRFIAAAEAAAABAAgGAAAAXHKoZgAAAAFzUkdCAK7OHOkAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMA
AA7DAAAOwwHHb6hkAABO2klEQVR4Xu29B3hUV54n2rM9M/t2983O9LzZ2fftvt3vm9030w6AA86h23YH
d552d9sd3O3u9us4nafDGAQITDDBGNvYGIMTBgQiiCwQQpQq5yplRBAgEQVIBEkgJFX93/f7n3uqbt0q
6V5JVVJJOr/vO5aMpFPnnnv+4fzjRz6ioKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgMH5ARH+mhhof
+chHMBTGG7QX/O+I6KM2m+3PMbT/x1AvXSEBeS7EOSGck49u2rTpo+qcjCHgZeGlSUI3/tyImpqaj9ls
0b9xOp0fU2PiDbz7mprmj+HMGM+GHoWFhcwYwBTwvfHnCqMIybUzEXwoFPqP4XDtrZFIw2ccjmCB2x2a
53KF9rvdwYMORzDg8YTbXa5gu9utxkQcLleg3euNtDudgQanM1Dh8YQPulzBZT5fVWEgUPU1tztybygU
+mvjuYKg6e/MKYwA+nsBHk/d37rdoSfc7vBsELrLFWrxeCJ90eghqq09SnV1xygabST8fzhcTx5PhDye
qBoTekQoGKxNnAt5TqqqGsnnqyKXK3jR44nYvd7IMr+/5qlQqO5/6s9cf2dRIQcoLBTSXv9vbnfolkCg
5od+f812tzt6KRSqp9paQeh+fzU5nUGy2byxykpfb0WFr9du9/dhOJ3BPo8nHFdjoo9I3OkMxuS5kOek
shLf++NebxVFIoIx4Ey53dEun6/K7fNV/cHjid6nP4u4SphdJxSGALGxlNhYr9f7XyXRe72R7pqao8yx
vd4oVVb6mNjxAvFiA4GqeE1NIzU1tVBLy1m6fPkqj46OTurt7VNDDbp+/QafiStXrtGZM6108uRpqqs7
QuFwHQRIXDIGnCm3O0yRSAPhzAUCNeT1VrkDgdo/QBDJ86kZnz/6kY8oA+KwYLTWu91Vk/z+6iVud+Q8
ODKI3uUKgejxgvqczkC8qqqBif3ixXbq6rpOsViMFBSGgnicqLv7JrW3X6WWljNUW3uY3O5wXGgHrE3G
wQygcUIQ+f3VHwaDNZ/Rn2GlEQwBSQ4qgE3F5no8kZu4n+FuBq5ss/n63O5QvL7+KJ0/f5G6um4Y32EC
8Xg8bSgoSBjPRn/HAwwBwuXIkRPk94tzaLf7e6EZ1NRAa6jHv+/3+aqe27Rp019q55ldjCmHXCEz9ITv
dgcm+XzR0nC4gaqrj0hp31tZ6YtHInV06tQ5fiFGKAJXyCb6O0+4PrS2XmLNwOEIxG02LzSDOIyJOK8+
X3VtIFD9eXmecY1VcQX9AAY+6WM9cMDz332+qve83uhNqPkORyCGzcV97PDh46yS6V9Ify9IQSEXyHTe
Ojuv0/HjLaydQjN1OAJ90AZCoTry+2v3e71V98uzrq4FBuilvsdT9atAoLYVRhaoVbjbQ/JD5cKdXg/j
S1BQGGkYz2BPTw81N58hny9KNpsnBuEFIeb31/YEAtWvl5eXc1yBduYntjYgI/fwvcPh/yevt3of7lHa
HZ9V/cbGphTCz8R9FRTyAfpzCUYAb4I0UuMrDNdeb/Vhtzv0pI4GJqZtQK8GeTyRH4VCdVfAKZ3OYO/B
gx625sM1k2lzFRTyGfqzCuEFIVZZ6WehhisBrgYILJIxLcbYlnEP6dPfvt31V4FAzerq6sPSh9+HyCz4
6+UmKrpXGKvQM4ILF9ooFKrhoDTEp8B16PNVuyorvf8IWtBfg8c1JLerrHTfFQzWRKAWuVyhPkj96upD
dP16d8YNVFAYq5DnuK+vj21ZlZU+1nQRWRgIVLU5nf5nQBPj3jgoid/h8Dzs91e3w13icAQQUMEW1KTU
V4SvML6gP9OIWZEGbsQSgBF4POGfgjbGbQoycqzx1eHw/zgUquuFoQ8b4PVGOLBCQWEiQDKCzs4uikTq
2VOAhDVcg12uyErQyLhjAnrih9RHEgbuQtgA+E/1G6OgMN4hzzoCiQ4dakLcAF+D6+qaoBmsAq2MGyZg
JH6vN9pXUeGOR6MNvAH6DVFQmCjQn/mjR0/SwYNecjrDPeOKCSTv/FLyR9jYB66niF9BIenlQvCQwxFg
46CeCRgT4sYMkj5Ob0Lyg/jB7RQUFJKQQhDGQbs9gOuAxgSCzATGXJyAdGeUl7se9Pur415vJHbggJsl
v/6BFRQUBGIxQROoRyCvAw0Nx8npDPwWtPT226G/MNJZXkKGNlZWeiYHgzVtPl8VEnliiOyD2q9oX0Eh
M6RgFDYBT9ztjvag3oDN5v2BRlv5HScgYvvpo2VlZf/J643UQPWHqw/WfnnnV1BQ6B+SCSBgCMZyCFC/
v7YLAlWjsfzNHZB3Fbs9+B4i/BDkg9BemcyjVH8FBXOATFDJCp4yIUAbkDtQU1ZW9Z/y1jOQzOoL/BDF
ENzuMEf4Xbp0WXsoRfwKClYgaQXFbhAoB0EKgWq3+98DjeXdVQCFPMCVXK7g//b5ajr9/uq+igpP/Pjx
UykPpKCgYA2SZiBAIUjhGUCNjMrKPMwbkBzJ5QoeQEov1BYk9uAhFPErKAwNknYgSGFI9/urYz5fpNXt
dv89BG5edCmSnMhuD/wCHAqBDLj337ghsvoUA1BQGDqkEIUXDYIVNGa3BzbpaW/UIFV/m83/f6PFEiyW
UP1RrFMuXkFBYeiQNHT1aocMEuJOV3a777OgwVFlAlL1dzgCH2icqRecCkENivgVFLIDSUvod4GrQDBY
G3c4Qo2lpaX/XnMLjrxXQPojXa7Ax32+6m63Oxyz2XxxcCr9ohUUFLIDxNKgchYqDqN2pt3uH70AIckA
HI5gmTT8ofYZoIhfQSG7kDR19uwFpA/HfL6quNsdOWezhf5Oa6QzclqAuHfQn3m9wccQpIB7CaqeynJe
igEoKGQfICvQFnoW4rqNhCGHI1AImhzRhCFpeHA6/UVQRSoq/L0IXRSLVMSvoJALSNpCNyLYAgKBmrjL
FWqqq6v7S00DyL0WIPOTvd7wrX5/1Q1068FAh1X9IhUUFLIPkBeM7EIL8PdVVaGUWGjkbAHJeP/AUqgg
6KWOdl1icYr4FRRyCUljqB2AFmTCJRgMgiZznigkDQ0OR+S/eDyhVq83GoflH33V9YtTUFDILXp6ern9
mN3uh1sw5nIFHwdt5jQuQEp/qBxITkCfdKT6gvAV7SsojAykoD12rJk1cNCi0xn8ELSZ02uAVDGczsDu
aLQR0r/vzJnzKYtSUFDILSStdXR0wv0e9/uryeUKn7XZbP+nRqfZNwbKxAOPJ/z/+nxV12H4c7tD8Zs3
e4zrU1BQyDGES5AISXfQxGEMdDqD3wGN5sQlmKzwG/ghVA5I/4aGo4nFKCgojBykFnD69PmRuQbImGOH
w78HkX9gAPBH6hejoKAwUhA0B/e7wxGI+3zVKMJztrw89NcavWbvGiAn83g8f+t2h9q1eOS4vpGngoLC
yENGBlZW+mKIynW7Q0+AVrPqDZCTwdUQCtXF8WHI+hMLMC5JQUFhJCA1bxQM0V0DZoNWs2oHkJM5ncE5
6GuOD1PlvhQURheS9traLrMhUHTbDh7U6nRkLygoU+afKvapoJAf6O7uIZcrGPd6q/D1Ynl5efbsALr7
/39wuYLNfn8NupXEZOy/goLC6ELkBtRCC4gHg7W9lZWBuzTaHb4WkOz0473V54vehPEvGKzhuuUKCgqj
C6mAoxYHPHPIznU6A8+DZrNiB0im/gY+H43C/eeN1dYeTvlwBQWF0YG8gre0nGXbXF3dMXI6QwtBs1lh
ALoAoOmwMgoDYEvKhysoKIwOJA3CJiciAhuhAewDzWblCqDzAMwHdwEDOH1aVf1VUMgHSBpELU7UCkQs
gMMRcGhlwobPAJLFP0P7Re6xv+/y5aspH66goDC6QHqwxxOOI0jP7Q5fjEajf6PR7/A8AUkGEDwgGYDK
/1dQyC+gYrDbHY57PFFyuQLtWXMFisYftj93OkOBcLieCxB0dHTxhyoGoKCQH+jri5HfXxV3OkNxrzdy
zW4P/A/Q77Dah+lzAFyu8BVwF6gZ4DYKCgr5ASmH6+oOs5cOmrrbHf4UaHdYOQGSATidzo+53cH28ccA
tKRq3kELQ2k8eQ6L71L+zjh5n/Ix4J4HAxCl+rNQImz8MwAFhbEPxQAUFCYwFAMYLOIxutJ6lE5W76aW
mj3UUltqOpqrd9GpujK6elGUQB8P6Ovppr7em8Z/HpPo7blOrScC1FKDd7o77f2lDO2dn6zaSRebI9R7
87pxujEFxQCsQtspeC+aa/fR7mVfoJL599GOxZ+gHYsepR2LM4+diz9B2196kLYvfJj82wrpRle7ceYx
BLEHXdda6WhwK5094jb+wthDPE6nDh2kshXfoG3zH6Dt/C4/kfYeEwM/X/QIbV/wENVVvkU3b4xtt7Zi
AIOAfMXXLjWTa+O/0rrpH6eimVNow8w7aMOs/sadVDTzDlo37RYqWfg4nazZqzMgjbVDI9Z7snoPbV/y
GXIV/4m6u8Z2anfX1VZybvgdrS+4ndbPuJ2KCu/M8A51Y+adtG76LbTntS/TuWOexDxj9fkVAxgE9C/5
zGE77Vz6OVo/8w7aOPse2jj7Xu1rhjHnXtpQeDczA8f631Dn5bNyxsR8+Q757Nc7LpB7859ozR//gbYv
+TSdqN4tfyPl9/MbYq2xvj5qiuygbYseY+LGe0p7d4mBn91LRYV3U/Hsu6nONvalP6AYwCAhX/aNjksU
2r1ASIXCqQMzAG0UzbyTtr70KB0LbqZYnyyJPpYOT5yOhbbStsWforXTbqGiGVPIteF31HlFMLT4mHkW
sU5ocpVrfk4boMUV3m3yDsHEp7LGt3/lt6n97CHjpGMSigEMEnpu33oiRLtf+wqr+BsSUsJ4cFIPEBhG
xfs/ShoExwTNiEV2tLdQ5dpfsLq8sfAeWlcwia81R/zFxj/IW8j319vTTYd9G2jz3AepCNJ/wHcn3h8Y
+Oa591OD8302HGozpsw/1qAYwJAgdg0qYNX+V2nTbBD2nRYO0T20cdZdfIgaXWuop3tshUU3utfS1gWf
oHXTb6fiOfex1AQTsK35GV27dNL463mI5D5fPneYyt/5IRUVTKaNs000OFzhZt3N0r/8nR/Q1Yuinf1Y
J35AMYChQtu4tjP1tG/FM5oaaXKQoAXgKjBjEpWt/A5dOl2XnC7PmcCV1mN0YPUPaH3BpKS6POc+Wj9j
Em1d8Agdcr6f9/Qg97jnRifVV67md7Jh1l0Z3pNx3MvXnZIFj9BR/0aK9fXKGVPmH4tQDGCo0HYO/vC6
ylW0ee4DmkFwIAYgBgxJGwrvouoDb9DN6/mcHi3WFIv1Uu3Bt2jTi/fT+hmTqThhLLuXNhbeTUUFk2j/
queo/Zyo9pSPwP7KHYb/ft+Kp1mTMXtfeFYwCXh6HOt+Qdevin6W4wWKAQwLYveuXGii8lXPUdHMyUI6
DmhNFmNdwe1U+sbXqPV4IDlbXjGB5FqElvM0q/tC+uueZc69tL5gMjOH6gPLk8FBefUsyb0Fw8W1bcMs
a4Y/MADYPLYvfoJOVO00TjvmoRjAsCB2Lx6PUaP7Q9o6/2GWkFYYAEvOGVMovGcR3bx+RZsnn4hGrKX3
ZhdF9y2l4tmwgGdwlbGLcypfDUrf+DpdbKkSf8vPkh/Po9/Xs0ddtOf1r9K66bfxFSbtvegG2zlY+k8h
18Y/0I3OtpR5xwMUA8gSOttPkW3Nj4UWMMtMstxDxbPv40O485Uv0OlDNp4jvxiAOB2tJ4K069UvMbOS
BG98FvwbLOQbZ99NoT0Lqae7Q05gmHB0oJf+oT0L2AZjRVMDA1g//VbaufRJaqk7YJx2XEAxgCyiKbyV
dix+XNwtTaSLuD9Dct5Ovm2z6EbHRZ4jP5iAWEN31xUK7JzLHg5hLOuHYKAFzL6HtZ+dy75A54/58uoK
IPe0pf4Arw+MF8Sd9hyG9wOmBunvK5lBN6+LoJ98YWrZgmIAWYHYRQQHeYp/TxusagGQMLhfIqKuSkTU
jTrdaJ+Pa82ZI07a8fJnRbizRhTGZ0ghGKjLhXeKnIcO0f15tAkmEbjV2UbekoJEDMPAzyLeDYKddr/6
JTrdWGmcdtxAMYBsQdvIltq9tOuVJ2ndtFupeM79aQfLSDT4um76rXzHlCHCo6kFyM/uunKOfFsKLEbJ
ibFBsxNsX/IpOtVQwUxEP+foQHz2ichOZrRC+pu/lyLEdcy6k0K75iWuNKP7HLmBYgBZgjwcSI7xlUyn
DbhnWtACcFWAR2Drwk9yRJ2YZ3QOWuKAx+PUUruPti16XBj+jGvud4hrTdGMyeQq/iN1tp9JnXeEoWdm
rg2/p6KC23h9Vt4JpP++N5+mc0dlws/oPEOuoRhANiHvmnX7OV3YmhYgBrSAyg//ha5eEBF1oxFXLwmm
o62F3MW/p6IZt2uq/+AG5zwseJROVO1KEM5oMQHgaGATM7P1BRakP3s1cJW5i6r2L6NYbzfPMZrrzyUU
A8gi5CHpudFBoV3zxd0ZEseKtRlaACLqXO/rZ9R9n1vIteO/TZES2rrgIU36D7z29IHfF75zx/pf0bU2
jaGNOAGJz7t2qYVsa37KWpYV6c93/xduoX0rv02tJ0NiphFf+8hBMYAsQx6Ws0dcVLr8KZbs5hZnjKn8
uxXvfJ+unD9inDbnkOtGkpJ93S9o/fRbMqzR+kCCzZb5D7D0jfeJdz5yhJT8HI7PWPAIMyTT9wB3Jrwd
hVOp1rYyEdQ0cuseeSgGkGXIw4JSUSLiDIUk7jLVAkRc/WROFKqteJNiMblPuT98cs2IcT/k+ZA2zb2P
jX/FJtJy4HEv+9ARG3H5vNYQdgSeRY+rF5qYoRZZlP7i7n8rHXj3eY5+BMYz8QOKAeQA8tBcaI5S2dvf
4WpAluIC4EsvuI3Dbi+dqjFOmzNIwmw/00AH3vk+rZv2cV28/1AHYujvpM0v3sPXmr6+kZKmYv54LEb1
lStpC3I0ODpz4P0Hs0O1n00v3keN3vVC+mOqnK93dKEYQA6Q0AJ6blCD8z1W76EFmElUEB3sBsVzplKk
dDEnGokJU+fPJuRa+3pvUO3BNzmaD3f/4TMATauZfgsdWP0cXTpdq/u8XD2QNnecuGBH2VvPsEdC2GEy
rC9l3MtXMNuHP6erF0Sthtwzq9GHYgA5QTyxscg7P/DO83y4zFRQSXSIq9/92pfpwglhhBL0koPDyCH7
Yt7Wk0Ha99Y32QBmJi0tDy2TbiMyH8tfS1TQzRlh6Rhv9f5ltHkOPBIZ8hcyDLZZLHiEmiLbE+m+OVtn
HkExgBwhIVl7btBhbxEVv6gFl2Q4fPoBQxXH1RfeTcGdLybqzuWGAWgEc7OLwqULmVD5sy0QjOWh+dT3
vvkNOtfk0z42B88CaIzyYnMV7V3+z7RhBiIYzbwwMnZhErk3/pE6r4jYhYQ2Mc6hGEDOkDxAqCBj+/Bn
fMhMq89w6TBIrikchnv2sFNHMNk+kGK+M4crqXQ5MuRuzZ70l0NjaLAHoIZiso5+bp6l+/oVCu9aQMWz
76KiwgHyF3QDuf5I9z1VV05xzfiaMyaVZ1AMIIdIaAF9PXQ8soNKXnrUkhYgDGh3sQfBu2UaXb92Qc6Y
Mv+woK0NGXL+bTOpmMthQ/qbMQAQ1FRWma1V0xFaDYKidr/+FTrdIDIfc2Jci8e5V8GupZ/T8hfAbNPX
o38Wts0gf2H7LLrRKfMXJg4UAxghcDhq8R/5ToqKQGaSSWgBkEyf4sjCJMFkl3BQ4x8Es95ShhzqGAhb
BcpjbZn3IF9V0n7HOKAFzLqLmZ93y3RdLwHjaoYKMRGq9fhKZmqVmq3u8WTa/eqXE9cT/XwTAYoB5Bxi
h6ENtDRUcEIKlw7jjLSBhlZua+ZkjmPvvKy/m2YH16+cJ+eG32qNTSzc/eGlmDGJC2rU21czsaHIqWAC
A/8tawHTb+Nrjcx8zAb016Pmuv3MMItmabULBhjC44Jnnkrh0kXUk0tbSx5DMYARgdjl7q528pfM0gjb
AsEl4uofoabwdq7Nx7NlQXQiU+8YYuQXIkZ+kgW3n1bWfOYUiu5dzIbDs8fctOu1L2sx9iZ/r0XZ4e+d
63/DGpG2EsPKBge5Fx1tp8i5EQk/0s6SYQ36Z+HMxSlU+uY36GJz1DjthIFiACOC5CE/d8wregnAP60d
xvQDmjqQlFO5BolCTdpsmG8ohJP8m2ttLXTw/Z/Q+hlTRPirhXVw2a83v0GtTaKOITwUkX0vW2+OwjkP
k2jbwsd0mY9Dh/x7ZmbhbbRl/qPWCrOizt/MKbRpLuoYvs6emomKickA8NTDPHyDh/i8npudFC5dTJvg
Fpw5xZoWgIi6uffTYe/axGEdGvGIv0FXokPO92jLvIcs1zBEdhw0F1QH7u1OdsRFrMLeFQi4geQ1mwc1
9kR9/YPv/9jQS2AIz6P9CRgjGpaIWAvjZxoGVy+aKioZv/2srsPPED5/uBjSO8wuJiYD0AGExMQ0gi/j
UksNla14OukWNCNASKzpiFH/PrWdSfYSGNyhTf5u25lDtH/lt7QoObPaeFq5r4JJVL7qe2kx8mBIdfZV
tGmOKHWe/vepg+/eM6bQlvkP0SHXB4lrzWCh97A0etYzg4QtwzzaUuRcbJn/MNXZVyfcfiMBedaGxrxz
gwnJAHq7O/ngpIBfTEx7Obl9QZDANeWvsxXdigRmomEj3d1UW7mS79/A4A6S+F344avLl9MmRMlZ7GaE
K8LmF6GBIEZenx8v5mw/20AHVn9PY2j4m/7nZFuBVhEZEhiRksY1miNJRG1nD9GB934k8i1mm3gx5GcX
TKKDH/yErl7SOvwMah8HCe1cZfoM5BuMJAPKhAnFAOTDosvNseBGaq7ZzWpostNLEklmkF3IOdFEQ2aq
CX91/0QjDq/IVNv31re4Um9iLstLFL944WSY9rz+z3wHthKUBIIBk7J98FO6eqk5ZS69FnDEu562QApb
ig0QDG3TnHup5sBy6tVapFl9GMl8EPKLtN1iiyG/osrvbVSy8DHuC6ibUD/98DEA0cMF2noiQE3BTXT+
qE8xgJGEPLCovecp/h3tXPI4OYt+zaooKtl2Xj5N8Vj6S8umzUCuAYa8RvcH7E+Hem0agJOIq7+TDW89
3Z0p8w0M8TvoPxDe85JlPzkT6gzk9T9MxzlGPrWjsf6jRafdnyaboww4t3YPnzGFXYqtJ8LanFaeJfnM
aM5atvLbHGRkun+SmRXcRo4itGiXbtVsof/1Y98vn2vkxiIIuS59/StU+vqXOQZjtDGhGID+BTUFt9K2
lx6lNX/4n6wO73n9K+Td8gI1hbZycwuU6c6kGWSFGWh/fq3tlCi+YVELEL70W2nP8q/S6Ua7NpXZWsTB
BNGgSMmOpU8K46Mkigyfw0NjOCBSR9Fvqetqa2K21OnFv0CdRSLNlgUP6+YfeIgWaXdSaM9L7CLVJkyZ
3ghJ/LjKIGMSf480XlMGoMUhbH/503Q8qu/wM/DnDQztLGSYAhGWKK5y+lAFJyZVvPtDbg1fNP1W+vBP
/0DODf9KXSltxjJMMgKYsAygo+00uYp+J6QvLNMFk1gd3zLvPtr7xtcptPNFlnpXWo/y4UwW6DBgSMwg
+TfHQltp2+InrPUS4Hp1woru317Ice882wBrkD/DYUP/Ae6Gyy67DPMbBlR/BC611JVTLC6fP8Nnaf/U
efU8+/i5krBpERTxM5Hz8Dk602hPVBEeeE/Fz840OqgUHX6m3WIhglF2L7qda/xfvzacHgz4m8x/B9sS
GsScPeLk7EfbBz+mbQs/SRtnTWHNA4wK561k0RN0LFxi/PNRwQRjAKlo9KzjIBsQRfFsFIsUBSFZjZ05
mUpeeoTK3/4mq80na/bStYsnWfVOHNRhIEGYV86TZ9MLwhZgwZeOopa4x+585XPmKqT2GVjvyeq9tG3h
E+z3N/sMDtrRMhJBMGgQok2YMn0S2ufE+qiltox2LPkU76Hp52CAMGdMJl/JLN4Lnqc/wtT+HTUX/dtn
c/SiCKgamAHIu/+uV79IpxsqxFSGqYcK2D8Q1IQej/WVq8i+9me065XP8lVtw8xJbJuAdidjPnBdsX34
C+4nCfT7rCOECckApNrcdqaBKt77/2i9QYqwOo6oN6jAMydzsgiuC6iWU1W2lFt5Xb/WKizixhdo+X0m
f7G5dh/tfOXzlvrVCSZ1N22YMZncG3+fUCMzXQXk4bp28QQ5i34n5rdClLImwatf4uSa5COmf0YS4mdg
Fr6tBYNKLUbwDqQimGySafX/WWAyaKm2dpq1/eJ035mT+aox+D6M6b8HW0h3ZxtfFdEW3b7uV7TzlSeF
K3QWAquEjUWcI20d7Mm5g5uoNjje052b9PlHEhOTAWhPDbW+9uAK0fhyltGKjO+1w8OJLIiXn0Kb5kyl
HS9/mio/+DG398a9+kZHW0atwOyMyXXc6GynwI4XaT3caBaSa4REEx1rjwY2G6dlJIyNsTgd9hXTZgT9
WAk8Yj+5qEoU3jWfLe3WkHxYNOCEtOVafMb5+xmQ0M4Nv08EB6UTqLZXHZfIjaQqTfqb+/0RQ3EbGxvP
HnX3M3cq+MfG34nH2e6AsGFojsihKF3+Fdoy737OPZDZkYLw8dna+UlZx63sLr3YIkKPzdYxEpiQDACQ
m3/+mJf2vfkNfjmZ75LyRcr79x1sGMPddfPc+2jXK58nx/pfszsKVumbN64aP4qlc38vW/477sB7Xv2S
NVuAXAvcc2t+znHwRsh5UZATtQjEXXlgYpFzQ1PY++bX6QJb5weP3t4bFNw1V+soDGZi8jwgDg4OeoSO
BTcnTmXansXj1BTdQdsWo8PPIPIXZk3hGv89mrsxbV7t3zJpUTBuIlrwiH8jtxbDvmxd8DB3DYJWwWnH
7PqU17dMaxLvC1pRbcUbiVJvmdYx0pjwDABZYJG9i2kjpKPpHfzehARlrWDGZDYs4RAgqAeHw7P531hC
QD1MFr9I/Vz9i9evI1q6hNdhJUeAtYCCSUw0h9wfUiyWqoHIeRE5eODdH9DaF1Doc2BCLH7xPn4m+Oer
ypbp3H6Dx/kTQdr3xtdY+oo9G/h5MMCkENKLOA1APENyr7ounxNek5kyf2Hg58Fn4v3sXfE0M+fknElk
Inx4fy6fP0pNkW0U2DWPylY9y7EDIHRoabAZyfLheDYrjAjr2PP6U3QOjVMzrGO0MGEZACBfApo/4k7J
KriFg8qDXzwOoAhqAeFAckLawN2DUNvAjtl0NLiV2s42ZFSl+fN1DOF8k5+JRgQHma1DSBUwgf2rvscH
VjdzkrF0d7J2IgqT3jnAYRXMDW7GA6u+yxWCtZl081oHJGd03xK+MlnRAmRBVCToIE8hWZlH6y8Yi3EC
UcmCR2k9jLYm82FIqQvjnNz//ggPRA/D3InqPZyrUfHe89zjEH+P9yoYvVbMBZ/d7z4ahwilRpRkaDfc
nbIWQuZ1jDQUA+BCEq3k3ap1jk17gRaGjhnAiwA1HtVwwQxg3Kp493mKlC6h5uq9TKh9vamSVR7y3pud
3BNgYyJQJ8Nn6YaMq0cpa9gykuHN4rnk80GFxYFeh2Yf/Rxc9i4UTKLN8x6kesc7GgGmS0crkH9z6VQ1
la38lrh+mDI0odWsfeGfqHz1c9R2OjXnAIFGB979oaZy3z0AI8MQPwNDL1/1bJKZZSC6rmutbNRFeLRt
7c9px9LPsqQHI4T2InsjYm1WmI5xgJFDY9m++NMJD0Q+QTEAjQBPRHfR1vmPDrIZZoahMQMRvy+YAcep
z7qTi2HY1/6Cag+u5Ds/DrUx2OjSqVoqe+ubOgNa/wddxNWLZpx73/iGVnobz5TKAGK9N+loAIbAB4Wx
M8Nc+Jx1L9zC9oKrF/szxFmDZAB4tpqKN4UBjHMeBu7LJ7UA2A5qDiTvyrG+m3TI+QEVv3i/pZBfDA41
fvEeOuxZ26/0h/sOkXm7ln0x0ZkJQ0h6jalrjN04v9UBGwTeJQyXHVr04RC3NSeY0AxAD0RtVX74c9FB
NsOLHNrQM4M7aV3BbSyFccB3L/siuTb+nt1I5495qKP9VIIZIDio5KWHte7CxjmNQzTggPcgsvdluqm1
sk7encXXjvbT7ApkLYddU8lDLe0JaOh5JLBJ+7t0ghkcxN8i2QdRcGunfdyCcVPTAlBFeMUzdOFkJDEH
ciDARMx7LWpXoxmTWOuRNf6N6wJTOeLbwExi7b/9Y7IXQoLojfMOcaCgy7yH6Hh0R0JDG96+ZhcTngHI
lyHKdyOtVIu5N77IYQ8pUe7larUgRKiYMgzZs/kFOurfSG2na6mlbh+VLv+yKNVloboNvkJywm8P45te
xCS0nFiMmmvL2JiVqeknAlRQUQeMQv93Q4X+7w+51wjtY4b53Z0NkVwy7S6K7nuZo/bqbG9TMTcssVK4
BB1+7uDPQ1/CRHMVg1aE2HwYRxMBSybrGvwQHgjc/RFrgliMJIa3t9nEhGcA+peBQ1G+6jtC0mgvMf3F
ZmEkLMdgBpBWt1PRjNv40O5b/hXa/+bXaOtLj2iRgWYMQIYIiyrCwZ1zOUjF+GzA9Y6L5C2ZpdUA1BJ2
oJ6jSs/iT7MBTGK4DACQc8Cqj6uPSNm1tqeQ4GiuGt49n683SEoyj5QU+4lQZGhziYQf7VH0zL7B/g6/
A2ta1lCG0PqQqdjg+iDpEcrCvmYTigEA2i70dHdQDdpjMTFZy5Uf9ki4yLTIQy3GwIoRUD9Ejbs7aOfS
T9OZIw4DASe/P3vUQ7te+aImZUWVXzAA/7bZ1HVFS/jJ0iHVz3M0tJW2wIKPUGQL0lYw4Klc399K0VEx
RDxByUuf5HiBhH1FakHaV7ho+UrB3hbjHNkawvtR9ta3qP1sY2If8g2KARiAfHm05RJEaEH6ZnngQA71
UIqinYirL6Cuy2f5eZJEKL4iSw22AkgmSD9oO7uWfYnOHBbZhdmG/Pxr7S1sCINLrTjD2jOOQvFMaf+e
YQhpjvDjO8i54Q8cMaitIGUdqGNYXf46M3jztOWhDmGXga2nev9rGewy+QPFABIQO9Hd2U7+HbO1RhlW
7pz5NbiXwKLHqLmmNPlk/GjJw3eppZpbdeF+CnU5su+VHPqnkwSIWP9tSBSCLSAH+7puxiTa/vLnuPx6
KuOTg+jcUQ+Vvv4Uh1IP7Eoc+kC/AeQ3IBwaxT+Me5FPUAwggeRBPVV/QMto689llt+jaPpt7GG41iYq
+Bi1ANxHOd6g8A7RhFSztusJJZuQny9SkgtFCrYV24bFAcMiZ90V3snxHMlw7OQ7BZBzEdo9X5Qus3TF
ktcz47/3P4QrUwgP79bp1H1dMNZc7Gs2oBhABly/eoGcRb8RlXPQOmoQkkJEn2nGKrb6p/9ObocIDkK8
+rHglsS5M0p2ds+9/yOqgoo66Ay5wUIwFsx/+rCTdmitu+R6059hkAMRjAVI9/0ynW10ZPhsgZb6ctrx
yufMeyBKdyD//2AZlYh52LbocTpZuw8Ox7R15BMUA0iBJjFifXQstIV7+eFlDoYBIN0T3XLg72cjE0sa
LYpsEPMMb9zLKc6VH+p6CRiIGwayc0e9dOX80f6LnWQR8vO5eWfpYl204/D2REp/MN0AshcN+RfycxHt
6dkyjZO+MuZ86CL9MB/eH/oxCEOkxTVqwV/4e/vaX9KNRE/H/IViAP0A/nAEknBxELiKTIiXjXczptC+
t57mTDh38e9px5JP8x1bRJjdJspmy4NmMt9wRiJEeO791MiJQv10FML/G/9tBIArx57lT2k++AzEaHXA
naolEZW++bSIgRC6hvgg3bOdiGyn7Yse53eBsGexT0miB6NHLARKdqG4afnbz3IuR+Wan9EmeGisGCNR
dgwVfxZ+kvMW8lXq66EYQD9A4Az638E3b6V0Nyd8FEzi2Hc0y+hsP00na0opWraUKtf8hHP3IfXWTfs4
l4eSJbnFARxAHR3iABPAZyEKD8lI/EyjQOypEJ+PtNyaihWCsIbhbmXpr2loVfvR4UdLszUwAHhEXEW/
ZtuI2PP7E+nUYB4IyOJszje+Tv6t0+mw50P2BiHNunr/K7Rx1iQ27Bk/P3Ukk7Mq3vtRwv6S70xAMYAB
gCQS+IvB1a1IKmgK6PiDiD7SEnyQFYf7NuoLorRYxbs/oO1LnmADHGeZTU9mmcmwYeO8QxnsFpt5B2fj
1VS8wfkAaUa+EWcIyc/Dnux/+7si6MqChpVxzLmX1k6/hcrf+QFXd+oPR3xFtH3hJzkvA4wXBI/rGeo5
lL7xFDdfbXSvoXNH3Tr3oeg4ZP/wZ5Z6H+qTqeoqV+kKxIz0Hg8OigFkgHxlkCioPMt1562EsWpS9+AH
P+aoQiMQgdZ+rpErDwd3zqH9b3+H1UUYG8WhnJR0PVrKMx94YL2QcGUrv0kXm4WlfyjZfbkAd/Rxr9VC
hC1UKsrwbLhCbJ7/IDU43qWYTBuWJ1r7Akl88L0f0to//QOtK7idGTSSfxzrf0W1B9+kM0ecbB8wAtem
w551fB1AFKL5uxAVf/av/DZdOq3v3pTfUAzABGcOOzlWn41HFhgAGAUi3kDksrkIrhNGSQBmgHTZw/71
5N0yjdXPLQseYWYANxVSSBOVZhLRgumfOdAAkXC7rDlIFFqSFhc/Okh+dselZu4RCAZgXkXYOATBVX74
M7p87og2s2GPe29SfeVbVPLSQ+wVOfje87wP8AZ0XpbdiXXg2gzifF5tO0n2ot9o/QbN1qWVUZs9Veyz
TPcezW22CMUA+oE8TDevXyNfyUytBJS1wCBIc1QG6rxiiMZjo1t67UAU7bjQHKUG1/vk3PA72vPal2jL
vAcEM0D1G/iV2b0oDr6VNcgBpgRCgaoLaZcfEPsRj/Wyq3LbYi04yCoD0NKL4aVBmnNiVsOVBkQe3r2A
fFun0fHwNtEFKq0Xoax5kPq36B2AdeGqYK75CU2rdPnX8miPrUExAAs4UV1KO5eKqr1WDgOX7V76JFf7
BTIJArHxqT+B+/FGZxudO+ahOttKsn/4c9q19LOJ2nqJJB5OiU3/7IwDqjKHpd7FvQRQUlu3gFEHSoFX
rv1lsluRRSaAe7mreOAioje7rnCVH1QqTi/amu4BSQQMdVzicugiYMjE+s+JWBAOd1Bgx5xECfX09eQn
FAMYAFILwCF1bfyj7kAMdEiT+ej+HXPoRqd5iG3aj+JxVtdRAw/lyqr2v0oH3n2e3Vii3DZq0kErMDmc
ukMKSYYCplB/8wndnZfZCIc6+lxnz4QBSBcnKuycrC4V+8oC3LiJmf4tcxcfI1rq9nMY77qC/grF6vdW
dBxCWXfJ8McSFAOwgnici0eUvPQJS338cGhQ1AJFIGFDGA4guVAw9NqFE5zPH9qziPav+i7364NGYMU7
IQNUcI1xFf+RbnTINlyjBXHq8GwIu979ype0mIAMazcM7vCTaCQi7vEDMVerkHNAQwruelG7fllwUXI2
5e3k2fQn88YmeQjFAEwgXybq6h18H22oYRQamAEwwXFnnakU3buk35JU/YNFmvEf2ZiIZCVE7zWFS7hj
L9qaCR/1wAeVJWfBZG5DhvttMvov/XNGCij2Ac2Ks/gshlxD+uM6htZgQq3PvFdDxbkmP+1d8XWtcpPZ
e0YcwiRu/4Vy5tbfb/5AMQBTiB0SFuW3afOL8K+bd7xhl+D0W2j/yu/QxZZq46SDQOYDDmPWmcMO2rP8
6yJQydQ4KNue3cEhwghUSiJ9/txBfBZCkY9HdtC2hY9p6zeuN33gaoXIymxX15VTgClWH1jOVYm4QrSJ
psdXq+m3canyK+f1pczHDhQDsAD5UhEdBt+9qHU/8OFgY6AMDLGvTtgThndABDOQc8BOUHvwLUEYVuLq
cWDRw2DBI3ylSRYkHc6ahga0YkfVHm4kihDpAdeO4qciFgPZi+eP61Nsswe4E9H+DfECpqXYtDqPm+Y+
QI2etRRLVHoe+b0cDhQDsIDE/bC7kw1y3PjR1GItKvbiMMHXjQrA+rmGB8EIAEQrlq0UZcxM7QGyu/CM
KVS++vt0WWvAkZwz1xCfgYYjaGm2Zf5DyVr7Aw5R7AOeDOw/3oN+vuFBY8yxGDU43+VmsSL0e2AGj71E
jED5O9/nOo48R1be7chCMQAr0L1Y9ALc89pXRXXdARmA5h8uuJ22vvQJOuwtSply+BBrgn3hkGsNbUYx
TStx9YWyVt19VG9/R9ewZCQOr/gM1AiEV2M9Eq3MvCpwd3JzzylUtuJpakuJssvGmsUc19paOIJT9h0w
e7f4HeQx1Nre4n4OPJNiAEmMKwage7nwEYd2LqCiAqiu6Qcj9fDKMlVTyL7ulwkrcTYPLnD14gmuPCsi
6swKXchqtVNo34pn6NKpmrT5coHEtaX3JjU436PiF0FEZqq/NKiiq65gWH292WdYWNvR4CYOy7aS+IU1
c6uv5U9xW3DdRPppxwQUA7AIPXeH62r7ks9oMezGw2Ecouru9iWfphNVu7J8SJJEdTS4mSsJ85rMiIol
2FQqLryLqstfZTcjz5bVtaVCzo3mJftWflvrhCz2x7g2/d5tnCWYVfmq79LVVlHbQJtR9/3wcP0aCsD8
mt2k1kKSRcNRNBWRFZhzuXe5hGIAg4B8ybCgI9+fa+rJg5p2SMRg9xvfc+/i2v8yUixr0F4gym05in4l
otJMVVjxM2FU+wqdb0LDSkwkR3aht6EgDZirLlsyWt7HmlbJgofpMOoaGFqfDQ9iDrgSEcCzk2sVyipF
Aw8YLnctfZKDtBKzKQaQivHMAOAuQmw51+7ne3f6ITGODSC2ZV9gG0Ji17NxaLQ5kMRyomYP7Xj50zq3
YPo6UtYEScZutQV0/ZpIg83FQZYznj/mp1K4LdEC3Wx9Wq8DEGXlmp9SZ3t6C/RsABWK/NtRBBZ7Yebe
1dqNz5xCvq0FzHSBXOzZSEExgCECLadsa37KhG0aHsy2gDs5Nz+8az71XBcqd/Yg3mJ3VztHpMFazgbB
AQ+zONBgFqjRd0rfuDKLB1oSB0J+w3sWsdYBtT59LalDuFFvp22LHuOEoezm1yfngEtxz+v/rBUVNV8X
3mPJwk9wsZdE5+Is7tdIQzGAQUK+bFjPUW4LZbcsaQGocT9zCu1d/lW62Fyln1H3/fBxqr6cdi/7nNbp
2IwBCAs7fte7ZTp1tMvmldlaU3Ke04cquf8AineaRvxpoctgTo71v+E7umG6rAA9AqL7lop6D2YeFK2L
EAy6lWv/JdFCbaxDMYBhAOHB+956hg1Cpu4srVkEClLU2N7islgC2TrVYh7cs5HJJsJroQWY+bNFwFLJ
wsfpeHRXcrYsMAE5x42Oi6xmC6ZkLmVFeu1ttGPJZzhsOZvQPxcbJNEfAa4/C+uClrB5/kN0JLAxrRX7
WIViAEOBtmtoJVZVtoxVeyFB0g+NfnAQzswptH/V91IqBmWD2PRAnPzuV78i8hbMGIDGtJC85Cj6HXW0
tfAcw19T8u+ba/fSjqVPWkqnFtJf7JN38wuc0mucbzhIGiQ7qN6+it+dqTtSC6CCBle++nvsdtVmS5l7
LEIxgOEgHqcLJ8K0R7YSM4vE0/rWb557P5ebGnySkDX03uyi0M55WhETBP0MvCZ535YhwnI1w1mXDH3m
ctyb/kTrC/opx21cy4v309ppt9KuZV+gljqZujz0daQiOQ9qEpavfk7z5JisSxeLUHtwBVdzMs43VqEY
wJAhdg4Vg1AIYiPaV5vdI3ENQHGPGZPYgJiUJMn5hgtJeK1NAW7/tfaFj5tLXW1ta6d9nGxrftJvLwHL
QGkt7VtkLaJJhr4cd3+DC5lC+s+YTIHtc7iPoTahbvKhI+HF6RNxE5vnPiDqKmRYi35NIuV3Mlf8uXSq
Nkk14wCKAQwZYucQQ3660U47ln5WF9zS3wADEFrA1gWP0onoLorFxF1yyMRmgCQ9JApx3sLsu7S6gAMx
Jhz0+2ldwWTaPO8BakDyEqcLy3JZg4T2LJ1XzpFj/a+5ek+ytmH6Z+vXAIYFqzy7SxP7MoQ1ZIDc42tt
J8lR9BvNJpG+jtQ1wVMi6i4EMzQeGetQDCALQI6+a+O/UpHFIhLcPLJgMrmL/y3Rwz5bDIChzYWio/tX
fYfWvfBPpgxArBlawC18z4WBk6caMvHF6bBvvQivtVBXDzUWcBfHPTu692W+o/MsWdsXjWHHY1xJCOsS
7clM9mXOPZzPgSuJKO6SrfXkBxQDyAJwqISq+5hWMcjkUGn+9+2LP0MtdQd0Ui47hyup6vZwbcFiGLq4
epDJumALmDGZNs29j6rLX9NF3lmHPFDIfrR98CMq4vZoVqS/VsL8rW9R64mQcdphQ+4JbBL+bbO47ddA
qr8YWoLVrDvIDYNk1uM3Rh+KAWQJ8Avb3v8R31/NXYKytNUkCu6cRzc6sh9PLudqP1PPiUJc4caECMVA
mutttG/F03RB6yUwWIAhHnK9R9uQWltgIbVWS/dFiDAYVm+PULOzuR/ypCN8F9Kcr2sm70gWeEUeR7bd
kfkCxQCyBBxWtBLbOv8hSyovGk7ibrzn9a9yk045R7Yg54KNAh4HYfC6w1QSJ7SAF++hcOki6uuVvQTM
kNRgrrQ20YHV3xMWdgvMEKW3ECC0f/VziaYaudgL1PuL7H2ZG31YykXgVl+3k33dv7A9Q5stZe6xDsUA
soi2M3VULisGGQ9T2hAWbwQHVZe/kTAu5eLgX2k9ymXAuLmJ2aHXBiRk6etfodbjfv2Muu+NED9DZmId
SqfNvd9aYQ1N+sPF1uBak2iqkYt9aD0RpH0rvsnxESj7lb6W5AADR69HFAhBv4bxCsUAsghYzqvKltKm
OSAgpAqbHzLcexEYdLFZ1A3MxcGHSn4stJW2zn9YtNLOsJaUofm9kS4c3D472UugXyTX3HamnsreekZk
1lmJreca/7ezWxTFTnm2HOwBErhqE/YQc0Mt9gAMs2L1c9SuNVcdT+4/CcUAsgVtJ88dc3MXnvWQMiYM
AIeQCQ3FLhzv5CS5RM6FTreujX8QRkoLYa/s+54xid2biOMX7c36IwLxbwhAqip7hS3nVlyPGPCabJ7/
MB0Ll2iuxyw/v7Y2eDXYFjINcREDr4ul/ww0Vr2XaiqW62onjj8oBpA1iJ3sudlFwZ2zaSPyA8xCTHkI
15ttzc+4VJaYKXsEIN8wiAsNL7YtfFynBQywNq3oJerju4v/SNdl19y0pSX/ofV4iHa/+mWLVX6TlYk4
BDmR7pv2AcNAcq7DnrW0ZcHDzADNGDPHRLzwcdr75tNcJlzMlM115Q8UA8gi5CFprimlXa88ySqk+WGT
dQM/KdqK62bLHsRcqMPv2zqTm3BYMoKxhJ7CDVGaa/b2U0VYfI+8+tDO+ewyM2d84meQsiWLnqDm2v0J
6Z9diLV1Xj4rApKm32JawEXG/cObg/LjiaStLGol+QTFALIIqbpev3qB3MV/4GvAgIeNLeD4ipTcW7nX
HYhUmyx18mFBzIUrxpkjLtrx8pPCRmEWA6+1OQMxONf/ijq1dOEkA0jOe/awg/shcr6/6RUjWSvRu7Ug
UYwku0wviRPRnVzCjTv9moYj359o9dVSf4D/nt9rbpY26lAMIIvQ313RtZZLTBeg662ZFnA/W6aRMXey
Zq+cLDlxViDmQ3w9JBtcXKKOwUAMQBjp8HsIET4W3MpWfp6NiUIyvFbuwCtq/JswFZawohzZzlc+xyG/
bPvgqbL9zEQ3uzvIX1IgWn2Z1fvT6juCUXi3Tuc0ZiC9sej4gWIAWYZkApfPHyXbBz/h2HZzb4CQiDCc
+UtmUW+iVkA2ob3pOFFrc5j7FuKubl4FRxAMDIJojXb5/BExjSYVobrjerBt0SdFh1/d32Qc3JwE3Yqn
UgjVkbSCpDmgfcbZo252ZwrpP8C6tPeA2IWSlz5Jx6M7EnNk0yiZb1AMIMtIuJ36eqne/i67ncyzBAVh
4JDuWZ4MDNJm1H2fHfT1XOdEIZnoYmYVx0B9PrRFa3B9kNACANQP4DwIC5F1Yh4RAVm6/CnutJTUdLL/
nOjWEyldbN0ti+CsabeSc/1vBmg7Pr6gGEAuoO3qheYqKuPAIPMwXOF6mkzFL95L0bKl3Psv+0geZvbX
r/y26CVgqgVgoLnoJCp/+1m61BwVs8W0+IKXHrWUBMXSf8ZkbmISLXtFF2WoI7Is0lvb6XrufWAl64+f
byYqNj1AR3wbE/uvGMAQMZEZgDw0qDmHuvt8NzYthClaia2fcTvtX/UsXW4VqnauEOdEoVUcHGS1GQYM
gsWz76TaA/CN99BlRBiu/Rdec/rvG4f2fAWTmCmiHFcuAQKus71NW+Y/KBirifTHQGg2Oha1a9Waxjvx
A4oB5ATYVbGz5466aRd84xyAY0JkLCGncM88SMj2c4fp8vlj/HUwA/YH8fUwVwpOrikViDuoeO95LYHJ
glsQ6yu4nfaueIaOhbdRdcUbXCPPSo4BJ9bMmExb5j9MdZWrdO3JU4FgoqsXj7OGgqo9xmczG2jweeXC
cTp7zEsVq7/PBkzRLWng9Ynnn0p1aJeWg7DsfIViADlCwiV47QL5d8wRabGm7jGMqXwYSxY+Rvvf/jaV
r3qWyvHV4tj/9rcSf7Pvjaf4OtF55WzKmpJrjHFlY/j5rSQwCUKZyl6L7S9/hkoWPWaNcei0G0TjgUFp
KzB8Rf3AfXTwvR/SvhVfo/JV30l7PtOBv1n1LO1d/hRtnveQhXBkrUjLzMkc+HNBu94Y1zVeoRhArqDt
LHeeqdvPVXctxeHzQKHKO8XVYdBjstbg8g4uBLLtJVFXP21d2v8ijRl9CxNagIkkx+AIvplwq5kXQsVg
6V9wOzOaw+61aW41GUB1ra2ZnEW/oXXT/okJsgjRlGnPZz7E81u1bWjSv/BO1rq6r18Wa5oA0h9QDCCH
kIcIcfgId+W7tpmfPOVgCm1AfB3M0P5m1t207oVbyL7uF4n25Jmk2rHgZtqx5FMckWhmKU8dVp5D/A6i
Ih3rfpXee0BHaOigDCaBQJwNms0h/dnMBv5G/F36WoxD1GgEs9y17It0Di3SEutJ36fxCMUAcoikS7CH
joVKaPO8B4Vkt0Q44oAOfYgKu7A9oNovVH3juhLXlI6L5Nn0b2zlZ8KxoAVYHbKoRsmix3kP+HMzENeV
C0108P2faMSPvzU+z1BG+nqMA+5NxGD4thVy52eB9PWNVygGMEJAK7FEC29L9+ZsDPEZIMCKd59PS7fF
10T+AhpkLv2cVr13MFrAAIMj66ay9AeDkWHOic/X9gbuxFrUEJj3EBcmNQvXzc4QewMD5rZFT3AJ8mQ+
gmIAoF3FALICscPweSOIBoUvLAUGZWmI+IJJHMqLmvbS+i4JXxIjCpuiFDeMlYO5pgw0ONFp+m204+XP
UnPNvsRuGBlA25kG2q8vpJJFDaTfobUfg/qPq0nnZVnxZ2JBMYCcIylNuJXYimdENVpLd9QsDI2YYIRD
wU2ua69jAPo7+JnDDm4XbqVijrUxlYoKbqPgjhd1cfWp0rW3p5ui3F0JhkJr/vqsDA77FZmOMJJmznQc
/1AMYASBvn3Rfa+I2H/TVtTZG8IHP4U/N7J3SaIjkURCC7h+lSL7lrAFHgU6jfMMajBB30a7X/0iZwrq
Piz5PZfpClHpG19LFioZkT0RrcfhMYDd4ZrWDk1AMQDFALIOKW1jXGBiN7ejlum4xsOZi6Hdd2dM5iKk
aImdujY5ZN28p1l1Hw4xwpgIRhLdu4SvF/xJCeIXX1FqLLBrntAULOYkZGOIHAgEJT1EDc73cxR2PTag
GMCIQZOyN66Sf1shp+NyXMCIHfr7tHj9qeTfMVfXdktbnXYSoKXUVqwQ3go2VqbPZT5EVh0SflpTmA1/
UuI7XDm4RDdfiYxz5GqISkRISNr/9rOJsF/j2iYKFAMYMYidBqGhGQgXqJh2i+aGQrjqSIw7uPAI6tw3
15bpJJ+2Nu1r26lajtdng2AaAZkPwTjuotqKNzgfQj63Hl1XW8m96Y8cuLSeKxSN0D4U3s2eDmQIIvAH
GYMTGYoBjCS0zb7R2UbeLTNo67wHOVmlZNEnqGTho7kfiz5BW+fjMx8g//ZZvI6U5WmnAd1vG13v02YU
9xyUy1KE/EL6l638Jl06XSNnTvkKg9up+nLavewLtGXe/VTyUoa15mAgaxFj89x76MDq71LrCaN2MvGg
GMAoAYkrTdEddDS0hY5Ht9Px8Lbcj+h2aopso6bQFu6Q09vdaVxWgglcOX+YKt79AW0YZPQiXJzFc+6h
esd7/SbVgAG0n2ngdmo8Qtr6Ijnch8g2TmBC+nJTeBu1nghzl+CJDsUARhFQwfv6ejhScDSG0SIPSGLF
z4/4N9CWeQ+w6mwk9PRxLxVpVX4PrP4+dwfqF/F42lpGaqCYyXgu8z1YKAagkAHiVHRcOkm2D34qkmss
JArBqIkWZIjpn6h+9bEGxQBGFdj90Rz9QfwMobFQl5FLAOLur5uurGkI6X/wg58Mosa/cT0jORQAxQAU
MiBJIF1XzpJ97S9ZC+i3qq7mV0dvg6bwdl26ryK0fIdiAAoDAlrAyZpS2rbocdFSWyudrZf+MPxBQ3AU
/TbZ10D8te57hXyEYgAKpkBZMbQH49r6hhBmjqoruJ22L/ksndQSfhTGDhQDUDBHPE6nGiq0dGGUDkuq
/mAI8BJ4tkyn7q4r8g8MEyjkKxQDUBgY2gFBjzzfttlcZYg7Gs+5jxkBoup2vfZlOn240viXCmMAigEo
WMaZI27as/wpzttHYVB0Mto4+24K7pqX6GZkDPpRyG8oBqBgDu2UoKhJZO9i0e1o5h3MCFBJ9zxq6SmM
SSgGoGAR4qS0ngxT2cpnac2f/jcbAKvKXuUIO/ErSvqPNSgGoGARmhbQ18Ppwmun3cLVjdq0Dj9K9R+b
UAxAwTIkkV9sjlLlul9SzcG3JnQxjfEAxQAUBg2UFEMhjWTIr8JYhWIACgoTGIoBKChMYIwIA3A6Q22K
ASgo5B8yMQCnM/gYaDcrDMDj8fyt2x265nZHyOuNxPv6UhtDKigojB4kA6irO0I2mydWVdUIBvAZ0O6w
GQCGx+P5D05noCEYrCWnMxDr6kqtSa+goDC6iMViFArVxB2OQDwQqL5eWem9FTRcWFj474x0PSgQEU/g
coX2g7NUVvr6Ll8W5aiV31hBIT+Aa7nbHYp7vVXkdIYuuVyuv9Lol7X4IUMyAIcj4IhGD5Hd7u+7erWD
P1QxAAWF/EBfXx95veG42x0llyt8pby8/P/S6HfYDIDvEC5XcFlt7VGqrPT3nj3byh+qGICCwuhC0mBH
RxeEcywcrieHIxSw2Wx/Pmz1H8BE+OpwBArr6o5RRYWv9+TJ0ykfrqCgMDqQNNjefoW1c2jpTme4AjQr
tfdhQVoR3e7gN6qqDrMNoL5e9qg3rEZBQWFEIRnA6dPnWThDS3c4gm+AZqXwHhYkF7Hbg3cHg7W9lZW+
eDhcp6S/gkIeQJLh0aMnIZyZAbhcwV+BZrPFANiI4PP5/rPLFbggrIzBeHe36siioDDaAAOAMI5GG8AA
YqFQXczpDD0Cmh1WDIAe0AJgUHC5wk5EGeGuoVyBCgr5gZ6eXnK7w3GPJwIPwFWHI/JfNLodngdAQqoS
TmfwNagYuGu0tJzlD1cMQEFhdCBp78qVayz94QFwuQIh0GvWiB+QqoTDEfqqCAby9yHuWCzCsCoFBYUR
gWQAEMY6A+CroNWs3P8ldDkB/93tjnS53WFWOW7enNh92RUURhPi/k9UXS0C9EQOQOgp0GrW7v8SsANg
Uqcz6IMdAFpAW9tlbSFKDVBQGA1ACLtcQb7/ezzhay6X679p9Jq9KwCQtAOE/iAiAn29cD0Aiv4VFEYW
Uui2tl7i2Bwh/QO7QKNZCQAyQk7q8QTv9vurY3a7P+73V5FKDVZQGHlIodvQIMLza2uPQf3/DWg0q/d/
PTJdAy5ebNMWpNQABYWRgaC1Gze6OSYH6r/bHbnqcoVzo/5LSM7icoX+CI4jOI/yBigojCT01n+bzddX
XX2Y7PZgKWgzJ+q/hMwuqqz0/qPPF73hcoW4AEGyQIjiAgoKuQboXxQAqWXrPxiAyxV6FrSZM/VfQroX
nE5/UU2NCAo6cUKUllbXAAWF3EKf/Wez+WKBQE3c5Qo12Wy2/0NT/XOj/ktIBuD1Bh8Lheo5B9nnq+Jw
RAUFhdxCylhR/8/Xh6s4UvVBkzmX/hLJDEG/LRJpiGMhKjRYQSG30If+2my+uNcbjbvdkYs2m+3vZP1O
I63mBJLTuN3Bb9fUHAEH6vP5olyXTEFBITeQshWGd2GAR+hv4B3QoqzcNVJgboN7h8MRakQSAuqRNzef
0RaqtAAFhWxC0hSycFGTw+0Ox7ze6E23O3SLJv1zZ/3PBGkLsNt9n4UtwOUK9blcIbp+vTtlwQoKCsMH
yAk0hWI8iL+BAd5u98/X0+KII+kRCFbKcmGNjU3aghUDUFDIBiQtnTt3gQ4e9MZ9vqqYxxNu93jq/nZE
7/5GQO3AhzudvqmBQG2vxxPps9m88UuXVJKQgkI2ABoCGSHqD1m4sLdB+judgV+ABkdN+kskawX439Ci
A/uCwRrOEVD0r6AwPEghCs0aGrbo+xeKaEU/WAAbaXJEgQWACaATiccTORYI1MZhEExmCiouoKAwFEja
QcYfNGuvN9rn99f2uN2BuzTaG1nDX3/QaQGfAofyeCKoHswL1z+IgoKCNUia6eq6LlX/3vr6Jhj+ZoPW
RizoxyqkH9LhQAchpCYGe7FwPID+gRQUFMwBckG8fyRSz9dqNPxwuYK+UCj0FxC4o676GyGvAkS4DoR9
WDAWjgdAgJCifwUFa5DC8siRE1RR4UHdjZjfX93udAb+l0Zr+aH6G5H0CgT+FxYMd8XBg57YoUPKNaig
YAWSRs6caYXLj9zuaA+Eqc3m+4ZGY6Nr9TeDXCAWjDJFXm+0F75LZRRUUBgYkjbOn7+IOz+u0T319cfJ
4fAvEzSVZ/f+/iAXarf7fopcAbc7DCbABQz0D6qgoCAgaQKJPnZ7AMa+HjTjdblCH+hoKr/u/QNBMgGH
w78S1kunM9wDrgbupn9gBYWJDkkLaPHt9UbZ4g/B6fVGA6FQ6D+iEE/eGf3MoCULaVmD4VV1dWACwV5w
tzNnzqc8uILCRIWkAST5gPjtdr9G/FUBp9P5MdCPrMQ15iA9A/heMgGXK9Rrs3m5m6lxExQUJhL0d34I
Rkh+lPcC8e/eLYg/by3+VpHOBBAjEO4BE4CbQ5YVV0xAYaJAf9ahDeNq7HD4e8Yd8UsYmQAsm253uK+i
wh2vqmrgRAfjxigojEfIMw7BBwEIQehwBNngp1f7xw3xS+iLFng80d+iiAhqCSLBweuN0MWL7WmbpKAw
niDPdWdnF0f4IcgHghBGcr+/+t3t211/pdHK+CJ+HRKagNMZeD4Uqr2G3AHcfex2Px0/3pKIGFRMQGG8
QH+Wcd9HiDwEn99fTTj/LleY/fzAmDX4DQbJOAHP3cFgTQS1zVBR6OBBD18JYBHNtHkKCmMJ+rOLSllI
6UUxTwi8aLSRgsHqS05n6BnQQl6k9o4kJBOA2hMI1Kyurj4CNYjdIDCKNDU1p5QaV4xAYaxAf1bxPcJ6
0b4LUh/NdOAN8/mqXWiwo6eFCQd9NROvt+pbfn/NGa3KcAw1BeAXxeYZN1RBIR9hPJto3oEafsjlRyUf
qPt+f3Wv1xud/fbbb/8Fzv2EJX4JvXFw/37Xf/P5qjdgo0KhOi5/hDwCbCLuTkZGoHiBQj4gnfCvaqW7
fXG7PdALYzcEm99f43M4gvfrzv74v+9bhZ4TBgLVn/f5qmv11wJoBGAEKIzY09OTsuHGF6CgkGsIAZQ8
d7FYnFALM0n4fq6HAcIPBGpa/f6qXxmk/sS571uFXhvYtGnTX/p8Vc/7/dWn4SMNBkUjRJvNE0MTEkQS
Xr3akfJSAOOLUVDIBvo7V9ev3yD0w0CjzspKXwz3fCHxjyK096bPVzXX7a76e90ZV1LfDHrbgNvt/nu/
v3q2z1d1CKXHcT2w2/3xykpfb2WlP15dfYhOnTrHlYcyvSD54vp7gQoKelg5L93dN/lKWl+P6rxBbo0H
4QQhBY+W3x897/NFV7vdgUnyHGtp8krqDwLQBhKMoLS09N9DI/D5qtzYaHBY7XrQB2aANuW4IjQ1tdCl
S+38kvp7gRL4sRpqmAHeKKTpQtJD4MCSD0mP9lyw7kMwIYwXQgrCyuut+a/y3OIMTyj3XrahXQtSqqAE
gzWfCQRq3vd4Iqew+bhnaVGFUMGgGfS5XMF4OFxLhw4d4xeH+xmuDHiZvb29XG9NQQEAE8CZQOm6jo5O
tt6jdgVCdaPRegTusBUfZwsCRxB9I0t7tzt61e+P7vB4qp6DkNKd248WFip1P2uQjEDPTX0+33/2eCLP
BYO174EZ4HqAl4ISSnAh4ooATl1RIZgCXqLHE0b4JeqsxWGwUUONUKiWz4THE4k7nUFW54Ug4REDwSN0
HVqnqHIVvuZ2R3f4fNW/9fmq/x/DOVUSP9fQqqKmaAUu16G/8vmqnnC5QoVOZ7jC7Q5flO4XGBEReRWJ
CMbg8UQRfskNTdVQw+kMaudCEDoECAQJCB7uaJcrcsXjCQW83siyQKDqaxmIHlF8ivBHGjqtIK1Qos0W
/Ru3O3Kv31/9g1Cobq7DESxzOoN2lyt40e0OtTud4S686HC4gQ2Laky8IYnd6QzEXK5gu8cTuuxwBAMe
T6TC54u+6nSGfutwBD7Z2Nj4d8bzBaKHO29CxO6PBciUY9kyyfhziVAo9NdOZ83H7PbA/wgGax93uYJq
TOARjR56vLIyfCsERk1NM6fi9gOucCXu9oro8x56hoCB75VRRsEMMhZFf26Uaj+OoL3gPwMX37SJPooX
rMZEHnyF5Ew8RegKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgrjAP8/QFpdOm5hBz8AAAAASUVORK5C
YII=
)"
}

LogoB64() {
    return "
(Join
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
H32FtG4WPHAWAAAAAElFTkSuQmCC
)"
}

LogoWideB64() {
    return "
(Join
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

FlagB64(c) {
    if (c = "cs")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAABvElEQVR42s2YPUtCURjHz9vV640Sq6U1aKxJF1uajJaKIHAsyIaGgqClEoIa+gD1AQoJitZqCzJqKSP6AmJyFS2v2HX0nKfhQmGYL9fLPT6c+fDjx/P8n8PBkcgs6qViCKG0f/JwbWZhahwhxLmglMiimZ6eIwih3MfX4nZiaf+8YJiUEi4EAMhiIggh1cMGB7TTm1Q4dnx5+0YJwRhzLqQBCQAuxLC/r1iuRuNnywcXBaMqS9Vvu9S48Cos0O87uX4Ox45kqarr315Q1WCg5KpqPOESVTWLHCmqWmSg+6raCmU3VbW7JVxT1dnaaqYKwIHTKVBDVUXDpJQgjB041ra3UZYq1askrp7uXtN76/PRiREKwrq02+eHvRIArMbVoUDOqKZiG2HxbnV4V0SjYzaBKADHuKRowYoez94HTb0sqAMtbQ+IgTCp1wO1zezjaj7lgVqJ+ih1ZtaYTTGmvptJBk29wtQq8VBwLJBYV2IUjYGgjuYQ60YMA+eTmvWImLaA3BTTGshlMc2ApIj5F0iWmAZAcsX8BZIupg4IEP5UtJCp72SSIUli6oAIgq3sw0r+RaKYn8K99h3zDUdy4kUbCE0JAAAAAElFTkSuQmCC"
    if (c = "pl")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAAV0lEQVR42mN0c/NjGEyAhYGBYefOjYPENe7u/kwMgwyMOmjUQaMOGnXQqINGHTTqIBo0P+6K2g4W5xgJjUbZqINGHTTqoFEHjTpo1EEjofmRZSQ0eBwEAHwWBkHb25DwAAAAAElFTkSuQmCC"
    if (c = "de")
        return "iVBORw0KGgoAAAANSUhEUgAAADAAAAAgCAIAAADbtmxLAAAAUUlEQVR42u3YQQ0AIAwEwStBCWL6xAcOUIkDvPBHwRF2FUxyjyaNzC6rrECZvcgsQIAAfQeqkraNZjAZIECAAL1xOtqy4UwmAwQIEKC7cHvHHMs0Bldf+x2dAAAAAElFTkSuQmCC"
    return "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"
}

; ===== TRANSLATIONS (generated by i18n/gen_tables.py - edit the JSON files, not this block) =====
TrCs() {
    m := Map()
    m["Dark mode"] := "Tmavý režim"
    m["All macros"] := "Všechna makra"
    m["Search (name, key or application)"] := "Hledat (název, klávesa nebo aplikace)"
    m["Macro Hub"] := "Macro Hub"
    m["Name"] := "Název"
    m["Key"] := "Klávesa"
    m["Application"] := "Aplikace"
    m["Type"] := "Typ"
    m["Share"] := "Sdílet"
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
    m["Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."] := "Zaškrtnutím makra ho zapneš. Dvojklikem na řádek ho upravíš. Tažením myší přes řádky (nebo Ctrl / Shift+klik) vybereš více maker. Kliknutím na záhlaví sloupce seřadíš seznam. Soubory .ahk přetažené do okna se naimportují; vybraná makra přetažená ze seznamu ven (na plochu, do složky, do chatu) se exportují. Zavřením okna aplikace zůstane běžet v oznamovací oblasti (pravým tlačítkem na ikonu → Ukončit)."
    m["Backup..."] := "Záloha..."
    m["Uninstall"] := "Odinstalovat"
    m["Open window"] := "Otevřít okno"
    m["Check for updates..."] := "Zkontrolovat aktualizace..."
    m["Check for updates at start"] := "Kontrolovat aktualizace při spuštění"
    m["Uninstall..."] := "Odinstalovat..."
    m["Exit"] := "Ukončit"
    m["Delete macro `"{1}`"?"] := "Smazat makro `"{1}`"?"
    m["Delete {1} selected macros?"] := "Smazat vybraná makra ({1})?"
    m["Cancel"] := "Zrušit"
    m["the toggle key of `"{1}`""] := "přepínací klávesa makra „{1}“"
    m["the trigger key of `"{1}`""] := "spouštěcí klávesa makra „{1}“"
    m["The key {1} is already used as {2}."] := "Klávesa {1} už je použitá jako {2}."
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
    m["ComboCrown setup"] := "Instalace ComboCrown"
    m["ComboCrown is already installed"] := "ComboCrown je už nainstalovaný"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Nainstalováno v:`n{1}`n`nAktualizovat ho tímto souborem a spustit, nebo jen spustit nainstalovanou kopii?"
    m["Just start"] := "Jen spustit"
    m["Update and start"] := "Aktualizovat a spustit"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Nainstalovanou kopii se nepodařilo aktualizovat (neběží?). Spouští se nainstalovaná verze.`n`n{1}"
    m["Choose where to install ComboCrown.`nA 'MacroManager' folder will be created there."] := "Vyber, kam se má ComboCrown nainstalovat.`nVytvoří se tam složka 'MacroManager'."
    m["Installation failed:`n{1}"] := "Instalace se nezdařila:`n{1}"
    m["Create a Start Menu shortcut?"] := "Vytvořit zástupce v nabídce Start?"
    m["Skip"] := "Přeskočit"
    m["Create"] := "Vytvořit"
    m["Create a Desktop shortcut?"] := "Vytvořit zástupce na ploše?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Nainstalováno do:`n{1}`n`nTvoje makra a nastavení jsou uložena v:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "Tohle nevypadá jako nainstalovaná kopie, nic se neodstranilo."
    m["Uninstall ComboCrown"] := "Odinstalovat ComboCrown"
    m["Uninstall ComboCrown?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "Odinstalovat ComboCrown?`n`nTím se trvale smaže celá složka včetně všech maker a nastavení:`n{1}"
    m["Save a backup of your macros, profiles and settings before uninstalling? After a reinstall you can restore it with Backup... > Restore..."] := "Uložit před odinstalací zálohu maker, profilů a nastavení? Po nové instalaci ji obnovíš přes Záloha... > Obnovit..."
    m["Don't save"] := "Neukládat"
    m["Create backup..."] := "Vytvořit zálohu..."
    m["Create backup"] := "Vytvořit zálohu"
    m["ComboCrown backup (*.mmbackup)"] := "Záloha ComboCrown (*.mmbackup)"
    m["The backup could not be saved:`n{1}"] := "Zálohu se nepodařilo uložit:`n{1}"
    m["Backup saved to:`n{1}"] := "Záloha uložena do:`n{1}"
    m["ComboCrown has been uninstalled.`nThe folder will be removed in a moment."] := "ComboCrown byl odinstalován.`nSložka bude za chvilku odstraněna."
    m["New macro"] := "Nové makro"
    m["Edit macro"] := "Upravit makro"
    m["Profiles"] := "Profily"
    m["Trigger key"] := "Spouštěcí klávesa"
    m["Toggle"] := "Přepínač"
    m["Only in app (exe)"] := "Jen v aplikaci (exe)"
    m["Select"] := "Vybrat"
    m["Press"] := "Stisk"
    m["Normal"] := "Normální"
    m["Short tap"] := "Krátký stisk"
    m["Double tap"] := "Dvojitý stisk"
    m["Long press"] := "Dlouhý stisk"
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
    m["The toggle key {1} is already used as {2}."] := "Přepínací klávesa {1} už je použitá jako {2}."
    m["Paste or write a script first."] := "Nejdřív vlož nebo napiš skript."
    m["Enter a trigger key."] := "Zadej spouštěcí klávesu."
    m["The toggle key can't be the same as the trigger key."] := "Přepínací klávesa nemůže být stejná jako spouštěcí klávesa."
    m["The trigger key {1} is already used as {2}."] := "Spouštěcí klávesa {1} už je použitá jako {2}."
    m["Same trigger key as `"{1}`" - only one of them works"] := "Stejná spouštěcí klávesa jako „{1}“ – funguje jen jedno z nich"
    m["Exact delays"] := "Přesné prodlevy"
    m["Save"] := "Uložit"
    m["tap"] := "krátce"
    m["hold"] := "držet"
    m["Saving the settings failed: {1}"] := "Uložení nastavení se nezdařilo: {1}"
    m["the All macros toggle key"] := "přepínač všech maker"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makro `"{1}`" nelze zapnout (klávesa `"{2}`"):`n{3}"
    m["The key {1} is used twice - as {2} and as {3}. Only one of them works."] := "Klávesa {1} je použitá dvakrát - jako {2} a jako {3}. Funguje jen jedno z nich."
    m["Same trigger key"] := "Stejná spouštěcí klávesa"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}“ používá stejnou spouštěcí klávesu ({2}) jako aktivní makro „{3}“. Fungovat bude jen jedno z nich."
    m["Turn on anyway"] := "Přesto zapnout"
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
    m["ComboCrown update"] := "Aktualizace ComboCrown"
    m["Version {1} is available (you have v{2})."] := "Je dostupná verze {1} (máš v{2})."
    m["Later"] := "Později"
    m["Update now"] := "Aktualizovat"
    m["The download failed. Try again later."] := "Stahování se nezdařilo. Zkus to znovu později."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Stažený soubor neodpovídá očekávanému kontrolnímu součtu (nová verze se možná ještě nahrává). Nic se nezměnilo - zkus to znovu za pár minut.`n`nOčekáváno: {1}...`nPřijato: {2}  ({3} bajtů)"
    m["(could not compute)"] := "(nelze vypočítat)"
    m["The downloaded file is not a valid ComboCrown script. Nothing was changed."] := "Stažený soubor není platný skript aplikace ComboCrown. Nic se nezměnilo."
    m["Could not replace the app file: {1}"] := "Nepodařilo se nahradit soubor aplikace: {1}"
    m["Version {1}"] := "Verze {1}"
    m["hlp_start"] := "ComboCrown za tebe spouští makra na klávesové zkratky. Každé makro má spouštěcí klávesu; dokud ji držíš (ve vybrané aplikaci), makro se přehrává.`n`n- Zaškrtnutím makra v seznamu ho zapneš, odškrtnutím vypneš.`n- Přepínač Všechna makra v horní liště zapne nebo vypne všechna makra najednou.`n- Tmavý režim přepíná vzhled aplikace.`n- Tlačítko jazyka v horní liště přepíná jazyk aplikace (English, Čeština, Polski, Deutsch). Aplikace se kvůli tomu restartuje.`n- Dvojklikem na řádek (nebo tlačítkem Upravit) makro změníš. Přidat vytvoří nové, Kopírovat ho zduplikuje, Smazat ho odstraní.`n- Chceš-li vybrat více maker, táhni myší přes řádky (nebo Ctrl / Shift + klik). Kopírovat, Smazat, Exportovat, Nahoru / Dolů i přetažení ven z okna fungují na všech vybraných řádcích.`n- Zavřením okna aplikace zůstane běžet v oznamovací oblasti. Po kliknutí pravým tlačítkem na ikonu v oznamovací oblasti najdeš Otevřít okno / Odinstalovat / Ukončit.`n- Aplikace vždy běží jako správce, takže makra fungují i ve hrách spuštěných se zvýšenými oprávněními.`n- Pole pro hledání nad seznamem zobrazí jen makra, jejichž název, klávesa nebo aplikace obsahuje zadaný text. Křížek vedle něj hledání zruší."
    m["hlp_edit"] := "Název - libovolný text, zobrazuje se v seznamu.`nProfily - do kterých profilů makro patří (může jich být víc).`nSpouštěcí klávesa - klikni do pole a stiskni klávesu nebo tlačítko myši (pravé, prostřední, boční tlačítka X1 / X2, kolečko myši). Pro kombinaci při stisku drž Ctrl / Shift / Alt, například Ctrl+XButton1. Esc zruší výběr.`nPřepínač - volitelná klávesa, která toto makro zapíná/vypíná bez otevření okna. Backspace ji smaže.`nJen v aplikaci (exe) - makro funguje, jen když je daný program v popředí. Tlačítkem Vybrat vybereš spuštěnou aplikaci nebo najdeš soubor .exe. Prázdné = funguje všude.`nTyp - Pohyb + akce, Sekvence nebo Skript (.ahk). Viz další témata.`nStisk - jak se má spouštěcí klávesa stisknout. Normální: makro začne, jakmile klávesu stiskneš. Krátký stisk: rychle stiskni a pusť - makro se přehraje jednou po puštění. Dvojitý stisk: stiskni klávesu dvakrát rychle za sebou. Dlouhý stisk: chvíli klávesu podrž (s Opakováním hraje, dokud ji držíš). Jedna klávesa tak může mít až tři makra: krátký, dvojitý a dlouhý stisk. Normální makro na stejné klávese si vezme celou klávesu. Makra na kolečku myši se spouští vždy hned.`nSpouštění - Jednou na stisk klávesy: přehraje jeden průchod a čeká, dokud klávesu nepustíš. Opakovat při držení klávesy: přehrává dokola, dokud klávesu nepustíš (zastaví se okamžitě). U Krátkého stisku se nenabízí - přehraje se vždy jednou.`nPřesné prodlevy (vlevo dole) - prodlevy se dodrží zhruba na milisekundu. U nových maker zapnuté. Vypnuté = dřívější časování, kdy krátké prodlevy často trvají o 10-15 ms déle, než je zapsáno.`n`nUložit makro uloží, Zrušit zahodí změny."
    m["hlp_move"] := "Určeno pro hry, kde se neustále pohybuješ (například A a D) a mezitím sesíláš kouzla.`n`nSměry - pohybové klávesy v pořadí, například: a,d`nAkce v pořadí - klávesy ke stisknutí, jedna na cyklus, například: 1,2,1,F7,1,F8`n`nKaždý cyklus proběhne takto, s prodlevami, které nastavíš:`n  1. směr dolů`n  2. (prodleva 1) akce dolů`n  3. (prodleva 2) směr nahoru`n  4. (prodleva 3) akce nahoru`n  5. (prodleva 4) pauza, pak další směr + další akce`n`nSeznamy se po dojetí na konec opakují od začátku. Pokud jsou Směry prázdné, mačkají se jen akce: doba držení = prodleva 2, pauza = prodleva 4.`nPokud hra makro ignoruje, zvyš prodlevy (běžně se používá 20-30 ms)."
    m["hlp_seq"] := "Volný seznam kroků. Piš jeden krok na řádek:`n`n  down KEY PAUSE   - stiskne a drží klávesu`n  up KEY PAUSE     - pustí klávesu`n  tap KEY PAUSE    - stiskne a hned pustí`n`nPAUSE je čekání po kroku v milisekundách (prázdné = 0).`n`nPříklad - rychlé střídání A / D:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nPříklad - útok a kouzla:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nPříklad - dvě klávesy najednou:`n  tap Shift+4 50`n`nPři Spouštění = Opakovat se řádky přehrávají ve smyčce, dokud držíš spouštěcí klávesu; při Jednou se přehrají jen jednou.`nKlávesy, které jsou při puštění spouštěcí klávesy stále stisknuté, se uvolní automaticky."
    m["hlp_script"] := "Pro všechno, co ostatní typy neumí. Vlož nebo napiš vlastní skript AutoHotkey v2.`n`n- Skript běží jako samostatný proces, dokud je makro zaškrtnuté, a po odškrtnutí se zastaví.`n- Musí to být kód AutoHotkey v2 (skripty pro v1 nebudou fungovat).`n- Spouštěcí klávesa a filtr aplikace se nepoužívají, to si řeší tvůj skript sám.`n- Importované soubory .ahk, které nevytvořil ComboCrown, se stanou skriptovými makry.`n- Importovaný skript se před prvním spuštěním zeptá: běží s právy správce, takže ho zapni, jen pokud věříš, odkud pochází. Okno ukáže, co skript dělá (například spouští programy nebo maže soubory), a nabídne zobrazení kódu."
    m["hlp_keys"] := "Názvy kláves odpovídají názvům v AutoHotkey: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nKlávesu lze zapsat i jako scan kód, například sc002 - jde o fyzickou klávesu bez ohledu na rozložení. Klávesy jako čárka, plus, & a | se takto ukládají automaticky.`n`nMyš: spouštěcí klávesa, přepínač i klávesa Všechna makra může být také tlačítko myši: RButton, MButton (klik kolečkem), XButton1 / XButton2 (dvě boční tlačítka) nebo samotné kolečko (WheelUp / WheelDown / WheelLeft / WheelRight). Kolečko nelze držet, proto se makra na kolečku vždy přehrají jednou. Levé tlačítko se nenabízí.`nHerní / MMO myši: Windows zná jen pět tlačítek myši, další boční tlačítka obsluhuje software myši (G HUB, Synapse, iCUE, ...). Nastav jim tam klávesy, nejlépe F13 - F24 (nebo Ctrl+Alt+číslo); ComboCrown je pak vidí jako obyčejné klávesy, takže klikni do pole spouštěcí klávesy a stiskni boční tlačítko.`n`nNahrát (vedle Směrů a Akcí): stiskni Nahrát, mačkej klávesy v požadovaném pořadí a pak stiskni Hotovo. Pole se plní průběžně. Během nahrávání jsou makra pozastavená.`n`nKlávesy současně: klávesy, které držíš zároveň, se uloží jako jeden krok spojený pomocí +, například Shift+4. Při přehrávání se všechny stisknou společně a společně se i uvolní (ne nejdřív Shift a pak 4).`nStejně to funguje i při psaní do polí: a,Shift+4,d"
    m["hlp_profiles"] := "Profily udržují různé sady maker odděleně (například jeden na hru).`n`n- Tlačítko profilu v horní liště ukazuje aktuální profil. Kliknutím přepneš profil nebo vytvoříš / přejmenuješ / smažeš profil.`n- Seznam ukazuje jen makra aktuálního profilu a jen ta jsou aktivní.`n- V editoru můžeš v Profily vybrat pro makro jeden nebo více profilů. Když změníš makro, které patří do více profilů, aplikace se zeptá: použít změnu ve všech, nebo jen v aktuálním profilu (ostatní profily si ponechají starou verzi).`n- Zaškrtnutí makra je ve všech profilech stejné; přepnutím profilu se jen mění, která makra jsou ve hře.`n- Smazáním profilu se makra, která patřila jen jemu, přesunou do prvního zbývajícího profilu."
    m["hlp_toggle"] := "Přepínač (v editoru) - klávesa, která zapíná / vypíná jedno konkrétní makro, stejně jako jeho zaškrtnutí v seznamu. Malý tooltip ukáže ZAP / VYP.`nPřepínač všech maker (tlačítko pod seznamem) - přepíná hlavní vypínač. Funguje ve všech profilech.`n`nKlikni na tlačítko a stiskni klávesu. Esc zruší, Backspace klávesu odstraní.`nMakra z jiných profilů na své přepínací klávesy nereagují."
    m["hlp_order"] := "Nahoru / Dolů mění pořadí v seznamu. Kliknutím na záhlaví sloupce se seznam seřadí (dalším kliknutím se pořadí obrátí).`n`nExportovat... uloží vybrané makro jako samostatný soubor .ahk pro AutoHotkey v2, který běží i sám (požádá o práva správce).`nImportovat... načte jeden nebo více souborů .ahk (nebo je stačí přetáhnout do hlavního okna). Makro můžeš také přetáhnout ze seznamu na plochu / do složky / do okna chatu a exportovat ho tak jako soubor .ahk. Makro se pojmenuje podle souboru; soubory vytvořené aplikací ComboCrown se vrátí jako upravitelná makra, ostatní skripty se stanou skriptovými makry. Importy jdou do aktuálního profilu a začínají vypnuté.`nExportovat vše... zapíše všechna makra do složky, každé do jednoho souboru.`n`nZáloha... (vedle Odinstalovat) uloží všechno – makra, profily, nastavení i soubory skriptů – do jednoho souboru .mmbackup a obnoví ho na novém PC nebo po přeinstalaci. Soubor zálohy můžeš také přetáhnout do okna. Před obnovou se současný stav uloží jako config\backup-before-restore.mmbackup.`n`nOdinstalovat smaže celou složku aplikace včetně všech maker a nastavení. Nejdřív nabídne export všech maker."
    m["hlp_updates"] := "Ikona šipky v horní liště (vedle tlačítka profilu) ukazuje, jestli existuje nová verze: šedá = máš aktuální verzi, zelená = je dostupná nová verze. Po najetí myší uvidíš podrobnosti.`n`nAplikace kontroluje několik sekund po spuštění (lze vypnout v nabídce v oznamovací oblasti: Kontrolovat aktualizace při spuštění). Kliknutím na ikonu můžeš kdykoli zkontrolovat znovu. Nic se nenainstaluje, dokud neklikneš na zelenou ikonu a nepotvrdíš.`n`nPři aktualizaci aplikace stáhne nový soubor, zkontroluje jeho kontrolní součet, starý ponechá jako Macro Manager.ahk.bak a restartuje se. Tvoje makra, profily a nastavení jsou uložené zvlášť ve složce config a zůstanou přesně tak, jak jsou.`n`nKdyž se něco pokazí, zavři aplikaci, smaž Macro Manager.ahk a přejmenuj Macro Manager.ahk.bak zpět na Macro Manager.ahk.`n`nAktualizace potřebuje přístup k internetu (server Macro Hubu nebo github.com)."
    m["hlp_hub"] := "Macro Hub (tlačítko vedle hledání) ukazuje makra, která sdílejí hráči. Otevře se jako panel po straně hlavního okna.`n`n- Makra hráčů: makra ostatních hráčů. Moje makra: makra, která jsi sdílel, s jejich hodnocením a počtem stažení.`n- Hledej slovy z názvu, hry nebo jména autora: musí sedět každé slovo. 4story najde všechna makra pro 4Story, 4story war jen ta pro warriora.`n- Tlačítko hry vyfiltruje jednu hru, tlačítko řazení řadí podle hodnocení, nejnovějších nebo nejstahovanějších.`n- U každého makra je průměrné hodnocení ve hvězdičkách (1 = nejhorší, 5 = nejlepší) s počtem hodnocení v závorce, autor, hra, spouštěcí klávesa a počet stažení. Zlatá fajfka označuje makra zkontrolovaná moderátorem - jsou na začátku.`n- Pole pod seznamem ukazuje popis a co makro dělá (klávesy, prodlevy, sekvenci) - ještě před stažením.`n- Stáhnout (nebo dvojklik) přidá makro do aktuálního profilu jako vypnuté. Zkontroluj klávesu a aplikaci a pak ho zaškrtni.`n- Hodnotit dá 1 až 5 hvězdiček - jedno hodnocení na instalaci, později ho můžeš změnit. Vlastní makra hodnotit nejde.`n- Nahlásit pošle makro ke kontrole, třeba farm / AFK makro, které není povolené. Po několika nahlášeních se makro schová.`n- Smazat (Moje makra) odstraní z Macro Hubu makro, které jsi sdílel; tvoje kopie v seznamu zůstane.`n`nSdílení: klikni na ikonu sdílení na konci řádku v hlavním seznamu a vyplň název, hru, popis a přezdívku. Po sdílení ikona zezlátne. Makra stažená z Macro Hubu mají místo ní šipku stažení a sdílet je jde až po úpravě.`n`nAktualizace: když upravíš makro, které jsi sdílel, aplikace se zeptá, jestli ho aktualizovat v Macro Hubu - hodnocení i počet stažení zůstanou (do té doby má jeho ikona tečku; kliknutím ho aktualizuješ). Když autor aktualizuje makro, které sis stáhl, objeví se upozornění a jeho šipka v seznamu zezelená: klikni na ni, uvidíš, co se změnilo, a převezmeš novou verzi nebo si necháš svou. Sdílí se: klávesy, prodlevy, nastavení Spouštění a Stisku a aplikace. Nesdílí se: přepínací klávesa a tvoje profily. Skript makra sdílet nejde.`n`nMacro Hub potřebuje připojení k internetu. Kdo makro hodnotil nebo nahlásil, nikdo neuvidí. Aby aplikace poznala makra stažená starší verzí, pošle Macro Hubu jednou, co dělají (klávesy, prodlevy, sekvenci - ne jejich názvy); nic z toho se neukládá."
    m["hlp_tips"] := "- Hra nic nedělá: zkus zvýšit prodlevy, ověř, že Jen v aplikaci (exe) odpovídá hře (použij Vybrat), a nech aplikaci běžet jako správce.`n- Postava běží jedním směrem: ve Směrech drž dvojice směrů (a,d) a prodlevu mezi cykly nastav malou, ale ne 0.`n- Makro se nespustí: zkontroluj, že je zaškrtnuté, Všechna makra je zapnuté, makro je v aktuálním profilu a spouštěcí klávesa je nastavená (není nedefinovaná).`n- Dvě makra se stejnou spouštěcí klávesou: funguje jen jedno z nich - použij různé klávesy, různé profily nebo různý Stisk (krátký / dvojitý / dlouhý).`n- Makra vytvořená před zavedením Přesných prodlev si nechávají dřívější časování. Když jim Přesné prodlevy zapneš, můžou hrát rychleji - pak jim prodlevy trochu zvyš.`n- Zaseknutá klávesa po přerušení: jednou ji stiskni a pusť; aplikace při zastavení makra uvolní klávesy, které stiskla.`n- Nastavení a skripty jsou ve složce config vedle aplikace."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Discord se nepodařilo otevřít. Odkaz je zkopírovaný do schránky - vlož ho do prohlížeče:`n`n{1}"
    m["Help"] := "Nápověda"
    m["Join Discord"] := "Přidej se na Discord"
    m["Close"] := "Zavřít"
    m["Set a trigger key first: {1}"] := "Nejdřív nastav spouštěcí klávesu: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Přetažení makra ven se nezdařilo:`n{1}"
    m["Backup"] := "Záloha"
    m["Backup and restore"] := "Záloha a obnova"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Ulož všechna makra, profily a nastavení (včetně souborů skriptů) do jednoho souboru zálohy – pro nový počítač nebo přeinstalaci. Nebo je z takového souboru obnov."
    m["Restore..."] := "Obnovit..."
    m["Restore from backup"] := "Obnovit ze zálohy"
    m["This is not a ComboCrown backup file:`n{1}"] := "Tohle není soubor zálohy aplikace ComboCrown:`n{1}"
    m["Restore this backup?"] := "Obnovit tuto zálohu?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Všechna současná makra, profily a nastavení se nahradí zálohou z {1} ({2} maker). Aplikace se restartuje.`n`nSoučasný stav se nejdřív uloží jako:`n{3}"
    m["Restore"] := "Obnovit"
    m["The backup could not be restored:`n{1}"] := "Zálohu se nepodařilo obnovit:`n{1}"
    m["Can't reach Macro Hub. Check your internet connection and try again."] := "Macro Hub není dostupný. Zkontroluj připojení k internetu a zkus to znovu."
    m["You have shared a lot of macros today. Please try again tomorrow."] := "Dnes jsi sdílel už hodně maker. Zkus to prosím zítra."
    m["You can't rate your own macro."] := "Vlastní makro hodnotit nemůžeš."
    m["This macro is no longer in Macro Hub."] := "Toto makro už v Macro Hubu není."
    m["Only the author can delete this macro."] := "Toto makro může smazat jen jeho autor."
    m["Please check the name, game, description and nickname."] := "Zkontroluj prosím název, hru, popis a přezdívku."
    m["Macro Hub could not do this ({1})."] := "Macro Hub to nemohl provést ({1})."
    m["Players' macros"] := "Makra hráčů"
    m["My macros"] := "Moje makra"
    m["Search: name, game or author"] := "Hledat: název, hra nebo autor"
    m["No connection"] := "Bez připojení"
    m["Macro Hub needs the internet. It tries again by itself every few seconds."] := "Macro Hub potřebuje internet. Každých pár sekund to zkouší znovu sám."
    m["Try again"] := "Zkusit znovu"
    m["Load more"] := "Načíst další"
    m["Download"] := "Stáhnout"
    m["Rate"] := "Hodnotit"
    m["Report"] := "Nahlásit"
    m["All games"] := "Všechny hry"
    m["Game: {1}"] := "Hra: {1}"
    m["Newest"] := "Nejnovější"
    m["Most downloaded"] := "Nejstahovanější"
    m["Top rated"] := "Nejlépe hodnocené"
    m["Loading..."] := "Načítám..."
    m["You have not shared any macro yet - use the share icon in your list."] := "Zatím jsi nesdílel žádné makro - použij ikonu sdílení ve svém seznamu."
    m["Macro Hub is empty so far - share the first macro!"] := "Macro Hub je zatím prázdný - nasdílej první makro!"
    m["No macros found."] := "Žádná makra nenalezena."
    m["Pick a macro to see its description."] := "Vyber makro a uvidíš jeho popis."
    m["(no description)"] := "(bez popisu)"
    m["What it does:"] := "Co dělá:"
    m["your macro"] := "tvoje makro"
    m["by {1}"] := "od {1}"
    m["updated {1}"] := "aktualizováno {1}"
    m["verified"] := "ověřeno"
    m["hidden after reports"] := "schované po nahlášení"
    m["your rating: {1}"] := "tvé hodnocení: {1}"
    m["`"{1}`" added to profile {2} - switched off, tick it to turn it on."] := "`"{1}`" přidáno do profilu {2} - je vypnuté, zapneš ho zaškrtnutím."
    m["Downloaded macro"] := "Stažené makro"
    m["This macro already has several ratings from your internet connection, so another one is not counted."] := "Toto makro už má z tvého internetového připojení několik hodnocení, další se proto nezapočítá."
    m["Thank you for rating!"] := "Díky za hodnocení!"
    m["Report macro"] := "Nahlásit makro"
    m["Why should `"{1}`" be removed from Macro Hub? For example: a farm / AFK macro (not allowed), it does not work, or spam."] := "Proč by mělo být `"{1}`" odstraněno z Macro Hubu? Například: farm / AFK makro (není povolené), nefunguje, nebo spam."
    m["Thank you. The macro will be checked."] := "Děkujeme. Makro zkontrolujeme."
    m["Delete from Macro Hub?"] := "Smazat z Macro Hubu?"
    m["`"{1}`" will be removed from Macro Hub for everyone, with its ratings. Your own copy in the list stays."] := "`"{1}`" zmizí z Macro Hubu pro všechny, i s hodnocením. Tvoje vlastní kopie v seznamu zůstane."
    m["Script macros can't be shared - only Move + actions and Sequence macros."] := "Skript makra sdílet nejde - jen makra Pohyb + akce a Sekvence."
    m["`"{1}`" comes from Macro Hub (author: {2}), so it can't be shared again as it is. Change it first - for example a delay or a key - and then share your own version."] := "`"{1}`" pochází z Macro Hubu (autor: {2}), proto ho nejde znovu sdílet tak, jak je. Nejdřív ho uprav - třeba prodlevu nebo klávesu - a pak nasdílej svou verzi."
    m["Share macro"] := "Sdílet makro"
    m["`"{1}`" is in Macro Hub and up to date. When you change it, you can update it there."] := "`"{1}`" je v Macro Hubu a je aktuální. Když ho upravíš, můžeš ho tam aktualizovat."
    m["No connection to Macro Hub. Sharing needs the internet - try again when you are online."] := "Macro Hub není dostupný. Sdílení potřebuje internet - zkus to znovu, až budeš online."
    m["You have already shared this macro as `"{1}`". Change it to share a new version."] := "Toto makro už jsi sdílel jako `"{1}`". Pro novou verzi ho nejdřív uprav."
    m["This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version."] := "Toto makro už v Macro Hubu je jako `"{1}`" od {2}. Nejdřív ho uprav - třeba prodlevu nebo klávesu - a pak nasdílej svou verzi."
    m["Thank you for sharing! `"{1}`" is now in Macro Hub."] := "Díky za sdílení! `"{1}`" je teď v Macro Hubu."
    m["Update in Macro Hub?"] := "Aktualizovat v Macro Hubu?"
    m["`"{1}`" is shared in Macro Hub. Update it there with your changes? Its ratings and downloads stay, and Macro Hub shows it as updated. Players who downloaded it get a notice."] := "`"{1}`" je sdílené v Macro Hubu. Aktualizovat ho tam tvými změnami? Hodnocení i počet stažení zůstanou a Macro Hub ho ukáže jako aktualizované. Hráči, kteří si ho stáhli, dostanou upozornění."
    m["Not now"] := "Teď ne"
    m["Update"] := "Aktualizovat"
    m["You updated this macro a moment ago. The app sends this change by itself in a few minutes."] := "Toto makro jsi aktualizoval před chvílí. Aplikace tuto změnu odešle sama za pár minut."
    m["No connection to Macro Hub. Your change is kept - the app sends the update by itself as soon as you are online again."] := "Macro Hub není dostupný. Tvoje změna zůstává uložená - aplikace aktualizaci odešle sama, jakmile budeš zase online."
    m["`"{1}`" is no longer in Macro Hub. Share it again with the share icon."] := "`"{1}`" už v Macro Hubu není. Nasdílej ho znovu ikonou sdílení."
    m["`"{1}`" is updated in Macro Hub."] := "`"{1}`" je v Macro Hubu aktualizované."
    m["`"{1}`" has a new version in Macro Hub. Click its green arrow in the list to see the changes."] := "`"{1}`" má v Macro Hubu novou verzi. Klikni na jeho zelenou šipku v seznamu a uvidíš změny."
    m["{1} downloaded macros have a new version in Macro Hub. Click their green arrows in the list to see the changes."] := "{1} stažených maker má v Macro Hubu novou verzi. Klikni na jejich zelené šipky v seznamu a uvidíš změny."
    m["New version of `"{1}`" by {2}"] := "Nová verze `"{1}`" od {2}"
    m["You changed this macro yourself - updating replaces your changes with the new version."] := "Toto makro jsi sám upravil - aktualizace nahradí tvé změny novou verzí."
    m["Changes (yours → new):"] := "Změny (tvoje → nové):"
    m["Keep mine"] := "Nechat moje"
    m["`"{1}`" is updated to the new version."] := "`"{1}`" je aktualizované na novou verzi."
    m["(no difference)"] := "(žádný rozdíl)"
    m["Share `"{1}`" in Macro Hub"] := "Sdílet `"{1}`" v Macro Hubu"
    m["Game (people filter and search by it, for example 4Story)"] := "Hra (podle ní se filtruje a hledá, např. 4Story)"
    m["Description (optional): what it does, for which class"] := "Popis (nepovinný): co dělá, pro jakou třídu"
    m["Your nickname"] := "Tvoje přezdívka"
    m["Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."] := "Sdílí se: klávesy, prodlevy, nastavení Spouštění a Stisku a aplikace. Nesdílí se: přepínací klávesa a tvoje profily. Každý ho uvidí a může si ho stáhnout. Farm / AFK makra nejsou povolená."
    m["Please fill in the name, the game and your nickname."] := "Vyplň prosím název, hru a svou přezdívku."
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
    m["Macro Hub"] := "Macro Hub"
    m["Name"] := "Nazwa"
    m["Key"] := "Klawisz"
    m["Application"] := "Aplikacja"
    m["Type"] := "Typ"
    m["Share"] := "Udostępnij"
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
    m["Tick a macro to turn it on. Double-click a row to edit. Drag over rows (or Ctrl / Shift+click) to select several. Click a column header to sort. Drop .ahk files onto the window to import them; drag selected macros out of the list (desktop, folder, chat) to export them. Closing the window keeps it running in the tray (right-click the icon → Exit)."] := "Zaznacz makro, aby je włączyć. Kliknij dwukrotnie wiersz, aby edytować. Przeciągnij myszą po wierszach (lub Ctrl / Shift+kliknięcie), aby zaznaczyć kilka. Kliknij nagłówek kolumny, aby posortować. Upuść pliki .ahk na okno, aby je zaimportować; przeciągnij zaznaczone makra z listy (na pulpit, do folderu, na czat), aby je wyeksportować. Zamknięcie okna zostawia aplikację w zasobniku systemowym (kliknij ikonę prawym przyciskiem → Zakończ)."
    m["Backup..."] := "Kopia..."
    m["Uninstall"] := "Odinstaluj"
    m["Open window"] := "Otwórz okno"
    m["Check for updates..."] := "Sprawdź aktualizacje..."
    m["Check for updates at start"] := "Sprawdzaj aktualizacje przy starcie"
    m["Uninstall..."] := "Odinstaluj..."
    m["Exit"] := "Zakończ"
    m["Delete macro `"{1}`"?"] := "Usunąć makro `"{1}`"?"
    m["Delete {1} selected macros?"] := "Usunąć zaznaczone makra ({1})?"
    m["Cancel"] := "Anuluj"
    m["the toggle key of `"{1}`""] := "klawisz przełącznika makra „{1}”"
    m["the trigger key of `"{1}`""] := "klawisz wyzwalający makra „{1}”"
    m["The key {1} is already used as {2}."] := "Klawisz {1} jest już używany jako {2}."
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
    m["ComboCrown setup"] := "Instalator ComboCrown"
    m["ComboCrown is already installed"] := "ComboCrown jest już zainstalowany"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Zainstalowano w:`n{1}`n`nZaktualizować go tym plikiem i uruchomić, czy tylko uruchomić zainstalowaną kopię?"
    m["Just start"] := "Tylko uruchom"
    m["Update and start"] := "Zaktualizuj i uruchom"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Nie udało się zaktualizować zainstalowanej kopii (czy jest uruchomiona?). Uruchamiam zainstalowaną wersję.`n`n{1}"
    m["Choose where to install ComboCrown.`nA 'MacroManager' folder will be created there."] := "Wybierz, gdzie zainstalować ComboCrown.`nZostanie tam utworzony folder 'MacroManager'."
    m["Installation failed:`n{1}"] := "Instalacja nie powiodła się:`n{1}"
    m["Create a Start Menu shortcut?"] := "Utworzyć skrót w menu Start?"
    m["Skip"] := "Pomiń"
    m["Create"] := "Utwórz"
    m["Create a Desktop shortcut?"] := "Utworzyć skrót na pulpicie?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Zainstalowano w:`n{1}`n`nTwoje makra i ustawienia są przechowywane w:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "To nie wygląda na zainstalowaną kopię, nic nie zostało usunięte."
    m["Uninstall ComboCrown"] := "Odinstaluj ComboCrown"
    m["Uninstall ComboCrown?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "Odinstalować ComboCrown?`n`nTo trwale usunie cały folder, razem ze wszystkimi makrami i ustawieniami:`n{1}"
    m["Save a backup of your macros, profiles and settings before uninstalling? After a reinstall you can restore it with Backup... > Restore..."] := "Zapisać przed odinstalowaniem kopię zapasową makr, profili i ustawień? Po ponownej instalacji przywrócisz ją przez Kopia... > Przywróć..."
    m["Don't save"] := "Nie zapisuj"
    m["Create backup..."] := "Utwórz kopię..."
    m["Create backup"] := "Utwórz kopię zapasową"
    m["ComboCrown backup (*.mmbackup)"] := "Kopia ComboCrown (*.mmbackup)"
    m["The backup could not be saved:`n{1}"] := "Nie udało się zapisać kopii:`n{1}"
    m["Backup saved to:`n{1}"] := "Kopię zapisano w:`n{1}"
    m["ComboCrown has been uninstalled.`nThe folder will be removed in a moment."] := "ComboCrown został odinstalowany.`nFolder zostanie za chwilę usunięty."
    m["New macro"] := "Nowe makro"
    m["Edit macro"] := "Edytuj makro"
    m["Profiles"] := "Profile"
    m["Trigger key"] := "Klawisz wyzwalający"
    m["Toggle"] := "Przełącznik"
    m["Only in app (exe)"] := "Tylko w apce (exe)"
    m["Select"] := "Wybierz"
    m["Press"] := "Naciśnięcie"
    m["Normal"] := "Zwykłe"
    m["Short tap"] := "Krótkie"
    m["Double tap"] := "Podwójne"
    m["Long press"] := "Przytrzymanie"
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
    m["The toggle key {1} is already used as {2}."] := "Klawisz przełącznika {1} jest już używany jako {2}."
    m["Paste or write a script first."] := "Najpierw wklej lub napisz skrypt."
    m["Enter a trigger key."] := "Podaj klawisz wyzwalający."
    m["The toggle key can't be the same as the trigger key."] := "Klawisz przełącznika nie może być taki sam jak klawisz wyzwalający."
    m["The trigger key {1} is already used as {2}."] := "Klawisz wyzwalający {1} jest już używany jako {2}."
    m["Same trigger key as `"{1}`" - only one of them works"] := "Ten sam klawisz wyzwalający co „{1}” – działa tylko jedno z nich"
    m["Exact delays"] := "Dokładne opóźnienia"
    m["Save"] := "Zapisz"
    m["tap"] := "krótko"
    m["hold"] := "przytrzym."
    m["Saving the settings failed: {1}"] := "Nie udało się zapisać ustawień: {1}"
    m["the All macros toggle key"] := "przełącznik wszystkich makr"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makra `"{1}`" nie można włączyć (klawisz `"{2}`"):`n{3}"
    m["The key {1} is used twice - as {2} and as {3}. Only one of them works."] := "Klawisz {1} jest użyty dwa razy - jako {2} i jako {3}. Działa tylko jedno z nich."
    m["Same trigger key"] := "Ten sam klawisz wyzwalający"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}” używa tego samego klawisza wyzwalającego ({2}) co aktywne makro „{3}”. Działać będzie tylko jedno z nich."
    m["Turn on anyway"] := "Włącz mimo to"
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
    m["ComboCrown update"] := "Aktualizacja ComboCrown"
    m["Version {1} is available (you have v{2})."] := "Dostępna jest wersja {1} (masz v{2})."
    m["Later"] := "Później"
    m["Update now"] := "Aktualizuj teraz"
    m["The download failed. Try again later."] := "Pobieranie nie powiodło się. Spróbuj ponownie później."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Pobrany plik nie zgadza się z oczekiwaną sumą kontrolną (nowa wersja może być jeszcze wgrywana). Nic nie zostało zmienione - spróbuj ponownie za kilka minut.`n`nOczekiwano: {1}...`nOtrzymano: {2}  ({3} B)"
    m["(could not compute)"] := "(nie udało się obliczyć)"
    m["The downloaded file is not a valid ComboCrown script. Nothing was changed."] := "Pobrany plik nie jest prawidłowym skryptem ComboCrown. Nic nie zostało zmienione."
    m["Could not replace the app file: {1}"] := "Nie udało się zastąpić pliku aplikacji: {1}"
    m["Version {1}"] := "Wersja {1}"
    m["hlp_start"] := "ComboCrown uruchamia za ciebie makra klawiszowe. Każde makro ma klawisz wyzwalający; dopóki go trzymasz (w wybranej aplikacji), makro jest odtwarzane.`n`n- Zaznacz makro na liście, aby je włączyć, odznacz, aby je wyłączyć.`n- Przełącznik Wszystkie makra w nagłówku włącza lub wyłącza wszystkie makra naraz.`n- Tryb ciemny zmienia wygląd aplikacji.`n- Przycisk języka w nagłówku zmienia język aplikacji (English, Čeština, Polski, Deutsch). Aplikacja uruchomi się ponownie, aby go zastosować.`n- Kliknij dwukrotnie wiersz (lub naciśnij Edytuj), aby zmienić makro. Dodaj tworzy nowe, Kopiuj je powiela, Usuń je kasuje.`n- Aby zaznaczyć kilka makr, przeciągnij myszą po wierszach (lub Ctrl / Shift + kliknięcie). Kopiuj, Usuń, Eksportuj, W górę / W dół oraz przeciąganie poza okno działają na wszystkich zaznaczonych wierszach.`n- Zamknięcie okna zostawia aplikację uruchomioną w zasobniku systemowym. Kliknij ikonę w zasobniku prawym przyciskiem, aby wybrać Otwórz okno / Odinstaluj / Zakończ.`n- Aplikacja zawsze działa jako administrator, więc makra działają też w grach uruchomionych z podwyższonymi uprawnieniami.`n- Pole wyszukiwania nad listą pokazuje tylko makra, których nazwa, klawisz lub aplikacja zawiera wpisany tekst. Krzyżyk obok czyści wyszukiwanie."
    m["hlp_edit"] := "Nazwa - dowolny tekst, widoczny na liście.`nProfile - do jakich profili należy makro (może być kilka).`nKlawisz wyzwalający - kliknij pole, potem naciśnij klawisz lub przycisk myszy (prawy, środkowy, boczne X1 / X2, kółko myszy). Przytrzymaj Ctrl / Shift / Alt podczas naciskania, aby uzyskać kombinację, na przykład Ctrl+XButton1. Esc anuluje.`nPrzełącznik - opcjonalny klawisz, który włącza/wyłącza to makro bez otwierania okna. Backspace go czyści.`nTylko w apce (exe) - makro działa tylko wtedy, gdy ten program jest na wierzchu. Naciśnij Wybierz, aby wskazać uruchomioną aplikację lub wskazać plik .exe. Puste = działa wszędzie.`nTyp - Ruch + akcje, Sekwencja lub Skrypt (.ahk). Zobacz kolejne tematy.`nNaciśnięcie - jak trzeba nacisnąć klawisz wyzwalający. Zwykłe: makro startuje, gdy tylko klawisz zostanie wciśnięty. Krótkie: szybko naciśnij i puść - makro odtwarza się raz po puszczeniu. Podwójne: naciśnij klawisz dwa razy szybko. Przytrzymanie: przytrzymaj klawisz przez chwilę (z Powtarzaniem gra, dopóki go trzymasz). Jeden klawisz może w ten sposób mieć do trzech makr: krótkie, podwójne i przytrzymanie. Zwykłe makro na tym samym klawiszu zajmuje cały klawisz. Makra na kółku myszy zawsze startują od razu.`nUruchamiaj - Raz na naciśnięcie klawisza: odtwarza jeden przebieg i czeka, aż puścisz klawisz. Powtarzaj, gdy klawisz jest wciśnięty: odtwarza w kółko, dopóki nie puścisz klawisza (zatrzymuje się natychmiast). Niedostępne dla Krótkiego - zawsze odtwarza się raz.`nDokładne opóźnienia (na dole po lewej) - opóźnienia są dotrzymywane co do około milisekundy. Włączone dla nowych makr. Wyłączone = dawny sposób, w którym krótkie opóźnienia często trwają o 10-15 ms dłużej, niż wpisano.`n`nZapisz zapisuje makro, Anuluj odrzuca zmiany."
    m["hlp_move"] := "Stworzone dla gier, w których cały czas się poruszasz (np. A i D) i w międzyczasie rzucasz czary.`n`nKierunki - klawisze ruchu, po kolei, na przykład: a,d`nAkcje po kolei - klawisze do naciśnięcia, po jednym na cykl, na przykład: 1,2,1,F7,1,F8`n`nKażdy cykl wygląda tak, z ustawionymi przez ciebie opóźnieniami:`n  1. kierunek w dół`n  2. (opóźnienie 1) akcja w dół`n  3. (opóźnienie 2) kierunek w górę`n  4. (opóźnienie 3) akcja w górę`n  5. (opóźnienie 4) pauza, potem następny kierunek + następna akcja`n`nListy powtarzają się od początku, gdy się skończą. Jeśli Kierunki są puste, naciskane są tylko akcje: czas przytrzymania = opóźnienie 2, pauza = opóźnienie 4.`nJeśli gra ignoruje makro, zwiększ opóźnienia (20-30 ms to częsta wartość)."
    m["hlp_seq"] := "Dowolna lista kroków. Napisz jeden krok w linii:`n`n  down KEY PAUSE   - wciśnij i przytrzymaj klawisz`n  up KEY PAUSE     - puść klawisz`n  tap KEY PAUSE    - wciśnij i od razu puść`n`nPAUSE to czas oczekiwania po kroku w milisekundach (puste = 0).`n`nPrzykład - szybka zmiana A / D:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nPrzykład - atak i czary:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nPrzykład - dwa klawisze naraz:`n  tap Shift+4 50`n`nPrzy Uruchamiaj = Powtarzaj linie są odtwarzane w pętli, dopóki trzymasz klawisz wyzwalający; przy Raz odtwarzane są jeden raz.`nKlawisze, które nadal są wciśnięte, gdy puścisz klawisz wyzwalający, są puszczane automatycznie."
    m["hlp_script"] := "Do wszystkiego, czego nie potrafią inne typy. Wklej lub napisz własny skrypt AutoHotkey v2.`n`n- Skrypt działa jako osobny proces, dopóki makro jest zaznaczone, i jest zatrzymywany, gdy je odznaczysz.`n- Musi to być kod AutoHotkey v2 (skrypty v1 nie zadziałają).`n- Klawisz wyzwalający i filtr aplikacji nie są używane, twój skrypt robi to sam.`n- Zaimportowane pliki .ahk, które nie zostały utworzone przez ComboCrown, stają się makrami skryptowymi.`n- Zaimportowany skrypt pyta przed pierwszym uruchomieniem: działa z uprawnieniami administratora, więc włącz go tylko wtedy, gdy ufasz jego źródłu. Okno pokazuje, co robi skrypt (na przykład uruchamia programy lub usuwa pliki), i pozwala obejrzeć kod."
    m["hlp_keys"] := "Nazwy klawiszy to nazwy z AutoHotkey: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nKlawisz można też zapisać jako kod skanowania, na przykład sc002 - to fizyczny klawisz, niezależnie od układu. Klawisze takie jak przecinek, plus, & i | są zapisywane w ten sposób automatycznie.`n`nMysz: klawisz wyzwalający, przełącznik i klawisz Wszystkie makra mogą być też przyciskiem myszy: RButton, MButton (kliknięcie kółkiem), XButton1 / XButton2 (dwa przyciski boczne) lub samo kółko (WheelUp / WheelDown / WheelLeft / WheelRight). Kółko nie ma przytrzymania, więc makra na kółku zawsze odtwarzają się raz. Lewy przycisk nie jest dostępny.`nMyszy dla graczy / MMO: Windows zna tylko pięć przycisków myszy, dodatkowymi przyciskami bocznymi zajmuje się oprogramowanie myszy (G HUB, Synapse, iCUE, ...). Ustaw je tam na klawisze, najlepiej F13 - F24 (lub Ctrl+Alt+cyfra); ComboCrown widzi je wtedy jako zwykłe klawisze, więc kliknij pole klawisza wyzwalającego i naciśnij przycisk boczny.`n`nNagraj (obok Kierunków i Akcji): naciśnij Nagraj, naciskaj klawisze w żądanej kolejności, potem naciśnij Gotowe. Pole wypełnia się na żywo. Podczas nagrywania makra są wstrzymane.`n`nKlawisze jednocześnie: klawisze trzymane razem są zapisywane jako jeden krok połączony znakiem +, na przykład Shift+4. Przy odtwarzaniu makra wszystkie idą w dół razem i są puszczane razem (nie najpierw Shift, a potem 4).`nTo samo działa przy wpisywaniu w polach: a,Shift+4,d"
    m["hlp_profiles"] := "Profile oddzielają od siebie różne zestawy makr (na przykład jeden na grę).`n`n- Przycisk profilu w nagłówku pokazuje bieżący profil. Kliknij go, aby przełączyć profil albo utworzyć / zmienić nazwę / usunąć profil.`n- Lista pokazuje tylko makra bieżącego profilu i tylko one są aktywne.`n- W edytorze Profile pozwalają wybrać jeden lub kilka profili dla makra. Gdy zmieniasz makro należące do kilku profili, aplikacja pyta: zastosować zmianę we wszystkich, czy tylko w bieżącym profilu (pozostałe profile zachowają starą wersję).`n- Stan zaznaczenia makra jest taki sam w każdym profilu; zmiana profilu zmienia tylko to, które makra są w grze.`n- Usunięcie profilu przenosi makra, które należały tylko do niego, do pierwszego pozostałego profilu."
    m["hlp_toggle"] := "Przełącznik (w edytorze) - klawisz, który włącza / wyłącza to jedno makro, tak samo jak jego zaznaczenie na liście. Mała podpowiedź pokazuje WŁ. / WYŁ.`nKlawisz przełączania wszystkich makr (przycisk pod listą) - przełącza główny wyłącznik. Działa w każdym profilu.`n`nKliknij przycisk, naciśnij klawisz. Esc anuluje, Backspace usuwa klawisz.`nMakra z innych profili nie reagują na swoje klawisze przełączające."
    m["hlp_order"] := "W górę / W dół zmieniają kolejność na liście. Kliknięcie nagłówka kolumny sortuje listę (kliknij ponownie, aby odwrócić).`n`nEksportuj... zapisuje zaznaczone makro jako samodzielny plik AutoHotkey v2 .ahk, który działa też sam (poprosi o uprawnienia administratora).`nImportuj... wczytuje jeden lub więcej plików .ahk (albo po prostu przeciągnij je na główne okno). Możesz też przeciągnąć makro z listy na pulpit / do folderu / do okna czatu, aby wyeksportować je jako plik .ahk. Makro dostaje nazwę od pliku; pliki utworzone przez ComboCrown wracają jako edytowalne makra, inne skrypty stają się makrami skryptowymi. Importowane makra trafiają do bieżącego profilu i startują wyłączone.`nEksportuj całość... zapisuje każde makro do folderu, po jednym pliku.`n`nKopia... (obok Odinstaluj) zapisuje wszystko – makra, profile, ustawienia i pliki skryptów – do jednego pliku .mmbackup i przywraca go na nowym komputerze lub po ponownej instalacji. Plik kopii możesz też przeciągnąć na okno. Przed przywróceniem bieżący stan zostaje zapisany jako config\backup-before-restore.mmbackup.`n`nOdinstaluj usuwa cały folder aplikacji razem ze wszystkimi makrami i ustawieniami. Najpierw proponuje wyeksportowanie wszystkich makr."
    m["hlp_updates"] := "Ikona strzałki w nagłówku (obok przycisku profilu) pokazuje, czy jest nowa wersja: szara = masz aktualną wersję, zielona = dostępna jest nowa wersja. Najedź na nią, aby zobaczyć szczegóły.`n`nAplikacja sprawdza aktualizacje kilka sekund po uruchomieniu (można to wyłączyć w menu zasobnika systemowego: Sprawdzaj aktualizacje przy starcie). Kliknij ikonę w dowolnym momencie, aby sprawdzić ponownie. Nic nie zostanie zainstalowane, dopóki nie klikniesz zielonej ikony i nie potwierdzisz.`n`nPodczas aktualizacji aplikacja pobiera nowy plik, sprawdza jego sumę kontrolną, zachowuje stary jako Macro Manager.ahk.bak i uruchamia się ponownie. Twoje makra, profile i ustawienia są przechowywane osobno w folderze config i pozostają dokładnie takie, jakie są.`n`nJeśli coś pójdzie nie tak, zamknij aplikację, usuń Macro Manager.ahk i zmień nazwę Macro Manager.ahk.bak z powrotem na Macro Manager.ahk.`n`nAktualizacja wymaga dostępu do internetu (serwer Macro Hub lub github.com)."
    m["hlp_hub"] := "Macro Hub (przycisk obok wyszukiwania) pokazuje makra udostępnione przez graczy. Otwiera się jako panel z boku głównego okna.`n`n- Makra graczy: makra innych graczy. Moje makra: makra, które udostępniłeś, z ich ocenami i liczbą pobrań.`n- Szukaj słowami z nazwy, gry lub nazwy autora: każde słowo musi pasować. 4story znajdzie wszystkie makra do 4Story, 4story war tylko te dla wojownika.`n- Przycisk gry filtruje jedną grę, przycisk sortowania sortuje według ocen, najnowszych lub najczęściej pobieranych.`n- Każde makro pokazuje średnią ocenę w gwiazdkach (1 = najgorsza, 5 = najlepsza) z liczbą ocen w nawiasie, autora, grę, klawisz wyzwalający i liczbę pobrań. Złoty znaczek oznacza makra sprawdzone przez moderatora - są na początku.`n- Pole pod listą pokazuje opis i co makro robi (klawisze, opóźnienia, sekwencję) - zanim je pobierzesz.`n- Pobierz (lub podwójne kliknięcie) dodaje makro do bieżącego profilu jako wyłączone. Sprawdź jego klawisz i aplikację, a potem je zaznacz.`n- Oceń daje od 1 do 5 gwiazdek - jedna ocena na instalację, możesz ją później zmienić. Własnych makr nie można oceniać.`n- Zgłoś wysyła makro do sprawdzenia, np. makro farm / AFK, które jest niedozwolone. Po kilku zgłoszeniach makro zostaje ukryte.`n- Usuń (Moje makra) usuwa z Macro Hub makro, które udostępniłeś; Twoja kopia na liście zostaje.`n`nUdostępnianie: kliknij ikonę udostępniania na końcu wiersza na głównej liście i wpisz nazwę, grę, opis i swój pseudonim. Po udostępnieniu ikona staje się złota. Makra pobrane z Macro Hub mają zamiast niej strzałkę pobierania i można je udostępnić dopiero po zmianie.`n`nAktualizacje: gdy zmienisz udostępnione przez siebie makro, aplikacja zapyta, czy zaktualizować je w Macro Hub - oceny i liczba pobrań zostają (do tego czasu jego ikona ma kropkę; kliknij, aby zaktualizować). Gdy autor zaktualizuje pobrane przez Ciebie makro, pojawi się powiadomienie, a jego strzałka na liście zrobi się zielona: kliknij ją, aby zobaczyć zmiany i przyjąć nową wersję lub zostawić swoją. Udostępniane są: klawisze, opóźnienia, ustawienia Uruchamiania i Naciśnięcia oraz aplikacja. Nie są udostępniane: klawisz przełączania i Twoje profile. Makr skryptowych nie można udostępniać.`n`nMacro Hub wymaga dostępu do internetu. Nikt nie widzi, kto ocenił lub zgłosił makro. Aby rozpoznać makra pobrane starszą wersją, aplikacja wysyła raz do Macro Hub, co robią (klawisze, opóźnienia, sekwencję - nie ich nazwy); nic z tego nie jest zapisywane."
    m["hlp_tips"] := "- Gra nic nie robi: spróbuj zwiększyć opóźnienia, upewnij się, że Tylko w apce (exe) pasuje do gry (użyj Wybierz) i zostaw aplikację uruchomioną jako administrator.`n- Postać biegnie w jedną stronę: trzymaj pary kierunków w Kierunkach (a,d), a opóźnienie między cyklami małe, ale nie 0.`n- Makro się nie uruchamia: sprawdź, czy jest zaznaczone, czy Wszystkie makra jest włączone, czy jest w bieżącym profilu i czy klawisz wyzwalający jest ustawiony (nie jest pusty).`n- Dwa makra z tym samym klawiszem wyzwalającym: działa tylko jedno z nich - użyj różnych klawiszy, różnych profili lub różnego Naciśnięcia (krótkie / podwójne / przytrzymanie).`n- Makra utworzone przed Dokładnymi opóźnieniami zachowują dawny sposób odmierzania. Gdy włączysz im Dokładne opóźnienia, mogą grać szybciej - wtedy lekko zwiększ opóźnienia.`n- Zablokowany klawisz po przerwaniu: naciśnij go i puść raz; aplikacja puszcza klawisze, które nacisnęła, gdy makro się zatrzymuje.`n- Ustawienia i skrypty leżą w folderze config obok aplikacji."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Nie udało się otworzyć Discorda. Link został skopiowany do schowka - wklej go w przeglądarce:`n`n{1}"
    m["Help"] := "Pomoc"
    m["Join Discord"] := "Dołącz do Discorda"
    m["Close"] := "Zamknij"
    m["Set a trigger key first: {1}"] := "Najpierw ustaw klawisz wyzwalający: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Przeciągnięcie makra na zewnątrz nie powiodło się:`n{1}"
    m["Backup"] := "Kopia zapasowa"
    m["Backup and restore"] := "Kopia zapasowa i przywracanie"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Zapisz wszystkie makra, profile i ustawienia (łącznie z plikami skryptów) w jednym pliku kopii – na nowy komputer lub po ponownej instalacji. Albo przywróć je z takiego pliku."
    m["Restore..."] := "Przywróć..."
    m["Restore from backup"] := "Przywróć z kopii"
    m["This is not a ComboCrown backup file:`n{1}"] := "To nie jest plik kopii aplikacji ComboCrown:`n{1}"
    m["Restore this backup?"] := "Przywrócić tę kopię?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Wszystkie obecne makra, profile i ustawienia zostaną zastąpione kopią z {1} ({2} makr). Aplikacja uruchomi się ponownie.`n`nObecny stan zostanie najpierw zapisany jako:`n{3}"
    m["Restore"] := "Przywróć"
    m["The backup could not be restored:`n{1}"] := "Nie udało się przywrócić kopii:`n{1}"
    m["Can't reach Macro Hub. Check your internet connection and try again."] := "Nie można połączyć się z Macro Hub. Sprawdź połączenie z internetem i spróbuj ponownie."
    m["You have shared a lot of macros today. Please try again tomorrow."] := "Udostępniłeś dziś już wiele makr. Spróbuj ponownie jutro."
    m["You can't rate your own macro."] := "Nie możesz ocenić własnego makra."
    m["This macro is no longer in Macro Hub."] := "Tego makra nie ma już w Macro Hub."
    m["Only the author can delete this macro."] := "Tylko autor może usunąć to makro."
    m["Please check the name, game, description and nickname."] := "Sprawdź nazwę, grę, opis i pseudonim."
    m["Macro Hub could not do this ({1})."] := "Macro Hub nie mógł tego wykonać ({1})."
    m["Players' macros"] := "Makra graczy"
    m["My macros"] := "Moje makra"
    m["Search: name, game or author"] := "Szukaj: nazwa, gra lub autor"
    m["No connection"] := "Brak połączenia"
    m["Macro Hub needs the internet. It tries again by itself every few seconds."] := "Macro Hub potrzebuje internetu. Co kilka sekund próbuje ponownie sam."
    m["Try again"] := "Spróbuj ponownie"
    m["Load more"] := "Wczytaj więcej"
    m["Download"] := "Pobierz"
    m["Rate"] := "Oceń"
    m["Report"] := "Zgłoś"
    m["All games"] := "Wszystkie gry"
    m["Game: {1}"] := "Gra: {1}"
    m["Newest"] := "Najnowsze"
    m["Most downloaded"] := "Najczęściej pobierane"
    m["Top rated"] := "Najlepiej oceniane"
    m["Loading..."] := "Wczytywanie..."
    m["You have not shared any macro yet - use the share icon in your list."] := "Nie udostępniłeś jeszcze żadnego makra - użyj ikony udostępniania na swojej liście."
    m["Macro Hub is empty so far - share the first macro!"] := "Macro Hub jest na razie pusty - udostępnij pierwsze makro!"
    m["No macros found."] := "Nie znaleziono makr."
    m["Pick a macro to see its description."] := "Wybierz makro, aby zobaczyć jego opis."
    m["(no description)"] := "(brak opisu)"
    m["What it does:"] := "Co robi:"
    m["your macro"] := "Twoje makro"
    m["by {1}"] := "autor: {1}"
    m["updated {1}"] := "zaktualizowano {1}"
    m["verified"] := "zweryfikowane"
    m["hidden after reports"] := "ukryte po zgłoszeniach"
    m["your rating: {1}"] := "Twoja ocena: {1}"
    m["`"{1}`" added to profile {2} - switched off, tick it to turn it on."] := "`"{1}`" dodano do profilu {2} - jest wyłączone, zaznacz je, aby je włączyć."
    m["Downloaded macro"] := "Pobrane makro"
    m["This macro already has several ratings from your internet connection, so another one is not counted."] := "To makro ma już kilka ocen z Twojego połączenia internetowego, więc kolejna nie zostanie policzona."
    m["Thank you for rating!"] := "Dziękujemy za ocenę!"
    m["Report macro"] := "Zgłoś makro"
    m["Why should `"{1}`" be removed from Macro Hub? For example: a farm / AFK macro (not allowed), it does not work, or spam."] := "Dlaczego `"{1}`" powinno zostać usunięte z Macro Hub? Na przykład: makro farm / AFK (niedozwolone), nie działa lub spam."
    m["Thank you. The macro will be checked."] := "Dziękujemy. Makro zostanie sprawdzone."
    m["Delete from Macro Hub?"] := "Usunąć z Macro Hub?"
    m["`"{1}`" will be removed from Macro Hub for everyone, with its ratings. Your own copy in the list stays."] := "`"{1}`" zostanie usunięte z Macro Hub dla wszystkich, razem z ocenami. Twoja kopia na liście zostaje."
    m["Script macros can't be shared - only Move + actions and Sequence macros."] := "Makr skryptowych nie można udostępniać - tylko makra Ruch + akcje i Sekwencja."
    m["`"{1}`" comes from Macro Hub (author: {2}), so it can't be shared again as it is. Change it first - for example a delay or a key - and then share your own version."] := "`"{1}`" pochodzi z Macro Hub (autor: {2}), więc nie można go ponownie udostępnić bez zmian. Najpierw je zmień - np. opóźnienie lub klawisz - a potem udostępnij swoją wersję."
    m["Share macro"] := "Udostępnij makro"
    m["`"{1}`" is in Macro Hub and up to date. When you change it, you can update it there."] := "`"{1}`" jest w Macro Hub i jest aktualne. Gdy je zmienisz, możesz je tam zaktualizować."
    m["No connection to Macro Hub. Sharing needs the internet - try again when you are online."] := "Brak połączenia z Macro Hub. Udostępnianie wymaga internetu - spróbuj ponownie, gdy będziesz online."
    m["You have already shared this macro as `"{1}`". Change it to share a new version."] := "To makro udostępniłeś już jako `"{1}`". Zmień je, aby udostępnić nową wersję."
    m["This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version."] := "To makro jest już w Macro Hub jako `"{1}`" (autor: {2}). Najpierw je zmień - np. opóźnienie lub klawisz - a potem udostępnij swoją wersję."
    m["Thank you for sharing! `"{1}`" is now in Macro Hub."] := "Dziękujemy za udostępnienie! `"{1}`" jest teraz w Macro Hub."
    m["Update in Macro Hub?"] := "Zaktualizować w Macro Hub?"
    m["`"{1}`" is shared in Macro Hub. Update it there with your changes? Its ratings and downloads stay, and Macro Hub shows it as updated. Players who downloaded it get a notice."] := "`"{1}`" jest udostępnione w Macro Hub. Zaktualizować je tam Twoimi zmianami? Oceny i liczba pobrań zostaną, a Macro Hub pokaże je jako zaktualizowane. Gracze, którzy je pobrali, dostaną powiadomienie."
    m["Not now"] := "Nie teraz"
    m["Update"] := "Aktualizuj"
    m["You updated this macro a moment ago. The app sends this change by itself in a few minutes."] := "Zaktualizowałeś to makro przed chwilą. Aplikacja wyśle tę zmianę sama za kilka minut."
    m["No connection to Macro Hub. Your change is kept - the app sends the update by itself as soon as you are online again."] := "Brak połączenia z Macro Hub. Twoja zmiana jest zachowana - aplikacja wyśle aktualizację sama, gdy tylko znów będziesz online."
    m["`"{1}`" is no longer in Macro Hub. Share it again with the share icon."] := "`"{1}`" nie ma już w Macro Hub. Udostępnij je ponownie ikoną udostępniania."
    m["`"{1}`" is updated in Macro Hub."] := "`"{1}`" zostało zaktualizowane w Macro Hub."
    m["`"{1}`" has a new version in Macro Hub. Click its green arrow in the list to see the changes."] := "`"{1}`" ma nową wersję w Macro Hub. Kliknij jego zieloną strzałkę na liście, aby zobaczyć zmiany."
    m["{1} downloaded macros have a new version in Macro Hub. Click their green arrows in the list to see the changes."] := "{1} pobranych makr ma nową wersję w Macro Hub. Kliknij ich zielone strzałki na liście, aby zobaczyć zmiany."
    m["New version of `"{1}`" by {2}"] := "Nowa wersja `"{1}`" (autor: {2})"
    m["You changed this macro yourself - updating replaces your changes with the new version."] := "Zmieniłeś to makro sam - aktualizacja zastąpi Twoje zmiany nową wersją."
    m["Changes (yours → new):"] := "Zmiany (Twoje → nowe):"
    m["Keep mine"] := "Zostaw moje"
    m["`"{1}`" is updated to the new version."] := "`"{1}`" zostało zaktualizowane do nowej wersji."
    m["(no difference)"] := "(brak różnic)"
    m["Share `"{1}`" in Macro Hub"] := "Udostępnij `"{1}`" w Macro Hub"
    m["Game (people filter and search by it, for example 4Story)"] := "Gra (według niej się filtruje i szuka, np. 4Story)"
    m["Description (optional): what it does, for which class"] := "Opis (opcjonalny): co robi, do jakiej klasy"
    m["Your nickname"] := "Twój pseudonim"
    m["Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."] := "Udostępniane są: klawisze, opóźnienia, ustawienia Uruchamiania i Naciśnięcia oraz aplikacja. Nie są udostępniane: klawisz przełączania i Twoje profile. Każdy może je zobaczyć i pobrać. Makra farm / AFK są niedozwolone."
    m["Please fill in the name, the game and your nickname."] := "Wpisz nazwę, grę i swój pseudonim."
    m["Release notes"] := "Informacje o wersji"
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
    m["Macro Hub"] := "Macro Hub"
    m["Name"] := "Name"
    m["Key"] := "Taste"
    m["Application"] := "Anwendung"
    m["Type"] := "Typ"
    m["Share"] := "Teilen"
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
    m["the toggle key of `"{1}`""] := "Ein/Aus-Taste von „{1}“"
    m["the trigger key of `"{1}`""] := "Auslösetaste von „{1}“"
    m["The key {1} is already used as {2}."] := "Die Taste {1} wird bereits verwendet als {2}."
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
    m["ComboCrown setup"] := "Macro Manager Setup"
    m["ComboCrown is already installed"] := "ComboCrown ist bereits installiert"
    m["Installed in:`n{1}`n`nUpdate it with this file and start it, or just start the installed copy?"] := "Installiert in:`n{1}`n`nMit dieser Datei aktualisieren und starten oder nur die installierte Kopie starten?"
    m["Just start"] := "Nur starten"
    m["Update and start"] := "Aktualisieren und starten"
    m["Couldn't update the installed copy (is it running?). Starting the installed version.`n`n{1}"] := "Die installierte Kopie konnte nicht aktualisiert werden (läuft sie noch?). Die installierte Version wird gestartet.`n`n{1}"
    m["Choose where to install ComboCrown.`nA 'MacroManager' folder will be created there."] := "Wähle, wo ComboCrown installiert werden soll.`nDort wird ein Ordner 'MacroManager' angelegt."
    m["Installation failed:`n{1}"] := "Installation fehlgeschlagen:`n{1}"
    m["Create a Start Menu shortcut?"] := "Verknüpfung im Startmenü erstellen?"
    m["Skip"] := "Überspringen"
    m["Create"] := "Erstellen"
    m["Create a Desktop shortcut?"] := "Verknüpfung auf dem Desktop erstellen?"
    m["Installed to:`n{1}`n`nYour macros and settings are stored in:`n{1}\config"] := "Installiert in:`n{1}`n`nDeine Makros und Einstellungen liegen in:`n{1}\config"
    m["This doesn't look like an installed copy, nothing was removed."] := "Das sieht nicht nach einer installierten Kopie aus, es wurde nichts entfernt."
    m["Uninstall ComboCrown"] := "ComboCrown deinstallieren"
    m["Uninstall ComboCrown?`n`nThis permanently deletes the whole folder, including all macros and settings:`n{1}"] := "ComboCrown deinstallieren?`n`nDadurch wird der gesamte Ordner endgültig gelöscht, einschließlich aller Makros und Einstellungen:`n{1}"
    m["Save a backup of your macros, profiles and settings before uninstalling? After a reinstall you can restore it with Backup... > Restore..."] := "Vor der Deinstallation eine Sicherung der Makros, Profile und Einstellungen speichern? Nach einer Neuinstallation stellst du sie über Sicherung... > Wiederherstellen... wieder her."
    m["Don't save"] := "Nicht speichern"
    m["Create backup..."] := "Sicherung erstellen..."
    m["Create backup"] := "Sicherung erstellen"
    m["ComboCrown backup (*.mmbackup)"] := "ComboCrown-Sicherung (*.mmbackup)"
    m["The backup could not be saved:`n{1}"] := "Die Sicherung konnte nicht gespeichert werden:`n{1}"
    m["Backup saved to:`n{1}"] := "Sicherung gespeichert unter:`n{1}"
    m["ComboCrown has been uninstalled.`nThe folder will be removed in a moment."] := "ComboCrown wurde deinstalliert.`nDer Ordner wird gleich entfernt."
    m["New macro"] := "Neues Makro"
    m["Edit macro"] := "Makro bearbeiten"
    m["Profiles"] := "Profile"
    m["Trigger key"] := "Auslösetaste"
    m["Toggle"] := "Ein/Aus-Taste"
    m["Only in app (exe)"] := "Nur in App (exe)"
    m["Select"] := "Wählen"
    m["Press"] := "Drücken"
    m["Normal"] := "Normal"
    m["Short tap"] := "Kurz tippen"
    m["Double tap"] := "Doppelt tippen"
    m["Long press"] := "Lang drücken"
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
    m["The toggle key {1} is already used as {2}."] := "Die Ein/Aus-Taste {1} wird bereits verwendet als {2}."
    m["Paste or write a script first."] := "Füge zuerst ein Skript ein oder schreibe eines."
    m["Enter a trigger key."] := "Gib eine Auslösetaste an."
    m["The toggle key can't be the same as the trigger key."] := "Die Ein/Aus-Taste darf nicht dieselbe sein wie die Auslösetaste."
    m["The trigger key {1} is already used as {2}."] := "Die Auslösetaste {1} wird bereits verwendet als {2}."
    m["Same trigger key as `"{1}`" - only one of them works"] := "Gleiche Auslösetaste wie „{1}“ – nur eines von beiden funktioniert"
    m["Exact delays"] := "Genaue Verzögerungen"
    m["Save"] := "Speichern"
    m["tap"] := "kurz"
    m["hold"] := "halten"
    m["Saving the settings failed: {1}"] := "Speichern der Einstellungen fehlgeschlagen: {1}"
    m["the All macros toggle key"] := "Taste für alle Makros"
    m["Macro `"{1}`" can't be enabled (key `"{2}`"):`n{3}"] := "Makro `"{1}`" kann nicht aktiviert werden (Taste `"{2}`"):`n{3}"
    m["The key {1} is used twice - as {2} and as {3}. Only one of them works."] := "Die Taste {1} ist doppelt belegt - als {2} und als {3}. Nur eines davon funktioniert."
    m["Same trigger key"] := "Gleiche Auslösetaste"
    m["Macro `"{1}`" uses the same trigger key ({2}) as the active macro `"{3}`". Only one of them will work."] := "Makro „{1}“ verwendet dieselbe Auslösetaste ({2}) wie das aktive Makro „{3}“. Nur eines von beiden wird funktionieren."
    m["Turn on anyway"] := "Trotzdem einschalten"
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
    m["ComboCrown update"] := "ComboCrown Update"
    m["Version {1} is available (you have v{2})."] := "Version {1} ist verfügbar (du hast v{2})."
    m["Later"] := "Später"
    m["Update now"] := "Jetzt aktualisieren"
    m["The download failed. Try again later."] := "Der Download ist fehlgeschlagen. Versuche es später erneut."
    m["The downloaded file does not match the expected checksum (the new version may still be uploading). Nothing was changed - try again in a few minutes.`n`nExpected: {1}...`nReceived: {2}  ({3} bytes)"] := "Die heruntergeladene Datei stimmt nicht mit der erwarteten Prüfsumme überein (die neue Version wird möglicherweise noch hochgeladen). Es wurde nichts geändert - versuche es in ein paar Minuten erneut.`n`nErwartet: {1}...`nErhalten: {2}  ({3} Bytes)"
    m["(could not compute)"] := "(konnte nicht berechnet werden)"
    m["The downloaded file is not a valid ComboCrown script. Nothing was changed."] := "Die heruntergeladene Datei ist kein gültiges ComboCrown Skript. Es wurde nichts geändert."
    m["Could not replace the app file: {1}"] := "Die App-Datei konnte nicht ersetzt werden: {1}"
    m["Version {1}"] := "Version {1}"
    m["hlp_start"] := "ComboCrown führt Hotkey-Makros für dich aus. Jedes Makro hat eine Auslösetaste; solange du sie gedrückt hältst (innerhalb der gewählten Anwendung), läuft das Makro.`n`n- Hake ein Makro in der Liste an, um es einzuschalten, entferne den Haken, um es auszuschalten.`n- Der Schalter Alle Makros in der Kopfzeile schaltet alle Makros auf einmal ein oder aus.`n- Dunkelmodus wechselt das Aussehen der App.`n- Die Sprachschaltfläche in der Kopfzeile wechselt die App-Sprache (English, Čeština, Polski, Deutsch). Die App startet neu, um sie zu übernehmen.`n- Doppelklick auf eine Zeile (oder Bearbeiten) ändert ein Makro. Hinzufügen legt ein neues an, Kopieren dupliziert es, Löschen entfernt es.`n- Um mehrere Makros auszuwählen, zieh die Maus über die Zeilen (oder Ctrl / Shift + Klick). Kopieren, Löschen, Exportieren, Nach oben / unten und das Herausziehen aus dem Fenster wirken auf alle ausgewählten Zeilen.`n- Beim Schließen des Fensters läuft die App im Infobereich weiter. Rechtsklick auf das Symbol im Infobereich öffnet Fenster öffnen / Deinstallieren... / Beenden.`n- Die App läuft immer als Administrator, damit Makros auch in Spielen funktionieren, die mit erhöhten Rechten laufen.`n- Das Suchfeld über der Liste zeigt nur die Makros, deren Name, Taste oder Anwendung den Text enthält. Das Kreuz daneben leert es."
    m["hlp_edit"] := "Name - beliebiger Text, wird in der Liste angezeigt.`nProfile - zu welchen Profilen das Makro gehört (auch mehrere).`nAuslösetaste - klicke in das Feld und drücke dann die Taste oder eine Maustaste (rechte, mittlere, Seitentasten X1 / X2, Mausrad). Halte beim Drücken Ctrl / Shift / Alt gedrückt, um eine Kombination zu bilden, zum Beispiel Ctrl+XButton1. Esc bricht ab.`nEin/Aus-Taste - optionale Taste, die dieses Makro ein-/ausschaltet, ohne das Fenster zu öffnen. Backspace löscht sie.`nNur in App (exe) - das Makro funktioniert nur, solange dieses Programm im Vordergrund ist. Drücke Wählen, um eine laufende Anwendung auszuwählen oder nach der .exe zu suchen. Leer = funktioniert überall.`nTyp - Bewegung + Aktionen, Sequenz oder Skript (.ahk). Siehe die nächsten Themen.`nDrücken - wie die Auslösetaste gedrückt werden muss. Normal: das Makro startet, sobald die Taste unten ist. Kurz tippen: kurz drücken und loslassen - das Makro spielt einmal nach dem Loslassen. Doppelt tippen: die Taste zweimal schnell drücken. Lang drücken: die Taste einen Moment halten (mit Wiederholen spielt es, solange du sie hältst). Eine Taste kann so bis zu drei Makros tragen: kurz tippen, doppelt tippen und lang drücken. Ein normales Makro auf derselben Taste belegt die ganze Taste. Mausrad-Makros starten immer sofort.`nAusführung - Einmal pro Tastendruck: spielt einen Durchlauf ab und wartet, bis du die Taste loslässt. Wiederholen, solange Taste gehalten: spielt immer wieder ab, bis du die Taste loslässt (es stoppt sofort). Bei Kurz tippen nicht verfügbar - es spielt immer einmal.`nGenaue Verzögerungen (unten links) - die Verzögerungen werden auf etwa eine Millisekunde eingehalten. Für neue Makros an. Aus = das frühere Timing, bei dem kurze Verzögerungen oft 10-15 ms länger dauern als eingetragen.`n`nSpeichern sichert das Makro, Abbrechen verwirft die Änderungen."
    m["hlp_move"] := "Gedacht für Spiele, in denen du dich ständig bewegst (zum Beispiel A und D) und dazwischen Zauber wirkst.`n`nRichtungen - die Bewegungstasten in Reihenfolge, zum Beispiel: a,d`nAktionen in Folge - die zu drückenden Tasten, eine pro Zyklus, zum Beispiel: 1,2,1,F7,1,F8`n`nJeder Zyklus läuft so ab, mit den eingestellten Verzögerungen:`n  1. Richtung runter`n  2. (Verzögerung 1) Aktion runter`n  3. (Verzögerung 2) Richtung hoch`n  4. (Verzögerung 3) Aktion hoch`n  5. (Verzögerung 4) Pause, dann die nächste Richtung + nächste Aktion`n`nDie Listen beginnen am Ende wieder von vorn. Wenn Richtungen leer ist, werden nur die Aktionen gedrückt: Haltezeit = Verzögerung 2, Pause = Verzögerung 4.`nWenn ein Spiel das Makro ignoriert, erhöhe die Verzögerungen (20-30 ms sind üblich)."
    m["hlp_seq"] := "Eine freie Liste von Schritten. Schreibe einen Schritt pro Zeile:`n`n  down KEY PAUSE   - Taste drücken und halten`n  up KEY PAUSE     - Taste loslassen`n  tap KEY PAUSE    - sofort drücken und loslassen`n`nPAUSE ist die Wartezeit nach dem Schritt in Millisekunden (leer = 0).`n`nBeispiel - schneller A / D-Wechsel:`n  down a 25`n  up a 5`n  down d 25`n  up d 5`n`nBeispiel - Angriff und Zauber:`n  tap 1 600`n  tap e 100`n  tap F7 100`n`nBeispiel - zwei Tasten zusammen:`n  tap Shift+4 50`n`nBei Ausführung = Wiederholen laufen die Zeilen in einer Schleife, solange die Auslösetaste gehalten wird; bei Einmal werden sie einmal abgespielt.`nTasten, die beim Loslassen der Auslösetaste noch gehalten werden, werden automatisch losgelassen."
    m["hlp_script"] := "Für alles, was die anderen Typen nicht können. Füge ein eigenes AutoHotkey v2 Skript ein oder schreibe eines.`n`n- Das Skript läuft als eigener Prozess, solange das Makro angehakt ist, und wird beendet, wenn du den Haken entfernst.`n- Es muss AutoHotkey v2 Code sein (v1-Skripte funktionieren nicht).`n- Auslösetaste und Anwendungsfilter werden nicht verwendet, das erledigt dein Skript selbst.`n- Importierte .ahk-Dateien, die nicht von ComboCrown erstellt wurden, werden zu Skript-Makros.`n- Ein importiertes Skript fragt vor dem ersten Start nach: Es läuft mit Administratorrechten, schalte es also nur ein, wenn du seiner Herkunft vertraust. Das Fenster zeigt, was das Skript tut (zum Beispiel Programme starten oder Dateien löschen), und bietet an, den Code anzuzeigen."
    m["hlp_keys"] := "Tastennamen sind die AutoHotkey-Namen: a, 1, F7, Space, Enter, Tab, LCtrl, LShift, Numpad1 ...`nEine Taste kann auch als Scancode geschrieben werden, zum Beispiel sc002 - das ist die physische Taste, unabhängig vom Layout. Tasten wie Komma, Plus, & und | werden automatisch so gespeichert.`n`nMaus: Auslöse-, Ein/Aus-Taste und die Taste für Alle Makros können auch eine Maustaste sein: RButton, MButton (Radklick), XButton1 / XButton2 (die zwei Seitentasten) oder das Rad selbst (WheelUp / WheelDown / WheelLeft / WheelRight). Ein Rad kann nicht gehalten werden, daher laufen Rad-Makros immer nur einmal. Die linke Taste steht nicht zur Auswahl.`nGaming- / MMO-Mäuse: Windows kennt nur fünf Maustasten, die zusätzlichen Seitentasten werden von der Maussoftware (G HUB, Synapse, iCUE, ...) verwaltet. Belege sie dort mit Tasten, am besten F13 - F24 (oder Ctrl+Alt+Zahl); ComboCrown sieht sie dann als normale Tasten, klicke also in das Feld Auslösetaste und drücke die Seitentaste.`n`nAufnehmen (neben Richtungen und Aktionen): Drücke Aufnehmen, drücke die Tasten in der gewünschten Reihenfolge und dann Fertig. Das Feld füllt sich live. Makros sind während der Aufnahme pausiert.`n`nTasten gleichzeitig: Tasten, die du zusammen hältst, werden als ein Schritt gespeichert und mit + verbunden, zum Beispiel Shift+4. Beim Abspielen gehen alle zusammen runter und werden zusammen losgelassen (nicht erst Shift und danach 4).`nDasselbe funktioniert durch Eintippen in die Felder: a,Shift+4,d"
    m["hlp_profiles"] := "Profile halten verschiedene Makro-Sets getrennt (zum Beispiel eines pro Spiel).`n`n- Die Profilschaltfläche in der Kopfzeile zeigt das aktuelle Profil. Klicke darauf, um zu wechseln oder ein Profil anzulegen / umzubenennen / zu löschen.`n- Die Liste zeigt nur die Makros des aktuellen Profils, und nur diese sind aktiv.`n- Im Editor kannst du unter Profile ein oder mehrere Profile für das Makro wählen. Wenn du ein Makro änderst, das zu mehreren Profilen gehört, fragt die App: Änderung auf alle anwenden oder nur auf das aktuelle Profil (die anderen Profile behalten die alte Version).`n- Der Haken-Status eines Makros bleibt in jedem Profil gleich; ein Profilwechsel ändert nur, welche Makros im Spiel sind.`n- Beim Löschen eines Profils werden Makros, die nur dazu gehörten, in das erste verbleibende Profil verschoben."
    m["hlp_toggle"] := "Ein/Aus-Taste (im Editor) - eine Taste, die genau dieses Makro ein- / ausschaltet, wie das Anhaken in der Liste. Ein kleiner Tooltip zeigt AN / AUS.`nEin/Aus-Taste für alle Makros (Schaltfläche unter der Liste) - schaltet den Hauptschalter. Funktioniert in jedem Profil.`n`nKlicke auf die Schaltfläche, drücke die Taste. Esc bricht ab, Backspace entfernt die Taste.`nMakros anderer Profile reagieren nicht auf ihre Ein/Aus-Tasten."
    m["hlp_order"] := "Nach oben / Nach unten ändern die Reihenfolge in der Liste. Ein Klick auf eine Spaltenüberschrift sortiert die Liste (erneut klicken kehrt um).`n`nExportieren... speichert das ausgewählte Makro als eigenständige AutoHotkey v2 .ahk-Datei, die auch allein läuft (sie fragt nach Administratorrechten).`nImportieren... lädt eine oder mehrere .ahk-Dateien (oder zieh sie einfach ins Hauptfenster). Du kannst ein Makro auch aus der Liste auf den Desktop / in einen Ordner / in ein Chatfenster ziehen, um es als .ahk-Datei zu exportieren. Das Makro wird nach der Datei benannt; von ComboCrown erstellte Dateien kommen als bearbeitbare Makros zurück, andere Skripte werden zu Skript-Makros. Importe landen im aktuellen Profil und sind zunächst ausgeschaltet.`nAlle exportieren... schreibt jedes Makro in einen Ordner, je eine Datei.`n`nSicherung... (neben Deinstall.) speichert alles – Makros, Profile, Einstellungen und Skriptdateien – in einer .mmbackup-Datei und stellt sie auf einem neuen PC oder nach einer Neuinstallation wieder her. Du kannst die Sicherungsdatei auch auf das Fenster ziehen. Vor dem Wiederherstellen wird der aktuelle Stand als config\backup-before-restore.mmbackup gespeichert.`n`nDeinstallieren löscht den gesamten App-Ordner einschließlich aller Makros und Einstellungen. Es bietet vorher an, alle Makros zu exportieren."
    m["hlp_updates"] := "Das Pfeilsymbol in der Kopfzeile (neben der Profilschaltfläche) zeigt, ob es eine neue Version gibt: grau = du bist auf dem neuesten Stand, grün = eine neue Version ist verfügbar. Fahre mit der Maus darüber für Details.`n`nDie App prüft einige Sekunden nach dem Start (im Menü des Infobereichs abschaltbar: Beim Start nach Updates suchen). Klicke jederzeit auf das Symbol, um erneut zu prüfen. Es wird nichts installiert, bis du auf das grüne Symbol klickst und bestätigst.`n`nBeim Update lädt die App die neue Datei herunter, prüft ihre Prüfsumme, behält die alte als Macro Manager.ahk.bak und startet neu. Deine Makros, Profile und Einstellungen liegen getrennt im Ordner config und bleiben genau so, wie sie sind.`n`nWenn etwas schiefgeht, schließe die App, lösche Macro Manager.ahk und benenne Macro Manager.ahk.bak wieder in Macro Manager.ahk um.`n`nFür das Update ist Internetzugang nötig (Macro-Hub-Server oder github.com)."
    m["hlp_hub"] := "Der Macro Hub (Schaltfläche neben der Suche) zeigt Makros, die Spieler teilen. Er öffnet sich als Seitenleiste neben dem Hauptfenster.`n`n- Makros der Spieler: Makros anderer Spieler. Meine Makros: die Makros, die du geteilt hast, mit ihren Bewertungen und Downloads.`n- Suche mit Wörtern aus dem Namen, dem Spiel oder dem Autor: jedes Wort muss passen. 4story findet alle 4Story-Makros, 4story war nur die für den Krieger.`n- Die Spiel-Schaltfläche filtert ein Spiel, die Sortier-Schaltfläche sortiert nach Bewertung, Neueste oder Meiste Downloads.`n- Jedes Makro zeigt seine Durchschnittsbewertung in Sternen (1 = am schlechtesten, 5 = am besten) mit der Anzahl der Bewertungen in Klammern, den Autor, das Spiel, die Auslösetaste und wie oft es heruntergeladen wurde. Ein goldener Haken markiert vom Moderator geprüfte Makros - sie stehen oben.`n- Das Feld unter der Liste zeigt die Beschreibung und was das Makro tut (Tasten, Verzögerungen, Sequenz) - noch vor dem Herunterladen.`n- Herunterladen (oder ein Doppelklick) fügt das Makro dem aktuellen Profil hinzu, ausgeschaltet. Prüfe Taste und Anwendung und hake es dann an.`n- Bewerten vergibt 1 bis 5 Sterne - eine Bewertung pro Installation, du kannst sie später ändern. Eigene Makros kann man nicht bewerten.`n- Melden schickt ein Makro zur Prüfung, zum Beispiel ein Farm- / AFK-Makro, das nicht erlaubt ist. Nach mehreren Meldungen wird es ausgeblendet.`n- Löschen (Meine Makros) entfernt ein von dir geteiltes Makro aus dem Macro Hub; deine eigene Kopie in der Liste bleibt.`n`nTeilen: Klicke auf das Teilen-Symbol am Ende einer Zeile in der Hauptliste und gib Name, Spiel, Beschreibung und deinen Spitznamen ein. Das Symbol wird golden, sobald das Makro geteilt ist. Aus dem Macro Hub geladene Makros zeigen stattdessen einen Download-Pfeil und können erst nach einer Änderung geteilt werden.`n`nAktualisierungen: Wenn du ein geteiltes Makro änderst, fragt die App, ob es im Macro Hub aktualisiert werden soll - Bewertungen und Downloads bleiben (bis dahin hat sein Symbol einen Punkt; ein Klick aktualisiert es). Wenn der Autor ein Makro aktualisiert, das du heruntergeladen hast, erscheint ein Hinweis und sein Pfeil in der Liste wird grün: Klicke darauf, um die Änderungen zu sehen und die neue Version zu übernehmen oder deine zu behalten. Geteilt werden: Tasten, Verzögerungen, Ausführen- und Drücken-Einstellungen und die Anwendung. Nicht geteilt: die Umschalttaste und deine Profile. Skript-Makros können nicht geteilt werden.`n`nDer Macro Hub braucht eine Internetverbindung. Niemand kann sehen, wer ein Makro bewertet oder gemeldet hat. Um mit einer älteren Version geladene Makros zu erkennen, sendet die App dem Macro Hub einmal, was sie tun (Tasten, Verzögerungen, Sequenz - nicht ihre Namen); davon wird nichts gespeichert."
    m["hlp_tips"] := "- Das Spiel reagiert nicht: Erhöhe die Verzögerungen, stelle sicher, dass Nur in App zum Spiel passt (nutze Wählen), und lass die App als Administrator laufen.`n- Der Charakter läuft nur in eine Richtung: Halte Richtungspaare in Richtungen (a,d) und die Verzögerung zwischen Zyklen klein, aber nicht 0.`n- Ein Makro startet nicht: Prüfe, ob es angehakt ist, Alle Makros an ist, es im aktuellen Profil liegt und die Auslösetaste gesetzt ist (nicht undefiniert).`n- Zwei Makros mit derselben Auslösetaste: Nur eines davon funktioniert - nutze unterschiedliche Tasten, unterschiedliche Profile oder unterschiedliches Drücken (kurz / doppelt / lang).`n- Makros, die vor den Genauen Verzögerungen erstellt wurden, behalten ihr altes Timing. Schaltest du sie für eines davon ein, kann es schneller spielen - erhöhe dann seine Verzögerungen etwas.`n- Hängende Taste nach einem Abbruch: Drücke sie einmal und lass sie los; die App lässt Tasten los, die sie gedrückt hat, wenn das Makro stoppt.`n- Einstellungen und Skripte liegen im Ordner config neben der App."
    m["Could not open Discord. The link was copied to the clipboard - paste it into your browser:`n`n{1}"] := "Discord konnte nicht geöffnet werden. Der Link wurde in die Zwischenablage kopiert - füge ihn in deinen Browser ein:`n`n{1}"
    m["Help"] := "Hilfe"
    m["Join Discord"] := "Discord beitreten"
    m["Close"] := "Schließen"
    m["Set a trigger key first: {1}"] := "Lege zuerst eine Auslösetaste fest: {1}"
    m["Dragging the macro out failed:`n{1}"] := "Das Herausziehen des Makros ist fehlgeschlagen:`n{1}"
    m["Backup"] := "Sicherung"
    m["Backup and restore"] := "Sichern und Wiederherstellen"
    m["Save all macros, profiles and settings (including script files) into one backup file - for a new PC or a reinstall. Or restore them from such a file."] := "Speichere alle Makros, Profile und Einstellungen (inklusive Skriptdateien) in einer Sicherungsdatei – für einen neuen PC oder eine Neuinstallation. Oder stelle sie aus einer solchen Datei wieder her."
    m["Restore..."] := "Wiederherstellen..."
    m["Restore from backup"] := "Aus Sicherung wiederherstellen"
    m["This is not a ComboCrown backup file:`n{1}"] := "Das ist keine Sicherungsdatei von ComboCrown:`n{1}"
    m["Restore this backup?"] := "Diese Sicherung wiederherstellen?"
    m["All your current macros, profiles and settings are replaced with the backup from {1} ({2} macros). The app restarts.`n`nYour current state is saved first as:`n{3}"] := "Alle aktuellen Makros, Profile und Einstellungen werden durch die Sicherung vom {1} ({2} Makros) ersetzt. Die App startet neu.`n`nDer aktuelle Stand wird zuerst gespeichert als:`n{3}"
    m["Restore"] := "Wiederherstellen"
    m["The backup could not be restored:`n{1}"] := "Die Sicherung konnte nicht wiederhergestellt werden:`n{1}"
    m["Can't reach Macro Hub. Check your internet connection and try again."] := "Macro Hub ist nicht erreichbar. Prüfe deine Internetverbindung und versuche es erneut."
    m["You have shared a lot of macros today. Please try again tomorrow."] := "Du hast heute schon viele Makros geteilt. Bitte versuche es morgen wieder."
    m["You can't rate your own macro."] := "Dein eigenes Makro kannst du nicht bewerten."
    m["This macro is no longer in Macro Hub."] := "Dieses Makro ist nicht mehr im Macro Hub."
    m["Only the author can delete this macro."] := "Nur der Autor kann dieses Makro löschen."
    m["Please check the name, game, description and nickname."] := "Bitte prüfe Name, Spiel, Beschreibung und Spitznamen."
    m["Macro Hub could not do this ({1})."] := "Macro Hub konnte das nicht ausführen ({1})."
    m["Players' macros"] := "Makros der Spieler"
    m["My macros"] := "Meine Makros"
    m["Search: name, game or author"] := "Suchen: Name, Spiel oder Autor"
    m["No connection"] := "Keine Verbindung"
    m["Macro Hub needs the internet. It tries again by itself every few seconds."] := "Der Macro Hub braucht das Internet. Er versucht es alle paar Sekunden von selbst erneut."
    m["Try again"] := "Erneut versuchen"
    m["Load more"] := "Mehr laden"
    m["Download"] := "Herunterladen"
    m["Rate"] := "Bewerten"
    m["Report"] := "Melden"
    m["All games"] := "Alle Spiele"
    m["Game: {1}"] := "Spiel: {1}"
    m["Newest"] := "Neueste"
    m["Most downloaded"] := "Meiste Downloads"
    m["Top rated"] := "Bestbewertet"
    m["Loading..."] := "Wird geladen..."
    m["You have not shared any macro yet - use the share icon in your list."] := "Du hast noch kein Makro geteilt - nutze das Teilen-Symbol in deiner Liste."
    m["Macro Hub is empty so far - share the first macro!"] := "Der Macro Hub ist noch leer - teile das erste Makro!"
    m["No macros found."] := "Keine Makros gefunden."
    m["Pick a macro to see its description."] := "Wähle ein Makro, um seine Beschreibung zu sehen."
    m["(no description)"] := "(keine Beschreibung)"
    m["What it does:"] := "Was es tut:"
    m["your macro"] := "dein Makro"
    m["by {1}"] := "von {1}"
    m["updated {1}"] := "aktualisiert {1}"
    m["verified"] := "geprüft"
    m["hidden after reports"] := "nach Meldungen ausgeblendet"
    m["your rating: {1}"] := "deine Bewertung: {1}"
    m["`"{1}`" added to profile {2} - switched off, tick it to turn it on."] := "`"{1}`" wurde zum Profil {2} hinzugefügt - ausgeschaltet, hake es an, um es einzuschalten."
    m["Downloaded macro"] := "Heruntergeladenes Makro"
    m["This macro already has several ratings from your internet connection, so another one is not counted."] := "Dieses Makro hat schon mehrere Bewertungen von deiner Internetverbindung, eine weitere wird nicht gezählt."
    m["Thank you for rating!"] := "Danke für deine Bewertung!"
    m["Report macro"] := "Makro melden"
    m["Why should `"{1}`" be removed from Macro Hub? For example: a farm / AFK macro (not allowed), it does not work, or spam."] := "Warum soll `"{1}`" aus dem Macro Hub entfernt werden? Zum Beispiel: ein Farm- / AFK-Makro (nicht erlaubt), es funktioniert nicht, oder Spam."
    m["Thank you. The macro will be checked."] := "Danke. Das Makro wird geprüft."
    m["Delete from Macro Hub?"] := "Aus dem Macro Hub löschen?"
    m["`"{1}`" will be removed from Macro Hub for everyone, with its ratings. Your own copy in the list stays."] := "`"{1}`" wird für alle aus dem Macro Hub entfernt, samt Bewertungen. Deine eigene Kopie in der Liste bleibt."
    m["Script macros can't be shared - only Move + actions and Sequence macros."] := "Skript-Makros können nicht geteilt werden - nur Bewegung + Aktionen und Sequenz."
    m["`"{1}`" comes from Macro Hub (author: {2}), so it can't be shared again as it is. Change it first - for example a delay or a key - and then share your own version."] := "`"{1}`" stammt aus dem Macro Hub (Autor: {2}) und kann so nicht erneut geteilt werden. Ändere es zuerst - zum Beispiel eine Verzögerung oder eine Taste - und teile dann deine eigene Version."
    m["Share macro"] := "Makro teilen"
    m["`"{1}`" is in Macro Hub and up to date. When you change it, you can update it there."] := "`"{1}`" ist im Macro Hub und aktuell. Wenn du es änderst, kannst du es dort aktualisieren."
    m["No connection to Macro Hub. Sharing needs the internet - try again when you are online."] := "Keine Verbindung zum Macro Hub. Teilen braucht das Internet - versuche es erneut, wenn du online bist."
    m["You have already shared this macro as `"{1}`". Change it to share a new version."] := "Dieses Makro hast du bereits als `"{1}`" geteilt. Ändere es, um eine neue Version zu teilen."
    m["This macro is already in Macro Hub as `"{1}`" by {2}. Change it first - for example a delay or a key - and then share your own version."] := "Dieses Makro ist bereits im Macro Hub als `"{1}`" von {2}. Ändere es zuerst - zum Beispiel eine Verzögerung oder eine Taste - und teile dann deine eigene Version."
    m["Thank you for sharing! `"{1}`" is now in Macro Hub."] := "Danke fürs Teilen! `"{1}`" ist jetzt im Macro Hub."
    m["Update in Macro Hub?"] := "Im Macro Hub aktualisieren?"
    m["`"{1}`" is shared in Macro Hub. Update it there with your changes? Its ratings and downloads stay, and Macro Hub shows it as updated. Players who downloaded it get a notice."] := "`"{1}`" ist im Macro Hub geteilt. Dort mit deinen Änderungen aktualisieren? Bewertungen und Downloads bleiben, und der Macro Hub zeigt es als aktualisiert. Spieler, die es heruntergeladen haben, bekommen einen Hinweis."
    m["Not now"] := "Nicht jetzt"
    m["Update"] := "Aktualisieren"
    m["You updated this macro a moment ago. The app sends this change by itself in a few minutes."] := "Du hast dieses Makro gerade erst aktualisiert. Die App sendet diese Änderung in ein paar Minuten von selbst."
    m["No connection to Macro Hub. Your change is kept - the app sends the update by itself as soon as you are online again."] := "Keine Verbindung zum Macro Hub. Deine Änderung bleibt erhalten - die App sendet die Aktualisierung von selbst, sobald du wieder online bist."
    m["`"{1}`" is no longer in Macro Hub. Share it again with the share icon."] := "`"{1}`" ist nicht mehr im Macro Hub. Teile es erneut mit dem Teilen-Symbol."
    m["`"{1}`" is updated in Macro Hub."] := "`"{1}`" ist im Macro Hub aktualisiert."
    m["`"{1}`" has a new version in Macro Hub. Click its green arrow in the list to see the changes."] := "`"{1}`" hat eine neue Version im Macro Hub. Klicke auf seinen grünen Pfeil in der Liste, um die Änderungen zu sehen."
    m["{1} downloaded macros have a new version in Macro Hub. Click their green arrows in the list to see the changes."] := "{1} heruntergeladene Makros haben eine neue Version im Macro Hub. Klicke auf ihre grünen Pfeile in der Liste, um die Änderungen zu sehen."
    m["New version of `"{1}`" by {2}"] := "Neue Version von `"{1}`" von {2}"
    m["You changed this macro yourself - updating replaces your changes with the new version."] := "Du hast dieses Makro selbst geändert - die Aktualisierung ersetzt deine Änderungen durch die neue Version."
    m["Changes (yours → new):"] := "Änderungen (deine → neu):"
    m["Keep mine"] := "Meine behalten"
    m["`"{1}`" is updated to the new version."] := "`"{1}`" ist auf die neue Version aktualisiert."
    m["(no difference)"] := "(kein Unterschied)"
    m["Share `"{1}`" in Macro Hub"] := "`"{1}`" im Macro Hub teilen"
    m["Game (people filter and search by it, for example 4Story)"] := "Spiel (danach wird gefiltert und gesucht, z. B. 4Story)"
    m["Description (optional): what it does, for which class"] := "Beschreibung (optional): was es tut, für welche Klasse"
    m["Your nickname"] := "Dein Spitzname"
    m["Shared: the keys, delays, Run and Press settings and the application. Not shared: the toggle key and your profiles. Everyone can see and download it. Farm / AFK macros are not allowed."] := "Geteilt werden: Tasten, Verzögerungen, Ausführen- und Drücken-Einstellungen und die Anwendung. Nicht geteilt: die Umschalttaste und deine Profile. Jeder kann es sehen und herunterladen. Farm- / AFK-Makros sind nicht erlaubt."
    m["Please fill in the name, the game and your nickname."] := "Bitte gib Name, Spiel und deinen Spitznamen ein."
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
