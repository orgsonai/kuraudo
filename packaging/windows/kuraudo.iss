#ifndef MyAppVersion
  #define MyAppVersion "0.4.4"
#endif

#define MyAppName "Kuraudo"
#define MyAppPublisher "Zero to Ship"
#define MyAppExeName "kuraudo.exe"

[Setup]
AppId={{DC3293D8-2694-4B86-8B21-197F70F94B11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Kuraudo
DefaultGroupName=Kuraudo
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=Kuraudo-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Kuraudo"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Kuraudo"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,Kuraudo}"; Flags: nowait postinstall skipifsilent
