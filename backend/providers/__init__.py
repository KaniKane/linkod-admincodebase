"""
Provider router and exports.

Provides provider selection based on AI_PROVIDER environment variable.
"""

from typing import Optional
from config.settings import get_settings, Settings
from providers.base_provider import BaseProvider
from providers.openai_provider import OpenAIProvider
from providers.ollama_provider import OllamaProvider


class ProviderRouter:
    """
    Routes to appropriate provider based on configuration.
    
    Provider selection is controlled EXCLUSIVELY through AI_PROVIDER env var:
    - "ollama": Use Ollama only (defense/offline mode)
    - "openai": Use OpenAI only (deployment mode)
    - "auto": OpenAI primary, Ollama fallback
    """
    
    def __init__(self, settings: Settings):
        self.settings = settings
        self._openai: Optional[OpenAIProvider] = None
        self._ollama: Optional[OllamaProvider] = None
    
    @property
    def openai(self) -> OpenAIProvider:
        if self._openai is None:
            self._openai = OpenAIProvider()
        return self._openai
    
    @property
    def ollama(self) -> OllamaProvider:
        if self._ollama is None:
            self._ollama = OllamaProvider()
        return self._ollama
    
    def get_primary(self) -> BaseProvider:
        """
        Get primary provider based on AI_PROVIDER configuration.
        
        Returns:
            BaseProvider: The provider to use first
        """
        mode = self.settings.AI_PROVIDER.lower()
        
        if mode == "ollama":
            return self.ollama
        elif mode == "openai":
            return self.openai
        else:  # auto - OpenAI is primary
            return self.openai
    
    def get_fallback(self) -> Optional[BaseProvider]:
        """
        Get fallback provider if enabled.
        
        Returns:
            BaseProvider or None: Fallback provider if configured
        """
        mode = self.settings.AI_PROVIDER.lower()
        
        if mode == "ollama":
            return None  # Ollama-only mode has no fallback
        elif mode == "openai":
            return self.ollama if self.settings.FALLBACK_TO_OLLAMA else None
        else:  # auto - Ollama is fallback
            return self.ollama if self.settings.FALLBACK_TO_OLLAMA else None
    
    def health_check(self) -> dict:
        """Check health of all providers."""
        return {
            "openai": self.openai.health_check(),
            "ollama": self.ollama.health_check(),
        }


# Singleton instance
_router: Optional[ProviderRouter] = None


def get_provider_router() -> ProviderRouter:
    """Get or create the provider router singleton."""
    global _router
    if _router is None:
        _router = ProviderRouter(get_settings())
    return _router


# Convenience exports
__all__ = [
    "BaseProvider",
    "OpenAIProvider", 
    "OllamaProvider",
    "ProviderRouter",
    "get_provider_router",
]
