; Inno Setup script for the Balamandir School App Windows build.
; Produces a standard "Setup.exe -> Next -> Next -> Install -> Finish"
; installer: installs to Program Files, adds Start Menu + optional desktop
; shortcuts, and registers a proper uninstaller in Add/Remove Programs.
;
; Build with: ISCC.exe windows_installer.iss
; Source files come from build\windows\x64\runner\Release\ (run
; `flutter build windows --release` first).

#define MyAppName "Balamandir School App"
#define MyAppVersion "1.0.8"
#define MyAppPublisher "Balamandir School"
#define MyAppExeName "school_management_app.exe"
#define MyReleaseDir "build\windows\x64\runner\Release"

[Setup]
AppId={{8F3A2C1E-7B4D-4E9A-9C2F-1A5D6E8B3F70}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=BalamandirSchoolApp-Setup-v{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft Visual C++ runtime next to the app, so it starts even on PCs
; that never installed the VC++ Redistributable.
Source: "windows_runtime\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
