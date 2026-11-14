Test copy of the app (not shipped). From the repo root:

  python tools/build.py T.ahk
  tools\test\mmrun.ps1 -Build T.ahk -Dir DIR -Fresh [-Ini my.ini]     isolated, non-admin, registry MacroManagerTest
  tools\test\win.ps1 move 100 100 | click X Y [-Double] | key VK | cap OUT.png

Afterwards: stop MMTest.exe, delete DIR and the registry keys HKCU\Software\MacroManagerTest and
HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MacroManagerTest.
The test copy shares the real Start menu / desktop shortcuts and the notification id of the stable app (registry
writes from Claude's shell stay in its own view). Never start the installed app from Claude's shell.
