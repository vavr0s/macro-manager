# Starts an isolated, non-admin test copy of a build (own folder, registry MacroManagerTest).
# -Fresh rebuilds the folder; -Ini FILE uses that macros.ini (UTF-8 text, saved as UTF-16 like the app does).
# Never start the installed app from here - see tools/test/README.txt.
param([string]$Build, [string]$Dir, [switch]$Fresh, [string]$Ini = '')
$utf8 = New-Object Text.UTF8Encoding $false
Get-CimInstance Win32_Process -Filter "Name='MMTest.exe'" | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 300
if ($Fresh -and (Test-Path $Dir)) { Remove-Item -Recurse -Force $Dir }
New-Item -ItemType Directory -Force "$Dir\config\scripts" | Out-Null
$s = [IO.File]::ReadAllText($Build, $utf8)
$s = $s.Replace("if !A_IsAdmin {", "if false {").Replace('Software\MacroManager"', 'Software\MacroManagerTest"').Replace('Uninstall\MacroManager"', 'Uninstall\MacroManagerTest"').Replace('Software\MacroManagerBeta"', 'Software\MacroManagerTest"').Replace('Uninstall\MacroManagerBeta"', 'Uninstall\MacroManagerTest"')
[IO.File]::WriteAllText("$Dir\Macro Manager.ahk", $s, $utf8)
Copy-Item -Force "C:\claude\setup-runtime\runtime64\Macro Manager Setup.exe" "$Dir\MMTest.exe"
New-Item -ItemType File -Force "$Dir\config\.installed" | Out-Null
if ($Ini) {
    $t = [IO.File]::ReadAllText($Ini).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText("$Dir\config\macros.ini", $t, [Text.Encoding]::Unicode)
}
$p = Start-Process "$Dir\MMTest.exe" -ArgumentList "`"$Dir\Macro Manager.ahk`"" -PassThru
"started pid $($p.Id)"
