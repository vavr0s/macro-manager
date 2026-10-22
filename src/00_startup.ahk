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
AssetVersion := "12"    ; bump when the embedded logo/icon change
AppVersion := "1.23"     ; bump on every release (must match version.json in the GitHub repo)
UpdAvail := false       ; a newer version exists (icon in the banner turns green)
UpdInfo := Map()
UpdRepo := "vavr0s/macro-manager"
UpdBranch := "main"      ; the test (beta) build uses "beta"
UpdateUrl := "https://raw.githubusercontent.com/" UpdRepo "/" UpdBranch "/version.json"      ; fallback (cached by GitHub for ~5 min)
UpdEtag := ""            ; GitHub API answers "not modified" for free when nothing changed
UpdBody := ""
; release notes of THIS version, shown in Help (English + translations below; written by tools/set_notes.py from
; tools/notes.json). No double quotes here.
ReleaseNotes := "- New: Macro Hub, a shared library of macros. Open it with the Macro Hub button and it docks to the main window. You can browse other players' macros or your own, filter by game, search by name, game or author, sort, and see what a macro does (keys, delays, sequence) before you download it. Downloading adds the macro to your active profile.`n- Share a macro with the share icon in its row (you pick its game). When you change a macro you shared, the app asks whether to update it in Macro Hub. Its ratings and downloads stay.`n- When the author updates a macro you downloaded, you get a notice and its arrow in the list turns green. Click it to see what changed, then take the new version or keep yours.`n- Rate macros with stars and report bad ones. Macros checked by the moderator have a gold tick and come first. Downloaded macros can't be shared again unchanged, and the same macro can't be in Macro Hub twice.`n- Without internet, Macro Hub shows No connection and tries again by itself. Changes made offline are sent once you are back online.`n- App updates now come through the Macro Hub server, so a new version shows up reliably even when several PCs share one internet connection."
; the same notes in the other languages (keep this on one line - tools/set_notes.py rewrites it)
ReleaseNotesL := Map("cs", "- Novinka: Macro Hub, sdílená knihovna maker. Otevře se tlačítkem Macro Hub a připojí se k hlavnímu oknu. Můžeš procházet makra ostatních hráčů nebo svoje, filtrovat podle hry, hledat podle názvu, hry nebo autora, řadit a ještě před stažením vidět, co makro dělá (klávesy, prodlevy, sekvenci). Stažené makro se přidá do aktivního profilu.`n- Makro nasdílíš ikonou sdílení v jeho řádku (vybereš, ke které hře patří). Když sdílené makro upravíš, aplikace se zeptá, jestli ho aktualizovat i v Macro Hubu. Hodnocení i počet stažení zůstanou.`n- Když autor aktualizuje makro, které sis stáhl, dostaneš upozornění a jeho šipka v seznamu zezelená. Po kliknutí uvidíš, co se změnilo, a buď převezmeš novou verzi, nebo si necháš svou.`n- Makra můžeš hodnotit hvězdičkami a špatná nahlásit. Makra zkontrolovaná moderátorem mají zlatou fajfku a jsou na začátku. Stažené makro nejde znovu sdílet beze změny a stejné makro nemůže být v Macro Hubu dvakrát.`n- Bez internetu ukáže Macro Hub nápis Bez připojení a sám to zkouší znovu. Změny udělané offline se odešlou, jakmile budeš zase online.`n- Aktualizace aplikace teď chodí přes server Macro Hubu, takže se nová verze spolehlivě ukáže, i když je víc počítačů na jednom připojení.", "pl", "- Nowość: Macro Hub, wspólna biblioteka makr. Otwierasz go przyciskiem Macro Hub i dokuje się do głównego okna. Możesz przeglądać makra innych graczy lub swoje, filtrować według gry, szukać po nazwie, grze lub autorze, sortować i jeszcze przed pobraniem zobaczyć, co makro robi (klawisze, opóźnienia, sekwencja). Pobrane makro trafia do aktywnego profilu.`n- Makro udostępnisz ikoną udostępniania w jego wierszu (wybierasz, do jakiej gry należy). Gdy zmienisz udostępnione makro, aplikacja zapyta, czy zaktualizować je także w Macro Hub. Oceny i liczba pobrań zostają.`n- Gdy autor zaktualizuje pobrane przez ciebie makro, dostaniesz powiadomienie, a jego strzałka na liście zmieni kolor na zielony. Kliknij ją, aby zobaczyć zmiany, i przyjmij nową wersję albo zostaw swoją.`n- Makra możesz oceniać gwiazdkami i zgłaszać złe. Makra sprawdzone przez moderatora mają złoty znaczek i są na początku. Pobranego makra nie można ponownie udostępnić bez zmian, a to samo makro nie może być w Macro Hub dwa razy.`n- Bez internetu Macro Hub pokazuje napis Brak połączenia i sam próbuje ponownie. Zmiany zrobione offline zostaną wysłane, gdy znów będziesz online.`n- Aktualizacje aplikacji przychodzą teraz przez serwer Macro Hub, więc nowa wersja pojawia się niezawodnie, nawet gdy kilka komputerów korzysta z jednego łącza.", "de", "- Neu: Macro Hub, eine gemeinsame Makro-Bibliothek. Du öffnest ihn mit der Schaltfläche Macro Hub, er dockt am Hauptfenster an. Du kannst Makros anderer Spieler oder deine eigenen durchsuchen, nach Spiel filtern, nach Name, Spiel oder Autor suchen, sortieren und schon vor dem Herunterladen sehen, was ein Makro tut (Tasten, Pausen, Ablauf). Heruntergeladene Makros landen im aktiven Profil.`n- Ein Makro teilst du mit dem Teilen-Symbol in seiner Zeile (du wählst das Spiel). Änderst du ein geteiltes Makro, fragt die App, ob es auch im Macro Hub aktualisiert werden soll. Bewertungen und Downloads bleiben erhalten.`n- Aktualisiert der Autor ein Makro, das du heruntergeladen hast, bekommst du eine Meldung und sein Pfeil in der Liste wird grün. Klick darauf, um die Änderungen zu sehen, und übernimm die neue Version oder behalte deine.`n- Makros kannst du mit Sternen bewerten und schlechte melden. Vom Moderator geprüfte Makros haben einen goldenen Haken und stehen oben. Heruntergeladene Makros lassen sich unverändert nicht erneut teilen, und dasselbe Makro kann nicht zweimal im Macro Hub sein.`n- Ohne Internet zeigt Macro Hub Keine Verbindung an und versucht es selbst erneut. Offline gemachte Änderungen werden gesendet, sobald du wieder online bist.`n- App-Updates kommen jetzt über den Macro-Hub-Server, sodass eine neue Version zuverlässig erscheint, auch wenn sich mehrere PCs eine Internetverbindung teilen.")
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
Main := Gui(, "ComboCrown")
Main.SetFont("s9", "Segoe UI")
try {
    Main.AddPicture("x10 y8 w820 h72", LogoWideFile)      ; black rounded banner with the logo
    Main.SetFont("s16 bold cD0AE6B", "Segoe UI")
    ttl := Main.AddText("x100 y29 w200 BackgroundTrans", "ComboCrown")
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
    A_IconTip := "ComboCrown v" AppVersion
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
