; Inno Setup script for Universal Translator (built by .github/workflows/release.yml)
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
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
OutputBaseFilename=universal-translator-windows-x64-setup
OutputDir=..\dist
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=yes
UninstallDisplayIcon={app}\universal_translator.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
MinVersion=10.0

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Universal Translator"; Filename: "{app}\universal_translator.exe"
Name: "{autodesktop}\Universal Translator"; Filename: "{app}\universal_translator.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Run]
Filename: "{app}\universal_translator.exe"; Description: "{cm:LaunchProgram,Universal Translator}"; Flags: nowait postinstall skipifsilent
; Relaunch after a silent in-app update.
Filename: "{app}\universal_translator.exe"; Flags: nowait; Check: WizardSilent
