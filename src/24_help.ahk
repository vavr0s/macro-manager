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
