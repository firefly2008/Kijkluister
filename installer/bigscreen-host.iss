; Inno Setup 6 script -- Bigscreen Host voor Windows 10/11 (x64)
; Bouwen: iscc /DAppVersion=6.8.2 installer\bigscreen-host.iss   (na scripts\build-installer.ps1 stap 1-3)
#ifndef AppVersion
  #define AppVersion "6.8.2"
#endif
#define AppName "Bigscreen Host"
#define AppExe "bigscreen-host.exe"

[Setup]
AppId={{6B0D5C1E-8E0B-4D53-9A61-B16C5C3EE2A7}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Plasma Bigscreen Windows-port
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE-GPL-2.0.txt
OutputDir=..\out
OutputBaseFilename=BigscreenHost-{#AppVersion}-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Snelkoppeling op het bureaublad"; Flags: unchecked
Name: "autostart"; Description: "Bigscreen automatisch starten bij aanmelden (tv-/mediacenter-pc)"; Flags: unchecked

[Files]
Source: "..\dist\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "{#AppName} nu starten"; Flags: nowait postinstall skipifsilent unchecked
