#define MyAppName "AniDash"
#define MyAppPublisher "Anshdeep Singh"
#define MyAppExeName "AniDash.exe"

[Setup]
AppId={{36E49B50-7D47-4D95-9A79-5DC6274C1871}
AppName={#MyAppName}
AppVersion=1.17.0
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
