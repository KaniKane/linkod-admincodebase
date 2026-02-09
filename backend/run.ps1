# Start LINKod Admin backend (FastAPI)
# From backend folder: .\run.ps1
# Or: python -m uvicorn main:app --host 0.0.0.0 --port 8000

Set-Location $PSScriptRoot
python -m uvicorn main:app --host 0.0.0.0 --port 8000
