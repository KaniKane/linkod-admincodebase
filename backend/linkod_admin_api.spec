# PyInstaller spec for LINKod Admin Backend API (FastAPI + Uvicorn)
# Run: pyinstaller --clean linkod_admin_api.spec
# Output: dist/linkod_admin_api/ (onedir) — run linkod_admin_api.exe to start server on port 8000

# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

# Hidden imports for Uvicorn and Firebase (discovered via trial or from trace)
hidden_imports = [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
]

# Bundle config so audience_rules.json is found inside the bundle when running as exe
datas = [
    ("config/audience_rules.json", "config"),
]

# Include firebase_admin and google packages (certificates, gRPC, etc.)
try:
    from PyInstaller.utils.hooks import collect_all, collect_data_files
    firebase_datas, firebase_binaries, firebase_hidden = collect_all("firebase_admin")
    datas += firebase_datas
    hidden_imports += firebase_hidden
except Exception:
    pass

_binaries = []
try:
    _binaries = firebase_binaries
except NameError:
    pass

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=_binaries,
    datas=datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="linkod_admin_api",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # Keep console so launcher can attach and user can see errors if needed
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="linkod_admin_api",
)
