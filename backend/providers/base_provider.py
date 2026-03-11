"""
Base provider interface for AI text generation.

Defines the contract that both OpenAI and Ollama providers must implement.
All providers return normalized GenerationResult objects regardless of
underlying SDK differences.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List


@dataclass
class GenerationRequest:
    """
    Request for structured text generation.
    
    Attributes:
        system_prompt: System-level instructions and principles
        user_prompt: The actual content to process (includes context, constraints)
        json_schema: JSON Schema dict for output validation
        temperature: Sampling temperature (0.0-1.0, lower = more deterministic)
        max_tokens: Maximum tokens to generate (None = model default)
    """
    system_prompt: str
    user_prompt: str
    json_schema: Dict[str, Any]
    temperature: float = 0.3
    max_tokens: Optional[int] = None


@dataclass
class GenerationResult:
    """
    Normalized result from any provider.
    
    All providers must return this exact shape so the orchestrator
    can handle OpenAI and Ollama identically.
    
    Attributes:
        success: Whether generation and parsing succeeded
        output: Parsed JSON dict if success=True, None otherwise
        raw_response: Original provider response for debugging
        provider: Provider identifier ("openai" or "ollama")
        latency_ms: Time taken for the request
        tokens_used: Token count if available (OpenAI), None for Ollama
        error: Error description if success=False
        warnings: Non-fatal issues (schema drift, extracted JSON, etc.)
    """
    success: bool
    output: Optional[Dict[str, Any]]
    raw_response: Optional[str]
    provider: str
    latency_ms: int
    tokens_used: Optional[int] = None
    error: Optional[str] = None
    warnings: List[str] = field(default_factory=list)


@dataclass
class ProviderHealth:
    """Health check result for a provider."""
    is_healthy: bool
    message: str
    latency_ms: Optional[int] = None


class BaseProvider(ABC):
    """
    Abstract base class for AI providers.
    
    Implementations must provide:
    - generate_structured(): Main generation method
    - is_available(): Health check for provider connectivity
    
    Design principles:
    - JSON parsing happens inside the provider
    - Failures are captured in result, not raised as exceptions
    - All timing and logging is provider's responsibility
    """
    
    @abstractmethod
    def generate_structured(self, request: GenerationRequest) -> GenerationResult:
        """
        Generate structured JSON output from the provider.
        
        Args:
            request: GenerationRequest with prompts and schema
            
        Returns:
            GenerationResult with normalized output
            
        Implementation notes:
        - Must handle own timeouts and connection errors
        - Must parse JSON and return structured output dict
        - Must measure and report latency_ms accurately
        - Must never raise exceptions - always return result
        - Raw response should be preserved for debugging
        """
        pass
    
    @abstractmethod
    def is_available(self) -> bool:
        """
        Check if provider is currently reachable and functional.
        
        Returns:
            True if provider can accept requests, False otherwise
            
        Use this for:
        - Health checks in orchestrator
        - Deciding primary vs fallback provider
        - Pre-flight validation before attempting generation
        """
        pass
    
    @abstractmethod
    def health_check(self) -> ProviderHealth:
        """
        Lightweight health check - no full model calls.
        
        Returns:
            ProviderHealth with status information
        """
        pass
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Provider identifier (e.g., 'openai', 'ollama')."""
        pass
