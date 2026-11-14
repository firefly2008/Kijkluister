; Inno Setup 6 script -- Kijkluister voor Windows 10/11 (x64)
; Zelfde AppId als "Bigscreen Host" (tot 3.7), zodat over de oude versie heen wordt geinstalleerd
; Bouwen: iscc /DAppVersion=6.8.2 installer\bigscreen-host.iss   (na scripts\build-installer.ps1 stap 1-3)
#ifndef AppVersion
  #define AppVersion "6.8.2"
#endif
#define AppName "Kijkluister"
#define AppExe "Kijkluister.exe"

[Setup]
AppId={{6B0D5C1E-8E0B-4D53-9A61-B16C5C3EE2A7}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Kijkluister (gebaseerd op KDE Plasma Bigscreen)
DefaultDirName={autopf}\{#AppName}
; Niet de oude map "Bigscreen Host" hergebruiken: vanaf 3.8.3 heet de programmamap Kijkluister
UsePreviousAppDir=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE-GPL-2.0.txt
OutputDir=..\out
OutputBaseFilename=Kijkluister-{#AppVersion}-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile=..\assets\kijkluister.ico
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Snelkoppeling op het bureaublad"; Flags: unchecked
Name: "autostart"; Description: "Kijkluister automatisch starten bij aanmelden (tv-/mediacenter-pc)"; Flags: unchecked

[InstallDelete]
; Tot en met 3.8.8 zaten MPC-HC en ffmpeg in de installer; nu haalt Kijkluister ze zelf op
Type: filesandordirs; Name: "{app}\mpc-hc"
Type: filesandordirs; Name: "{app}\ffmpeg"
; Overblijfselen van de oude naam "Bigscreen Host"
Type: files; Name: "{app}\bigscreen-host.exe"
Type: filesandordirs; Name: "{autopf}\Bigscreen Host"
Type: files; Name: "{userstartup}\Bigscreen Host.lnk"
Type: files; Name: "{autodesktop}\Bigscreen Host.lnk"
Type: filesandordirs; Name: "{autoprograms}\Bigscreen Host"
Type: files; Name: "{autoprograms}\Bigscreen Host.lnk"

[Files]
Source: "..\dist\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: autostart

[Run]
Filename: "{app}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Microsoft Visual C++ runtime installeren..."; Flags: waituntilterminated skipifdoesntexist
Filename: "{app}\{#AppExe}"; Description: "{#AppName} nu starten"; Flags: nowait postinstall skipifsilent unchecked
; Bijwerken vanuit Kijkluister zelf: na de stille installatie meteen weer starten
Filename: "{app}\{#AppExe}"; Flags: nowait runasoriginaluser; Check: IsRelaunch

[Code]
function IsRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
