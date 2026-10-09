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
AssetVersion := "10"    ; bump when the embedded logo/icon change
AppVersion := "1.17"     ; bump on every release (must match version.json in the GitHub repo)
UpdAvail := false       ; a newer version exists (icon in the banner turns green)
UpdInfo := Map()
UpdRepo := "vavr0s/macro-manager"
UpdBranch := "main"      ; the test (beta) build uses "beta"
UpdateUrl := "https://raw.githubusercontent.com/" UpdRepo "/" UpdBranch "/version.json"      ; fallback (cached by GitHub for ~5 min)
UpdEtag := ""            ; GitHub API answers "not modified" for free when nothing changed
UpdBody := ""
; release notes of THIS version (shown in Help; also used as the text of the update prompt). No double quotes here.
ReleaseNotes := "- Minor fixes"
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
Main := Gui(, "Macro Manager")
Main.SetFont("s9", "Segoe UI")
try {
    Main.AddPicture("x10 y8 w820 h72", LogoWideFile)      ; black rounded banner with the logo
    Main.SetFont("s16 bold cD0AE6B", "Segoe UI")
    ttl := Main.AddText("x100 y29 w200 BackgroundTrans", "Macro Manager")
    Roles[ttl.Hwnd] := "skip"
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
    A_IconTip := "Macro Manager v" AppVersion
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
verTxt := AddHint(Main, "x740 y+4 w90 Center", "v" AppVersion)

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
