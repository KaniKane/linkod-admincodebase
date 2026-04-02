; LINKod Admin Windows Installer - Inno Setup Script
;
; This script creates a professional Windows installer that:
; - Installs the Flutter app to Program Files
; - Installs the packaged backend EXE alongside the app
; - Creates Start Menu and Desktop shortcuts
; - Sets up writable directories for logs in LocalAppData
; - Does NOT require any manual post-install steps
;
; BUILD INSTRUCTIONS FOR DEVELOPER:
; 1. Build Flutter Windows app: flutter build windows --release
; 2. Build backend EXE: pyinstaller --clean linkod_admin_backend.spec
; 3. Update VERSION and paths below if needed
; 4. Compile this script with Inno Setup Compiler (ISCC.exe)
; 5. Output: LINKod_Admin_Setup.exe
;
; REQUIREMENTS:
; - Inno Setup 6.2 or later: https://jrsoftware.org/isinfo.php
; - Flutter Windows build output in build\windows\x64\runner\Release\
; - Backend EXE in backend\dist\linkod_admin_backend\

#define MyAppName "LINKod Admin"
#define MyAppVersion "1.0.4"
#define MyAppPublisher "LINKod"
#define MyAppExeName "linkod_admin.exe"
#define MyBackendExeName "linkod_admin_backend.exe"

[Setup]
; App metadata
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
; Output configuration
OutputDir=..\installer\output
OutputBaseFilename=LINKod_Admin_Setup_{#MyAppVersion}
Compression=lzma
SolidCompression=yes
; Installation behavior
WizardStyle=modern
; Privileges (admin required for Program Files installation)
PrivilegesRequired=admin
; Icon and images
; NOTE: For the installer icon, create linkod_logo.ico from linkod_logo.png
; You can use an online converter or ImageMagick:
;   magick convert assets/img/logo/linkod_logo.png -define icon:auto-resize=256,128,64,48,32,16 installer/linkod_logo.ico
SetupIconFile=..\assets\img\logo\linkod_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Minimum Windows version (Windows 10)
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode

[Dirs]
; Create log directory in LocalAppData during install
; Note: This runs as admin, so we use a custom step to create user dirs

[Files]
; === FLUTTER APP FILES ===
; Main application executable and DLLs
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs

; === BACKEND FILES ===
; Packaged Python backend EXE and all its dependencies
; The backend runs as a companion process managed by the Flutter app
Source: "..\backend\dist\linkod_admin_backend\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs

; === CONFIGURATION FILES ===
; Firebase credentials (if bundling them - otherwise configure separately)
; Uncomment and adjust path if you want to bundle Firebase credentials:
; Source: "..\backend\linkod-db-firebase-adminsdk-fbsvc-db4270d732.json"; DestDir: "{app}\backend"; Flags: ignoreversion

; === ADDITIONAL ASSETS ===
; App icon for shortcuts (create .ico from logo.png if needed)
; Source: "..\assets\img\logo\linkod_logo.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu shortcut
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; Desktop shortcut (optional, user can uncheck)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Launch application after install (optional - user can uncheck)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up backend log files on uninstall
; Note: Only removes the app directory; LocalAppData logs remain for troubleshooting
Type: filesandordirs; Name: "{app}\backend\logs"

[Registry]
; Optional: Add to PATH or registry entries if needed
; Currently not required as the app is self-contained

[Code]
// =============================================================================
// POST-INSTALLATION: CREATE USER DATA DIRECTORIES
// =============================================================================

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    // Log directory is created by the app/backend on first run
    // We don't create it here because:
    // 1. This runs as admin, not the end user
    // 2. The backend creates its own log directory on startup
    Log('Installation complete. Backend will create log directories on first run.');
  end;
end;

// =============================================================================
// UNINSTALLATION: CONFIRMATION
// =============================================================================

function InitializeUninstall(): Boolean;
begin
  Result := true;
  // Note: Backend may continue running after uninstall if it was started
  // This is acceptable - it will be cleaned up on next reboot or can be manually killed
end;

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

function GetUninstallRegPath(): String;
begin
  if IsAdminInstallMode then
    Result := 'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppName}_is1'
  else
    Result := 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppName}_is1';
end;
