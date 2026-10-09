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
        LV.Add(m["enabled"] ? "Check" : "", m["name"], m["hotkey"], (m["app"] = "" || m["type"] = "script") ? _T("(everywhere)") : m["app"], TypeLabel(m["type"]))
    LV.ModifyCol(4, "AutoHdr")                    ; last column fills the rest, so nothing stale is left on the right
    Populating := false
}
