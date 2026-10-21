@echo off
setlocal
cd /d "%~dp0"
if not exist "Macro Manager.ahk" goto :missing
set "AHK=runtime64\Macro Manager Setup.exe"
if /I "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "AHK=runtime32\Macro Manager Setup.exe"
if not exist "%AHK%" goto :missing
start "" "%AHK%" "Macro Manager.ahk"
exit /b 0
:missing
echo Some files are missing. Please extract the whole ZIP first (right-click - Extract All),
echo then run this file again from the extracted folder.
pause
