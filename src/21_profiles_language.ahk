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
