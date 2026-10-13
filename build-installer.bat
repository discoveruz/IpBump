@echo off
rem 1) publish IpBump with its own copy of .NET   2) wrap the folder into one installer with Inno Setup
cd /d "%~dp0"

dotnet publish IpBump\IpBump.csproj -c Release
if errorlevel 1 (echo Publish failed & pause & exit /b 1)

set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" (
  echo Inno Setup 6 not found. Install it with:  winget install JRSoftware.InnoSetup
  echo or from https://jrsoftware.org/isdl.php
  echo The app itself is in IpBump\bin\Release\net8.0-windows\win-x64\publish\
  pause & exit /b 1
)

"%ISCC%" installer\IpBump.iss
if errorlevel 1 (echo Installer build failed & pause & exit /b 1)

echo.
echo Done. The installer is in installer\output\
pause
