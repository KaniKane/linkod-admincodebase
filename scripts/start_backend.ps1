$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $repoRoot 'backend'
$pythonExe = Join-Path $repoRoot '.venv\Scripts\python.exe'
$healthUrl = 'http://localhost:8000/health'

if (-not (Test-Path $pythonExe)) {
    throw "Python virtual environment not found at $pythonExe"
}

# If backend is already listening, do not start a duplicate process.
$listener = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Host 'Backend already running on port 8000.'
    exit 0
}

Write-Host 'Starting backend on port 8000...'
$proc = Start-Process -FilePath $pythonExe `
    -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '0.0.0.0', '--port', '8000') `
    -WorkingDirectory $backendPath `
    -PassThru

Start-Sleep -Seconds 2

try {
    $health = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 10
    if ($health.status -eq 'ok') {
        Write-Host "Backend started successfully (PID=$($proc.Id))."
        exit 0
    }

    Write-Host "Backend process started (PID=$($proc.Id)), but health response was unexpected."
    exit 1
}
catch {
    Write-Host "Backend process started (PID=$($proc.Id)), but /health check failed."
    Write-Host $_.Exception.Message
    exit 1
}
