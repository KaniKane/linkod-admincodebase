"""
LINKod Admin Backend - Packaged Launcher Entry Point

This module serves as the entry point when the backend is packaged as a Windows executable
using PyInstaller. It handles:
- Runtime path resolution for packaged vs development environments
- Logging setup to a writable location
- Explicit Uvicorn startup with proper host/port binding
- Graceful error handling and diagnostics

Usage (packaged):
    linkod_admin_backend.exe

Usage (development):
    python launcher.py
"""

import os
import sys
import logging
import time
from pathlib import Path
from contextlib import asynccontextmanager

# =============================================================================
# PATH RESOLUTION FOR PACKAGED ENVIRONMENT
# =============================================================================

def get_runtime_paths():
    """
    Resolve runtime paths for both packaged (PyInstaller) and development modes.
    
    Returns:
        dict with keys:
            - exe_dir: Directory containing the executable/script
            - app_data_dir: Writable directory for logs/config (LocalAppData)
            - is_packaged: True if running from PyInstaller bundle
    """
    # Detect PyInstaller packaged mode
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        # Running from PyInstaller bundle
        exe_path = Path(sys.executable).resolve()
        is_packaged = True
    else:
        # Running from source
        exe_path = Path(__file__).resolve().parent
        is_packaged = False
    
    exe_dir = exe_path.parent if is_packaged else exe_path
    
    # Writable app data directory (LocalAppData is standard for Windows apps)
    local_app_data = os.environ.get('LOCALAPPDATA')
    if local_app_data:
        app_data_dir = Path(local_app_data) / 'LINKodAdmin' / 'Backend'
    else:
        # Fallback: use exe_dir if LocalAppData not available (shouldn't happen on Windows)
        app_data_dir = exe_dir / 'data'
    
    return {
        'exe_dir': exe_dir,
        'app_data_dir': app_data_dir,
        'is_packaged': is_packaged,
    }

# Get runtime paths
RUNTIME_PATHS = get_runtime_paths()
EXE_DIR = RUNTIME_PATHS['exe_dir']
APP_DATA_DIR = RUNTIME_PATHS['app_data_dir']
IS_PACKAGED = RUNTIME_PATHS['is_packaged']

# Ensure writable directories exist
APP_DATA_DIR.mkdir(parents=True, exist_ok=True)
(LOGS_DIR := APP_DATA_DIR / 'logs').mkdir(parents=True, exist_ok=True)

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

def setup_logging():
    """
    Configure logging to both file and console.
    Log files go to LocalAppData/LINKodAdmin/Backend/logs/
    """
    log_file = LOGS_DIR / f'backend_{time.strftime("%Y%m%d_%H%M%S")}.log'
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout),
        ],
    )
    
    logger = logging.getLogger(__name__)
    logger.info(f"Logging initialized: {log_file}")
    logger.info(f"Runtime mode: {'PACKAGED' if IS_PACKAGED else 'DEVELOPMENT'}")
    logger.info(f"EXE_DIR: {EXE_DIR}")
    logger.info(f"APP_DATA_DIR: {APP_DATA_DIR}")
    
    return logger

# Setup logging before anything else
logger = setup_logging()

# =============================================================================
# ENVIRONMENT CONFIGURATION FOR PACKAGED MODE
# =============================================================================

def setup_packaged_environment():
    """
    Set up environment variables for packaged mode.
    - Ensure config files can be found
    - Set up Firebase credentials path if bundled
    """
    # In packaged mode, look for config next to the executable
    if IS_PACKAGED:
        # Set GOOGLE_APPLICATION_CREDENTIALS to bundled creds if present
        bundled_creds = EXE_DIR / 'linkod-db-firebase-adminsdk-fbsvc-db4270d732.json'
        if bundled_creds.exists() and not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'):
            os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = str(bundled_creds)
            logger.info(f"Using bundled Firebase credentials: {bundled_creds}")
        
        # Ensure PYTHONPATH includes the bundle for imports
        if hasattr(sys, '_MEIPASS'):
            bundle_root = Path(sys._MEIPASS)
            if str(bundle_root) not in sys.path:
                sys.path.insert(0, str(bundle_root))
                logger.info(f"Added bundle root to path: {bundle_root}")

setup_packaged_environment()

# =============================================================================
# FASTAPI APPLICATION IMPORT AND SETUP
# =============================================================================

# Import the FastAPI app from main module
# We import here after environment setup to ensure paths are correct
try:
    from main import app, _initialize_firebase
    logger.info("FastAPI app imported successfully")
except ImportError as e:
    logger.error(f"Failed to import FastAPI app: {e}")
    raise

# =============================================================================
# LIFESPAN AND SHUTDOWN HANDLING
# =============================================================================

@asynccontextmanager
async def lifespan(app):
    """
    Application lifespan handler for startup/shutdown events.
    """
    # Startup
    logger.info("Backend starting up...")
    try:
        # Re-initialize Firebase if needed (in case packaged env has different paths)
        _initialize_firebase()
        logger.info("Firebase initialized in lifespan")
    except Exception as e:
        logger.warning(f"Firebase initialization in lifespan failed: {e}")
    
    logger.info("Backend startup complete - ready to accept connections")
    yield
    
    # Shutdown
    logger.info("Backend shutting down...")

# Apply lifespan to app if not already set
# Note: The main.py app doesn't use lifespan yet, but we could add it

# =============================================================================
# SERVER STARTUP
# =============================================================================

def run_server():
    """
    Start the Uvicorn server with explicit configuration.
    Binds to 127.0.0.1:8000 (localhost only for security)
    """
    import uvicorn
    
    host = "127.0.0.1"  # Localhost only - not accessible from network
    port = 8000
    
    logger.info(f"Starting Uvicorn server on {host}:{port}")
    logger.info(f"Health check URL: http://{host}:{port}/health")
    
    # Explicit server configuration for packaged mode
    config = uvicorn.Config(
        "main:app",  # Use module string for reload compatibility
        host=host,
        port=port,
        log_level="info",
        access_log=True,
        # Use single worker in packaged mode (no need for multiple processes)
        workers=1,
        # Allow graceful shutdown on signals
        lifespan="on",
    )
    
    server = uvicorn.Server(config)
    
    try:
        server.run()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    except Exception as e:
        logger.error(f"Server error: {e}", exc_info=True)
        raise

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

if __name__ == "__main__":
    try:
        logger.info("=" * 60)
        logger.info("LINKod Admin Backend - Starting")
        logger.info("=" * 60)
        run_server()
    except Exception as e:
        logger.critical(f"Fatal error starting backend: {e}", exc_info=True)
        # Write a simple error file for troubleshooting
        try:
            error_file = LOGS_DIR / 'startup_error.txt'
            with open(error_file, 'w', encoding='utf-8') as f:
                f.write(f"Startup failed at {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"Error: {e}\n")
                import traceback
                f.write(traceback.format_exc())
            print(f"Error details written to: {error_file}")
        except:
            pass
        sys.exit(1)
