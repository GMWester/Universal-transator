; Inno Setup script for Universal Translator (built by .github/workflows/release.yml)
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\" + Arch + "\runner\Release"
#endif

[Setup]
AppId={{6F1B7C2A-3E64-4C8B-9A51-2D7E0B5C9F31}
AppName=Universal Translator
AppVersion={#AppVersion}
AppPublisher=GMWester
AppPublisherURL=https://github.com/GMWester/Universal-transator
DefaultDirName={localappdata}\Programs\Universal Translator
DefaultGroupName=Universal Translator
PrivilegesRequired=lowest
#ifdef Full
OutputBaseFilename=universal-translator-windows-{#Arch}-full-setup
DiskSpanning=no
#else
OutputBaseFilename=universal-translator-windows-{#Arch}-setup
#endif
OutputDir=..\dist
#ifdef Full
Compression=lzma2/normal
#else
Compression=lzma2/max
#endif
SolidCompression=yes
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
CloseApplications=yes
RestartApplications=yes
UninstallDisplayIcon={app}\universal_translator.exe
; Portable mode: no uninstaller, no registry entries, no shortcuts
Uninstallable=not IsPortable
CreateUninstallRegKey=not IsPortable
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
MinVersion=10.0

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef Full
; Offline dictionaries + translation model (full installer only)
Source: "{#DataDir}\*"; DestDir: "{app}\offline-data"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{group}\Universal Translator"; Filename: "{app}\universal_translator.exe"; Check: not IsPortable
Name: "{autodesktop}\Universal Translator"; Filename: "{app}\universal_translator.exe"; Tasks: desktopicon; Check: not IsPortable

[Tasks]
Name: "portable"; Description: "Portable mode: keep dictionaries, models and settings in this folder (for USB sticks; no uninstaller or shortcuts)"; Flags: unchecked
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[INI]
; The app switches to portable mode when portable.txt exists next to it.
Filename: "{app}\portable.txt"; Section: "UniversalTranslator"; Key: "portable"; String: "1"; Tasks: portable

[Run]
Filename: "{app}\universal_translator.exe"; Description: "{cm:LaunchProgram,Universal Translator}"; Flags: nowait postinstall skipifsilent
; Relaunch after a silent in-app update.
Filename: "{app}\universal_translator.exe"; Flags: nowait; Check: WizardSilent

[Code]
function IsPortable: Boolean;
begin
  Result := WizardIsTaskSelected('portable');
end;
