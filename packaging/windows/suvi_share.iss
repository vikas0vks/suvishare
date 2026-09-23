; Suvi Share — Windows installer (Inno Setup 6)
;
; Build the app first, then compile this script:
;   flutter build windows --release
;   iscc packaging\windows\suvi_share.iss
;
; Or just run packaging\windows\build.ps1, which does both.
; Output lands in packaging\windows\output\.

#define AppName        "Suvi Share"
#define AppPublisher   "vikas0vks"
#define AppExeName     "suvi_share.exe"
#define AppUrl         "https://github.com/vikas0vks/suvishare"
#define AppId          "{{7B4E2C10-5F1D-4A6B-9E3C-1D8A2F6B4C90}"

; Version is passed in by build.ps1 (/DAppVersion=x.y.z); fall back for a
; manual `iscc` run.
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define SourceDir "..\..\app\build\windows\x64\runner\Release"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription="{#AppName} — share files across your Wi-Fi"
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=output
OutputBaseFilename=SuviShare-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\..\LICENSE
; x64 only — Flutter dropped 32-bit Windows support.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The app creates this named mutex (windows/runner/main.cpp); Setup uses it to
; detect a running copy and ask the user to close it before install/uninstall,
; instead of failing halfway with locked files.
AppMutex=SuviShareSingleInstance
CloseApplications=yes
RestartApplications=no
; Admin, because the installer registers Windows Firewall rules. Without them
; other devices cannot reach this PC, which is the single most common cause of
; "no devices found" for every app of this kind.
PrivilegesRequired=admin
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupicon"; Description: "Start {#AppName} when I sign in"; GroupDescription: "Startup"; Flags: unchecked
Name: "firewall"; Description: "Allow {#AppName} through Windows Firewall on private networks (recommended — other devices cannot find this PC without it)"; GroupDescription: "Network"

[Files]
Source: "{#SourceDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll";         DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\data\*";        DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Pre-authorise the app so the user never sees the "Allow access?" popup.
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""Suvi Share (TCP-In)"" dir=in action=allow program=""{app}\{#AppExeName}"" enable=yes profile=private,domain protocol=TCP"; \
  Flags: runhidden waituntilterminated; Tasks: firewall; StatusMsg: "Adding Windows Firewall rules..."
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""Suvi Share (UDP-In)"" dir=in action=allow program=""{app}\{#AppExeName}"" enable=yes profile=private,domain protocol=UDP"; \
  Flags: runhidden waituntilterminated; Tasks: firewall

; Autostart goes in the *installing* user's HKCU Run key. A {userstartup}
; shortcut would land in the elevating admin's profile instead, which is why
; Inno warns about per-user areas in admin install mode.
Filename: "{sys}\reg.exe"; \
  Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""{#AppName}"" /t REG_SZ /d ""\""{app}\{#AppExeName}\"""" /f"; \
  Flags: runhidden waituntilterminated runasoriginaluser; Tasks: startupicon; StatusMsg: "Configuring startup..."

Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Suvi Share (TCP-In)"""; Flags: runhidden; RunOnceId: "DelFwTcp"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Suvi Share (UDP-In)"""; Flags: runhidden; RunOnceId: "DelFwUdp"
; [UninstallRun] has no runasoriginaluser flag. UAC elevation of the same
; account keeps the same HKCU hive, so this is correct whenever the person
; uninstalling is the person who installed — the ordinary case.
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""{#AppName}"" /f"; \
  Flags: runhidden; RunOnceId: "DelAutostart"

; Note: no [UninstallDelete] for {app}\data — every file in it is installed by
; [Files] and therefore already tracked and removed on uninstall. A wildcard
; delete of the folder holding app.so is exactly the kind of thing that can
; brick an install if it ever runs at the wrong moment.
