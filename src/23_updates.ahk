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
    if (A_TickCount >= apiPause)
        info := HttpReq("https://api.github.com/repos/" UpdRepo "/contents/version.json?ref=" UpdBranch, hdr, &st, &et)
    if (st = 403 || st = 429)
        apiPause := A_TickCount + 1800000          ; 30 minutes (the limit resets within the hour)
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
