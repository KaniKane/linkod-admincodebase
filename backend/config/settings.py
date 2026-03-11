"""
Environment-based configuration for LINKod Admin AI refinement.

All provider settings are controlled through environment variables.
No code changes required for switching between demo/deployment modes.
"""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.
    
    AI_PROVIDER controls which provider is active:
    - "ollama": Use local Llama only (thesis defense/offline mode)
    - "openai": Use OpenAI only (deployment mode)
    - "auto": Try OpenAI first, fallback to Ollama
    """
    
    # Provider selection (EXCLUSIVE control mechanism)
    AI_PROVIDER: str = "auto"  # Options: auto, openai, ollama
    
    # OpenAI Configuration
    OPENAI_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-4o-mini"  # Safer default than gpt-5-mini
    OPENAI_TIMEOUT_SECONDS: int = 15
    
    # Ollama Configuration (fallback / defense mode)
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    OLLAMA_MODEL: str = "llama3.2:3b"
    OLLAMA_TIMEOUT_SECONDS: int = 30  # Reduced from 60 to stay under Flutter timeout
    
    # Fallback Settings
    FALLBACK_TO_OLLAMA: bool = True
    
    # Safety Settings
    MAX_INPUT_LENGTH: int = 3000
    
    # Validation Settings (conservative defaults)
    MIN_FACT_PRESERVATION_SCORE: float = 0.9  # Reject if <90% facts preserved
    MIN_DIALECT_CONFIDENCE: float = 0.5  # Minimum acceptable dialect confidence
    MAX_REFINEMENT_RETRIES: int = 1  # Max retry attempts before fallback
    
    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
