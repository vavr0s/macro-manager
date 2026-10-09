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
        MsgBox _T("Dragging the macro out failed:`n{1}", e.Message), "Macro Manager", 48
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
