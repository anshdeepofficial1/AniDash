[Setup]
AppId={{032B25E0-0713-4B9E-B19E-B23B15B9A60C}}
AppName=AniDash
AppVersion=1.18.6
AppPublisher=Anshdeep Singh
DefaultDirName={autopf}\AniDash
DefaultGroupName=AniDash
OutputDir=build\windows\x64\installer
OutputBaseFilename=AniDash-v1.18.6-Setup
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\AniDash.exe
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AniDash"; Filename: "{app}\AniDash.exe"; IconFilename: "{app}\AniDash.exe"
Name: "{autodesktop}\AniDash"; Filename: "{app}\AniDash.exe"; Tasks: desktopicon; IconFilename: "{app}\AniDash.exe"

[Run]
Filename: "{app}\AniDash.exe"; Description: "{cm:LaunchProgram,AniDash}"; Flags: nowait postinstall skipifsilent
