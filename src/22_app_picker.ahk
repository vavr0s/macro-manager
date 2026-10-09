; ============ application picker ============
; returns the chosen exe name (or `cur` when cancelled)
PickApp(owner, cur) {
    r := Mb(_T("Use one of the currently running applications?`n`nYes = choose from a list`nNo = browse for the .exe file"), _T("Select application"), "YesNoCancel Icon?")
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
        MsgBox _T("No running applications found - choose the file instead."), _T("Select application"), 64
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
