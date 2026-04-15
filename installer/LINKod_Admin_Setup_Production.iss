; LINKod Admin - Production Windows Installer (Inno Setup)
; This script is dedicated to production packaging and does not replace legacy .iss files.

#define MyAppName "LINKod Admin"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "LINKod"
#define MyAppExeName "linkod_admin.exe"
#define MyBackendExeName "linkod_admin_backend.exe"

#define FlutterReleaseDir "..\\build\\windows\\x64\\runner\\Release"
#define BackendDistDir "..\\backend\\dist\\linkod_admin_backend"

#ifnexist FlutterReleaseDir + "\\" + MyAppExeName
  #error "Flutter release binary is missing. Build with: flutter build windows --release"
#endif

#ifnexist BackendDistDir + "\\" + MyBackendExeName
  #error "Backend binary is missing. Build with: pyinstaller --clean linkod_admin_backend.installer.spec"
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir=..\installer\output
OutputBaseFilename=LINKod_Admin_Setup_{#MyAppVersion}
Compression=lzma
SolidCompression=yes

SetupIconFile=..\assets\img\logo\linkod_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter app runtime
Source: "{#FlutterReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Packaged Python backend runtime
Source: "{#BackendDistDir}\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\backend\logs"
