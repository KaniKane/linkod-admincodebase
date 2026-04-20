"""
AI configuration settings loaded from environment variables.

This module provides safe, typed access to AI-related configuration.
Values are loaded lazily from environment variables.
"""

import os
from typing import Optional

# Load .env file if present
from dotenv import load_dotenv

# Get the directory containing this file
_current_dir = os.path.dirname(os.path.abspath(__file__))
# Go up one level to backend/, then look for .env
_env_path = os.path.join(os.path.dirname(_current_dir), ".env")
load_dotenv(_env_path)


# Hosted LLM configuration
def get_llm_base_url() -> Optional[str]:
    """Get the hosted LLM base URL. Required for hosted mode."""
    return os.getenv("LLM_BASE_URL")


def get_llm_api_key() -> Optional[str]:
    """Get the hosted LLM API key. Required for hosted mode."""
    return os.getenv("LLM_API_KEY")


def get_llm_model_primary() -> Optional[str]:
    """Get the primary hosted LLM model name."""
    return os.getenv("LLM_MODEL_PRIMARY")


def get_llm_model_fallback() -> Optional[str]:
    """Get the fallback hosted LLM model name (if different from primary)."""
    return os.getenv("LLM_MODEL_FALLBACK")


# Request settings
def get_ai_timeout_seconds() -> float:
    """Get the timeout for AI requests in seconds. Default 60."""
    try:
        return float(os.getenv("AI_TIMEOUT_SECONDS", "60"))
    except ValueError:
        return 60.0


def get_ai_max_retries() -> int:
    """Get the maximum number of retries for AI requests. Default 1."""
    try:
        return int(os.getenv("AI_MAX_RETRIES", "1"))
    except ValueError:
        return 1


# Typed constants for convenience
LLM_BASE_URL: Optional[str] = get_llm_base_url()
LLM_API_KEY: Optional[str] = get_llm_api_key()
LLM_MODEL_PRIMARY: Optional[str] = get_llm_model_primary()
LLM_MODEL_FALLBACK: Optional[str] = get_llm_model_fallback()
AI_TIMEOUT_SECONDS: float = get_ai_timeout_seconds()
AI_MAX_RETRIES: int = get_ai_max_retries()
