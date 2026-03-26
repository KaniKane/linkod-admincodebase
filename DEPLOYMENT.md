# LINKod Admin - Final Windows Deployment Guide

## Overview

This document describes the final deployment architecture for the LINKod Admin desktop application on Windows.

**Deployment Model:**
- **Flutter Windows desktop app** - The main UI application
- **Packaged Python FastAPI backend** - Self-contained EXE (no Python required on target machine)
- **App-managed backend startup** - Flutter app starts backend automatically when needed
- **Inno Setup installer** - Professional Windows installer for end users

**Key Principle:** The end user only runs the app. No manual Python, PowerShell, CMD, or backend management required.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     LINKod Admin (Flutter)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Startup Flow:                                          │   │
│  │  1. Check http://127.0.0.1:8000/health                 │   │
│  │  2. If healthy → continue to LoginScreen               │   │
│  │  3. If not → start backend/linkod_admin_backend.exe    │   │
│  │  4. Poll until healthy (max 20 seconds)                │   │
│  │  5. If timeout → show error dialog with retry/logs      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ localhost:8000
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              LINKod Admin Backend (FastAPI + Uvicorn)           │
│                    Packaged as Windows EXE                      │
│  - AI text refinement (/refine)                                 │
│  - Audience recommendation (/recommend-audiences)              │
│  - Push notifications (/send-account-approval)                   │
│  - Logs to: %LocalAppData%\LINKodAdmin\Backend\logs              │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Locations

### Installation Directory (Read-Only)
```
C:\Program Files\LINKod Admin\              (or user-selected directory)
├── linkod_admin.exe                         (Flutter app)
├── *.dll                                    (Flutter dependencies)
├── data\                                    (Flutter assets)
└── backend\                                (Packaged Python backend)
    ├── linkod_admin_backend.exe             (Backend launcher)
    ├── config\audience_rules.json           (Audience rules config)
    └── ...                                  (Other bundled files)
```

### Writable Data Locations
```
%LocalAppData%\LINKodAdmin\Backend\logs\     (Backend logs)
    ├── backend_20240115_143022.log
    ├── backend_20240115_143522.log
    └── startup_error.txt                    (If startup fails)
```

---

## Development vs Production Mode

| Mode | Detection | Backend Management |
|------|-----------|-------------------|
| **Development** | `kDebugMode` or `kProfileMode` | Manual - developer runs `python main.py` or `uvicorn main:app` |
| **Production** | `kReleaseMode` (default) | Auto - Flutter starts packaged backend EXE |
| **Force Production** | `LINKOD_FORCE_PROD=true` env var | Can test production mode in debug builds |

### Switching Modes

**To test production mode in debug:**
```dart
// In lib/main.dart, set:
const bool forceProductionMode = true;
```

Or use environment variable:
```bash
flutter run --dart-define=LINKOD_FORCE_PROD=true
```

---

## Build Instructions

### Prerequisites

1. **Flutter SDK** (3.19.0 or later)
2. **Python** (3.10 or later) - for building backend only
3. **PyInstaller** - `pip install pyinstaller`
4. **Inno Setup 6.2+** - https://jrsoftware.org/isinfo.php

### Step 1: Build Flutter App

```powershell
# Navigate to project root
cd d:\GitHub\linkod_admin\linkod-admincodebase

# Get dependencies
flutter pub get

# Build Windows release
flutter build windows --release

# Output:
# build\windows\x64\runner\Release\linkod_admin.exe
```

### Step 2: Build Backend

```powershell
# Navigate to backend directory
cd d:\GitHub\linkod_admin\linkod-admincodebase\backend

# Activate virtual environment (if using)
# .\..\.venv\Scripts\Activate.ps1

# Install PyInstaller if not already
pip install pyinstaller

# Build the EXE
pyinstaller --clean linkod_admin_backend.spec

# Output:
# dist\linkod_admin_backend\linkod_admin_backend.exe
```

**Note:** First build may take 2-5 minutes. Subsequent builds are faster.

### Step 3: Build Installer

```powershell
# Using Inno Setup command line (ISCC.exe)
# Or open the .iss file in Inno Setup Compiler GUI

iscc installer\LINKod_Admin_Setup.iss

# Output:
# installer\output\LINKod_Admin_Setup_1.0.0.exe
```

### One-Step Build Script

Use the provided PowerShell script:

```powershell
# Run from project root
.\scripts\build_release.ps1

# This script:
# 1. Cleans previous builds
# 2. Builds Flutter app
# 3. Builds backend EXE
# 4. Creates Inno Setup installer
# 5. Outputs final installer to installer\output\
```

---

## Troubleshooting

### Backend Won't Start

1. **Check port 8000**: Ensure no other process is using port 8000
   ```powershell
   netstat -ano | findstr :8000
   ```

2. **Check backend logs**:
   ```powershell
   explorer "%LocalAppData%\LINKodAdmin\Backend\logs"
   ```

3. **Test backend manually**:
   ```powershell
   cd "C:\Program Files\LINKod Admin\backend"
   .\linkod_admin_backend.exe
   # Then check http://localhost:8000/health in browser
   ```

### PyInstaller Build Issues

1. **Missing imports**: Add to `hiddenimports` in `.spec` file
2. **Large file size**: UPX compression is enabled; consider excluding unused packages
3. **Firebase issues**: Ensure `collect_all("firebase_admin")` works in spec

### Flutter Build Issues

1. **Missing `url_launcher` or `path_provider`**:
   ```bash
   flutter pub get
   ```

2. **Windows SDK not found**: Install Visual Studio 2022 with "Desktop development with C++" workload

---

## Updating the Application

### Minor Updates (same backend)

1. Build new Flutter app only
2. Rebuild installer with same backend
3. Users run new installer (upgrades existing installation)

### Major Updates (backend changes)

1. Update backend code
2. Rebuild backend EXE
3. Rebuild Flutter app
4. Rebuild installer
5. Version number should increment

### Auto-Update Considerations

For future auto-update functionality, consider:
- [auto_updater](https://pub.dev/packages/auto_updater) package
- Custom update server
- Version check on startup

---

## Security Notes

1. **Backend binds to 127.0.0.1 only** - not accessible from network
2. **No admin privileges required to run** - only to install
3. **Firebase credentials** - Can be bundled or configured separately
4. **Logs** - May contain sensitive data; advise users on log retention

---

## Distribution

The final deliverable is:

```
LINKod_Admin_Setup_1.0.0.exe
```

End user installation:
1. Download installer
2. Run as administrator
3. Follow installation wizard
4. Launch from Start Menu or Desktop shortcut
5. App auto-starts backend - no additional steps needed

---

## Support and Diagnostics

When users encounter issues:

1. **Check backend is running**: Ask them to visit http://localhost:8000/health in browser
2. **Get logs**: `%LocalAppData%\LINKodAdmin\Backend\logs`
3. **Check Windows version**: Must be Windows 10 or later
4. **Check port availability**: Port 8000 must be free

---

## Files Created/Modified

### New Files Created:

| File | Purpose |
|------|---------|
| `backend/launcher.py` | PyInstaller entry point with proper Windows paths |
| `backend/linkod_admin_backend.spec` | PyInstaller specification |
| `lib/services/backend_orchestrator.dart` | Flutter service to manage backend |
| `lib/screens/startup_screen.dart` | Startup UX with loading/error states |
| `installer/LINKod_Admin_Setup.iss` | Inno Setup installer script |
| `scripts/build_release.ps1` | Automated build script |
| `DEPLOYMENT.md` | This documentation |

### Modified Files:

| File | Changes |
|------|---------|
| `lib/main.dart` | Added production/development mode switching |
| `pubspec.yaml` | Added `path_provider` and `url_launcher` dependencies |

---

## Architecture Decisions

### Why not use Windows Service/NSSM?

- **User friction**: Services require admin rights to manage
- **Complexity**: Service installation/uninstallation adds failure points
- **Not needed**: App-managed process is simpler and sufficient for this use case
- **Updates**: Services are harder to update atomically

### Why not use PM2?

- **External dependency**: Users would need to install Node.js and PM2
- **Overkill**: Process manager is unnecessary for a single local app
- **Simpler**: Direct process management by Flutter is more reliable

### Why not cloud-host the backend?

- **Offline capability**: Local backend works without internet
- **Data privacy**: AI processing stays on local machine
- **Cost**: No cloud infrastructure costs
- **Complexity**: No authentication/networking between Flutter and backend

### Why windowed mode for backend EXE?

- **Silent operation**: No console window appears
- **Professional feel**: Users don't see technical processes
- **UX**: Errors shown through Flutter UI, not console

### Why keep backend running after app closes?

- **Faster restarts**: Backend already running when app reopens
- **Simpler logic**: No need to track "should I kill it?"
- **Resource usage**: Minimal impact when idle
- **Graceful**: Let Windows handle process cleanup

---

## Future Considerations

1. **Auto-updates**: Consider adding auto-updater package
2. **Backend updates**: May need mechanism to restart backend when updated
3. **Multiple instances**: Currently only one app instance; consider single-instance enforcement
4. **Logging level**: Consider adding UI control for log verbosity
5. **Health check UI**: Could add advanced diagnostics panel in app
