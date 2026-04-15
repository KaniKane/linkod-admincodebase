# LINKod Admin Windows Installer Guide (Inno Setup)

This guide documents the current production flow used in the admin codebase to build:

1. Flutter Windows frontend
2. Packaged Python backend (PyInstaller)
3. Final Windows installer (.exe) using Inno Setup

It is based on the current production project files:

- `installer/LINKod_Admin_Setup_Production.iss` (main installer script)
- `backend/linkod_admin_backend.installer.spec` (PyInstaller spec)
- `scripts/build_release.ps1` (automation script)

## 1. Scope and Output

From one build run, you should get:

- Frontend build: `build/windows/x64/runner/Release/linkod_admin.exe`
- Backend package: `backend/dist/linkod_admin_backend/linkod_admin_backend.exe`
- Installer: `installer/output/LINKod_Admin_Setup_<version>.exe`

## 2. Prerequisites

Install these tools on the build machine:

- Flutter SDK (with Windows desktop support)
- Visual Studio 2022 with "Desktop development with C++"
- Python 3.10+
- PyInstaller (`pip install pyinstaller`)
- Inno Setup 6.2+ (ISCC compiler)

Quick checks:

```powershell
flutter --version
python --version
pyinstaller --version
"${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /?
```

## 3. Important Project Files

### Installer script

`installer/LINKod_Admin_Setup_Production.iss` currently does the following:

- installs app to Program Files (`{autopf}`)
- copies Flutter release files from `build/windows/x64/runner/Release`
- copies backend package from `backend/dist/linkod_admin_backend`
- creates Start Menu/Desktop shortcuts
- writes installer output to `installer/output`

### Backend build spec

`backend/linkod_admin_backend.installer.spec` currently:

- uses `launcher.py` as PyInstaller entrypoint
- builds in `onedir` mode for stable startup
- includes config files such as `config/audience_rules.json`
- bundles required hidden imports for FastAPI/Uvicorn/Firebase stack

### Automation script

`scripts/build_release.ps1` currently:

- validates toolchain
- builds Flutter release
- builds backend with PyInstaller
- compiles Inno installer with ISCC

## 4. Build Frontend (Flutter Windows)

Run from `linkod-admincodebase` root:

```powershell
cd d:\Desktop1\linkod-admincodebase
flutter pub get
flutter build windows --release
```

Verify:

```powershell
Test-Path .\build\windows\x64\runner\Release\linkod_admin.exe
```

## 5. Build Backend (PyInstaller)

Run from project root:

```powershell
cd d:\Desktop1\linkod-admincodebase\backend
pip install -r requirements.txt
pip install pyinstaller
pyinstaller --clean linkod_admin_backend.installer.spec
```

Verify:

```powershell
Test-Path .\dist\linkod_admin_backend\linkod_admin_backend.exe
```

## 6. Compile Installer (Inno Setup)

Run from project root (`linkod-admincodebase`):

```powershell
cd d:\Desktop1\linkod-admincodebase
"${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" .\installer\LINKod_Admin_Setup_Production.iss
```

If Inno Setup is installed in Program Files instead of Program Files (x86), use:

```powershell
"${env:ProgramFiles}\Inno Setup 6\ISCC.exe" .\installer\LINKod_Admin_Setup_Production.iss
```

Output should appear in:

- `installer/output/LINKod_Admin_Setup_<version>.exe`

## 7. One-Command Build (Recommended Existing Flow)

Use the existing automation script:

```powershell
cd d:\Desktop1\linkod-admincodebase
.\scripts\build_release.ps1
```

Useful options:

```powershell
.\scripts\build_release.ps1 -Clean
.\scripts\build_release.ps1 -SkipBackend
.\scripts\build_release.ps1 -SkipFlutter
.\scripts\build_release.ps1 -SkipInstaller
```

## 8. Versioning and Release Hygiene

Before final release build:

1. Update installer version in `installer/LINKod_Admin_Setup_Production.iss`:
   - `#define MyAppVersion "x.y.z"`
2. Confirm expected output filename pattern:
   - `OutputBaseFilename=LINKod_Admin_Setup_{#MyAppVersion}`
3. Rebuild using `build_release.ps1`

## 9. Smoke Test on Clean Windows Machine

After generating the installer:

1. Install using generated setup exe.
2. Launch LINKod Admin from shortcut.
3. Confirm app opens and backend autostarts.
4. Check backend health endpoint:

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8000/health -Method GET
```

5. If issues occur, inspect logs:

```powershell
explorer "$env:LocalAppData\LINKodAdmin\Backend\logs"
```

## 10. Troubleshooting Quick Notes

### ISCC not found

Install Inno Setup 6 and retry with the full path to `ISCC.exe`.

### Flutter build fails

- ensure Windows desktop dependencies are installed
- run `flutter doctor -v`

### Backend EXE missing

- run build from `backend` directory
- ensure spec file name is exact: `linkod_admin_backend.installer.spec`

### Installer compile fails due to missing source files

Most failures happen because one of these does not exist yet:

- `build/windows/x64/runner/Release/linkod_admin.exe`
- `backend/dist/linkod_admin_backend/linkod_admin_backend.exe`

Build frontend and backend first, then compile Inno Setup.

## 11. Notes About Legacy Installer Files

The `installer` folder also contains older `.iss` files (for example `desktop_inno_script.iss` and `linkod_admin_setup_2.iss`).

For current packaging flow, use:

- `installer/LINKod_Admin_Setup_Production.iss`

This avoids path/version drift across multiple installer scripts.
