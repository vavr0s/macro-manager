; Macro Manager setup .exe - compiled by tools/package.py with Ahk2Exe (base = the bundled AutoHotkey64).
; It unpacks the app script + runtime into a temp folder, runs the same setup dialog as the .bat and cleans up.
#Requires AutoHotkey v2.0
#NoTrayIcon
;@Ahk2Exe-SetName {NAME}
;@Ahk2Exe-SetDescription {NAME}
;@Ahk2Exe-SetProductName {NAME}
;@Ahk2Exe-SetCompanyName vavr0s
;@Ahk2Exe-SetVersion {VERSION}
;@Ahk2Exe-SetOrigFilename {EXE}
;@Ahk2Exe-SetMainIcon app.ico
;@Ahk2Exe-UpdateManifest 1

; admin right away: the app would restart itself elevated anyway, and that restart must not outlive the temp folder
if !A_IsAdmin {
    try Run '*RunAs "' A_ScriptFullPath '"'
    ExitApp
}
dir := A_Temp "\MacroManagerSetup-" A_TickCount
try {
    DirCreate dir "\runtime64"
    FileInstall "pkg\Macro Manager.ahk", dir "\Macro Manager.ahk", 1
    FileInstall "pkg\runtime64\Macro Manager Setup.exe", dir "\runtime64\Macro Manager Setup.exe", 1
    FileInstall "pkg\runtime64\AutoHotkey-license.txt", dir "\runtime64\AutoHotkey-license.txt", 1
    RunWait '"' dir '\runtime64\Macro Manager Setup.exe" "' dir '\Macro Manager.ahk"', dir
} catch as e {
    MsgBox "Setup failed:`n" e.Message, "{NAME}", "Icon!"
}
try DirDelete dir, true
