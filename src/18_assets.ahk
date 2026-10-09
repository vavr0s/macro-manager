; ============ embedded logo / icon ============
EnsureAssets() {
    try {
        DirCreate(AssetsDir)
        verFile := AssetsDir "\version.txt"
        cur := FileExist(verFile) ? Trim(FileRead(verFile)) : ""
        if (cur != AssetVersion || !FileExist(IconFile) || !FileExist(LogoFile) || !FileExist(SwOnFile) || !FileExist(LogoWideFile) || !FileExist(CbDarkFile) || !FileExist(BadgeMainFile) || !FileExist(DiscordFile) || !FileExist(DiscordHovFile) || !FileExist(FlagFile("de"))) {
            B64ToFile(IconB64(), IconFile)
            B64ToFile(LogoB64(), LogoFile)
            B64ToFile(SwOffB64(), SwOffFile)
            B64ToFile(SwOnB64(), SwOnFile)
            B64ToFile(LogoWideB64(), LogoWideFile)
            B64ToFile(CbDarkB64(), CbDarkFile)
            B64ToFile(CbLightB64(), CbLightFile)
            B64ToFile(BadgeMainB64(), BadgeMainFile)
            B64ToFile(BadgeDkB64(), BadgeDkFile)
            B64ToFile(BadgeLtB64(), BadgeLtFile)
            B64ToFile(DiscordB64(), DiscordFile)
            B64ToFile(DiscordHovB64(), DiscordHovFile)
            for c in LangOrder
                B64ToFile(FlagB64(c), FlagFile(c))
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
    }
}
