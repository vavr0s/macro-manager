; ============ embedded logo / icon ============
EnsureAssets() {
    try {
        DirCreate(AssetsDir)
        verFile := AssetsDir "\version.txt"
        cur := FileExist(verFile) ? Trim(FileRead(verFile)) : ""
        if (cur != AssetVersion || !FileExist(IconFile) || !FileExist(LogoFile) || !FileExist(SwOnFile) || !FileExist(LogoWideFile) || !FileExist(CbDarkFile) || !FileExist(DiscordFile) || !FileExist(DiscordHovFile) || !FileExist(FlagFile("de"))) {
            B64ToFile(IconB64(), IconFile)
            B64ToFile(LogoB64(), LogoFile)
            B64ToFile(SwOffB64(), SwOffFile)
            B64ToFile(SwOnB64(), SwOnFile)
            B64ToFile(LogoWideB64(), LogoWideFile)
            B64ToFile(CbDarkB64(), CbDarkFile)
            B64ToFile(CbLightB64(), CbLightFile)
            B64ToFile(DiscordB64(), DiscordFile)
            B64ToFile(DiscordHovB64(), DiscordHovFile)
            for c in LangOrder
                B64ToFile(FlagB64(c), FlagFile(c))
            for old in ["badge_main.png", "badge_dk.png", "badge_lt.png"]    ; pictures of older versions (the "!" is drawn now)
                try FileDelete(AssetsDir "\" old)
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
        SetLnkAppId(lnk, AppId())
    }
}

; ============ app identity (Windows notifications, taskbar) ============
; Windows shows a notification with the name and icon of the app's AppUserModelID. Without an own one it makes one
; from the exe - a renamed AutoHotkey, so the notice said "AutoHotkey" with its green icon. The shortcuts get the
; same id, so the taskbar still groups the running app with a pinned shortcut.
AppId() => UpdBranch = "beta" ? "VAVROS.MacroManager.Beta" : "VAVROS.MacroManager"

SetAppIdentity() {
    id := AppId()
    try DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "WStr", id)
    png := AssetsDir "\notify_" AssetVersion ".png"
    if !FileExist(png)
        try IcoToPng(IconFile, png)
    k := "HKCU\Software\Classes\AppUserModelId\" id
    try {
        RegWrite(UpdBranch = "beta" ? "Macro Manager (beta)" : "Macro Manager", "REG_SZ", k, "DisplayName")
        if FileExist(png)
            RegWrite(png, "REG_SZ", k, "IconUri")
    }
    lnk := UpdBranch = "beta" ? "Macro Manager Beta.lnk" : "Macro Manager.lnk"
    for dir in [A_Programs, A_Desktop]                         ; shortcuts made by older versions
        if FileExist(dir "\" lnk)
            SetLnkAppId(dir "\" lnk, id)
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
