; Inno Setup script -> builds IpBump-Setup-<version>.exe
; Get Inno Setup (free): https://jrsoftware.org/isdl.php

#define AppName "IpBump"
#define PublishDir "..\IpBump\bin\Release\net8.0-windows\win-x64\publish"
; The version is set in one place, IpBump.csproj, and read back from the built exe
#define AppVersion GetStringFileInfo(AddBackslash(SourcePath) + PublishDir + "\IpBump.exe", "ProductVersion")

[Setup]
AppId={{7C1B6E52-4E0B-4C59-9E1A-2B9B6F3B8D21}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=output
OutputBaseFilename=IpBump-Setup-{#AppVersion}
SetupIconFile=..\IpBump\Assets\IpBump.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\IpBump.exe
UninstallDisplayName={#AppName}

[Tasks]
Name: "autostart"; Description: "Start IpBump automatically for every user at sign-in"; GroupDescription: "Startup:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; The whole publish folder: IpBump.exe plus the .NET runtime it carries with it
Source: "{#PublishDir}\*"; DestDir: "{app}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\IpBump.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\IpBump.exe"; Tasks: desktopicon

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "IpBump"; \
  ValueData: """{app}\IpBump.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
; register + start the background service (runs as SYSTEM, does the actual IP change)
Filename: "{app}\IpBump.exe"; Parameters: "--install-service"; Flags: runhidden waituntilterminated; StatusMsg: "Installing service..."
; start the tray app as the normal user (NOT elevated), so settings go to that user's profile
Filename: "{app}\IpBump.exe"; Description: "Launch IpBump now"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{app}\IpBump.exe"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveService"
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im IpBump.exe"; Flags: runhidden waituntilterminated; RunOnceId: "KillTray"

[Code]
// When upgrading, stop the running service, tray apps and agent servers so the files can be replaced.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  R: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop IpBumpSvc', '', SW_HIDE, ewWaitUntilTerminated, R);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im IpBump.exe', '', SW_HIDE, ewWaitUntilTerminated, R);
  Sleep(1500);
  Result := '';
end;
