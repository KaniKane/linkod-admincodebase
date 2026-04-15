# LINKod Admin - Release Build Script
# This script automates the complete build process for Windows deployment
#
# Usage:
#   .\scripts\build_release.ps1
#   .\scripts\build_release.ps1 -SkipBackend    # Skip backend build (use existing)
#   .\scripts\build_release.ps1 -SkipFlutter   # Skip Flutter build (use existing)
#
# Prerequisites:
#   - Flutter SDK installed and in PATH
#   - Python installed with PyInstaller
#   - Inno Setup 6.2+ installed
#   - Running from project root directory

param(
    [switch]$SkipBackend,
    [switch]$SkipFlutter,
    [switch]$SkipInstaller,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Configuration
$BackendDir = "backend"
$FlutterBuildDir = "build\windows\x64\runner\Release"
$BackendDistDir = "backend\dist\linkod_admin_backend"
$InstallerDir = "installer"
$OutputDir = "installer\output"
$InnoSetupPath = $null
$InnoSetupCandidatePaths = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "D:\Inno Setup 6\ISCC.exe"
)
$BackendSpecFile = "linkod_admin_backend.installer.spec"
$InstallerScriptFile = "LINKod_Admin_Setup_Production.iss"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LINKod Admin - Release Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow

    # Check Flutter
    try {
        $flutterVersion = flutter --version 2>$null | Select-Object -First 1
        Write-Host "  Flutter: $flutterVersion" -ForegroundColor Green
    } catch {
        Write-Error "Flutter not found in PATH. Please install Flutter SDK."
    }

    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        Write-Host "  Python: $pythonVersion" -ForegroundColor Green
    } catch {
        Write-Error "Python not found in PATH. Please install Python."
    }

    # Check PyInstaller
    try {
        $pyinstallerVersion = pyinstaller --version 2>$null
        Write-Host "  PyInstaller: $pyinstallerVersion" -ForegroundColor Green
    } catch {
        Write-Warning "PyInstaller not found. Will try to use existing backend build or install it."
    }

    # Check Inno Setup
    foreach ($candidate in $InnoSetupCandidatePaths) {
        if (Test-Path $candidate) {
            $script:InnoSetupPath = $candidate
            break
        }
    }

    if ($InnoSetupPath) {
        Write-Host "  Inno Setup: Found at $InnoSetupPath" -ForegroundColor Green
    } else {
        Write-Error "Inno Setup not found. Please install Inno Setup 6 from https://jrsoftware.org/isinfo.php"
    }

    Write-Host ""
}

# Clean previous builds
function Invoke-CleanBuild {
    Write-Host "Cleaning previous builds..." -ForegroundColor Yellow

    if (Test-Path $FlutterBuildDir) {
        Remove-Item -Path $FlutterBuildDir -Recurse -Force
        Write-Host "  Cleaned Flutter build directory" -ForegroundColor Green
    }

    if (Test-Path $BackendDistDir) {
        Remove-Item -Path $BackendDistDir -Recurse -Force
        Write-Host "  Cleaned backend dist directory" -ForegroundColor Green
    }

    if (Test-Path "$BackendDir\build") {
        Remove-Item -Path "$BackendDir\build" -Recurse -Force
        Write-Host "  Cleaned backend build directory" -ForegroundColor Green
    }

    if (Test-Path $OutputDir) {
        Remove-Item -Path "$OutputDir\*" -Include "*.exe" -Force
        Write-Host "  Cleaned installer output" -ForegroundColor Green
    }

    Write-Host ""
}

# Build Flutter app
function Invoke-FlutterBuild {
    Write-Host "Building Flutter Windows app..." -ForegroundColor Yellow

    # Get dependencies
    Write-Host "  Getting Flutter dependencies..." -ForegroundColor Gray
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter pub get failed"
    }

    # Build release
    Write-Host "  Building Windows release..." -ForegroundColor Gray
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed"
    }

    # Verify output
    $exePath = "$FlutterBuildDir\linkod_admin.exe"
    if (-not (Test-Path $exePath)) {
        Write-Error "Flutter build did not produce linkod_admin.exe at expected location"
    }

    Write-Host "  Flutter build successful: $exePath" -ForegroundColor Green
    Write-Host ""
}

# Build backend
function Invoke-BackendBuild {
    Write-Host "Building Python backend..." -ForegroundColor Yellow

    $currentDir = Get-Location

    try {
        Set-Location $BackendDir

        # Check if PyInstaller needs installation
        pyinstaller --version 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Installing PyInstaller..." -ForegroundColor Gray
            pip install pyinstaller
        }

        # Build the EXE
        Write-Host "  Running PyInstaller (this may take 2-5 minutes)..." -ForegroundColor Gray
        pyinstaller --clean $BackendSpecFile

        if ($LASTEXITCODE -ne 0) {
            Write-Error "PyInstaller build failed"
        }

        # Verify output
        $exePath = "dist\linkod_admin_backend\linkod_admin_backend.exe"
        if (-not (Test-Path $exePath)) {
            Write-Error "Backend build did not produce linkod_admin_backend.exe"
        }

        Write-Host "  Backend build successful: $exePath" -ForegroundColor Green

    } finally {
        Set-Location $currentDir
    }

    Write-Host ""
}

# Build installer
function Invoke-InstallerBuild {
    Write-Host "Building Inno Setup installer..." -ForegroundColor Yellow

    # Check that all required files exist
    $flutterExe = "$FlutterBuildDir\linkod_admin.exe"
    $backendExe = "$BackendDistDir\linkod_admin_backend.exe"

    if (-not (Test-Path $flutterExe)) {
        Write-Error "Flutter executable not found: $flutterExe"
    }

    if (-not (Test-Path $backendExe)) {
        Write-Error "Backend executable not found: $backendExe"
    }

    Write-Host "  Flutter EXE: $flutterExe" -ForegroundColor Gray
    Write-Host "  Backend EXE: $backendExe" -ForegroundColor Gray

    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Run Inno Setup compiler
    $issPath = "$InstallerDir\$InstallerScriptFile"
    if (-not (Test-Path $issPath)) {
        Write-Error "Inno Setup script not found: $issPath"
    }

    Write-Host "  Running Inno Setup compiler..." -ForegroundColor Gray
    & $InnoSetupPath $issPath

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup build failed"
    }

    # Find the output file
    $outputFile = Get-ChildItem -Path $OutputDir -Filter "LINKod_Admin_Setup_*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $outputFile) {
        Write-Error "Installer output not found in $OutputDir"
    }

    Write-Host "  Installer build successful: $($outputFile.FullName)" -ForegroundColor Green
    Write-Host ""

    return $outputFile.FullName
}

# Show summary
function Show-Summary {
    param([string]$InstallerPath)

    Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
    Write-Host "Installer: $InstallerPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "File sizes:" -ForegroundColor Yellow

    $flutterSize = (Get-Item "$FlutterBuildDir\linkod_admin.exe").Length
    Write-Host "  linkod_admin.exe: $([math]::Round($flutterSize / 1MB, 2)) MB" -ForegroundColor Gray

    $backendFiles = Get-ChildItem -Path $BackendDistDir -Recurse -File
    $backendSize = ($backendFiles | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Backend files: $([math]::Round($backendSize / 1MB, 2)) MB total" -ForegroundColor Gray

    $installerSize = (Get-Item $InstallerPath).Length
    Write-Host "  Installer: $([math]::Round($installerSize / 1MB, 2)) MB" -ForegroundColor Gray

    Write-Host ""
    Write-Host "Installation instructions for end users:" -ForegroundColor Yellow
    Write-Host "  1. Run the installer as administrator" -ForegroundColor Gray
    Write-Host "  2. Follow the installation wizard" -ForegroundColor Gray
    Write-Host "  3. Launch from Start Menu or Desktop shortcut" -ForegroundColor Gray
    Write-Host "  4. The app will automatically start the backend" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  - Backend logs: %LocalAppData%\LINKodAdmin\Backend\logs" -ForegroundColor Gray
    Write-Host "  - Port requirement: localhost:8000 must be available" -ForegroundColor Gray
    Write-Host "  - Windows 10 or later required" -ForegroundColor Gray
    Write-Host ""
}

# Main execution
try {
    Test-Prerequisites

    if ($Clean) {
        Invoke-CleanBuild
    }

    if (-not $SkipFlutter) {
        Invoke-FlutterBuild
    } else {
        Write-Host "Skipping Flutter build (using existing)" -ForegroundColor Yellow
        if (-not (Test-Path "$FlutterBuildDir\linkod_admin.exe")) {
            Write-Error "No existing Flutter build found at $FlutterBuildDir\linkod_admin.exe"
        }
    }

    if (-not $SkipBackend) {
        Invoke-BackendBuild
    } else {
        Write-Host "Skipping backend build (using existing)" -ForegroundColor Yellow
        if (-not (Test-Path "$BackendDistDir\linkod_admin_backend.exe")) {
            Write-Error "No existing backend build found at $BackendDistDir\linkod_admin_backend.exe"
        }
    }

    if (-not $SkipInstaller) {
        $installer = Invoke-InstallerBuild
        Show-Summary -InstallerPath $installer
    } else {
        Write-Host "Skipping installer build" -ForegroundColor Yellow
    }

    Write-Host "Build script completed successfully!" -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Build failed. See error message above." -ForegroundColor Red
    exit 1
}
