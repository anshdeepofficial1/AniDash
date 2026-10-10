#define MyAppName "AniDash"
#define MyAppPublisher "Anshdeep Singh"
#define MyAppExeName "AniDash.exe"

[Setup]
AppId={{0516D984-72BF-47D4-BFBC-B2B8FD563479}
AppName={#MyAppName}
AppVersion=1.19.3
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\AniDash
DefaultGroupName=AniDash
OutputDir=..\..\dist
OutputBaseFilename=AniDash-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=force
CloseApplicationsFilter=AniDash.exe

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\AniDash"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\AniDash"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch AniDash"; Flags: nowait postinstall skipifsilent
