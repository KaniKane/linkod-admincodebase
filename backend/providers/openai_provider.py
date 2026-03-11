"""
OpenAI provider for structured JSON generation.

Uses Chat Completions API with response_format for reliable JSON output.
Matches the Ollama provider interface exactly.
"""

import json
import time
import logging
from typing import Optional
from openai import OpenAI, APIError, APITimeoutError, RateLimitError, AuthenticationError

from providers.base_provider import (
    BaseProvider, 
    GenerationRequest, 
    GenerationResult,
    ProviderHealth
)
from config.settings import get_settings

logger = logging.getLogger(__name__)


class OpenAIProvider(BaseProvider):
    """
    Cloud-based OpenAI structured generation provider.
    
    Leverages OpenAI's native JSON mode for reliable output:
    - response_format={"type": "json_object"} enforces valid JSON
    - Messages API with separate system/user roles
    - Built-in retry logic disabled - handled by orchestrator
    - Never raises exceptions - always returns GenerationResult
    """
    
    def __init__(
        self,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: Optional[int] = None
    ):
        self.settings = get_settings()
        self.api_key = api_key or self.settings.OPENAI_API_KEY
        self.model = model or self.settings.OPENAI_MODEL
        self.timeout = timeout or self.settings.OPENAI_TIMEOUT_SECONDS
        
        self._client: Optional[OpenAI] = None
        if self.api_key:
            self._client = OpenAI(api_key=self.api_key)
    
    @property
    def name(self) -> str:
        return "openai"
    
    def is_available(self) -> bool:
        """Check if OpenAI client is configured and reachable."""
        if not self._client:
            return False
        
        try:
            self._client.models.list()
            return True
        except Exception:
            return False
    
    def health_check(self) -> ProviderHealth:
        """Detailed health check without making expensive model calls."""
        start = time.time()
        
        if not self._client:
            return ProviderHealth(
                is_healthy=False,
                message="OpenAI API key not configured"
            )
        
        try:
            # Just list models - cheap operation, no generation cost
            self._client.models.list()
            latency_ms = int((time.time() - start) * 1000)
            
            return ProviderHealth(
                is_healthy=True,
                message=f"OpenAI available (model: {self.model})",
                latency_ms=latency_ms
            )
        except AuthenticationError as e:
            return ProviderHealth(
                is_healthy=False,
                message=f"OpenAI authentication failed: {str(e)[:50]}"
            )
        except Exception as e:
            return ProviderHealth(
                is_healthy=False,
                message=f"OpenAI health check failed: {str(e)[:50]}"
            )
    
    def generate_structured(self, request: GenerationRequest) -> GenerationResult:
        """
        Generate structured JSON using OpenAI.
        
        Strategy:
        1. Use native JSON mode (response_format)
        2. Separate system/user messages (better than combined for OpenAI)
        3. Parse response - should always be valid JSON
        4. Return normalized GenerationResult
        
        Error handling:
        - RateLimitError: Don't retry (orchestrator handles)
        - TimeoutError: Don't retry (orchestrator handles)
        - APIError: Report and let orchestrator decide
        - JSON parse errors: Should not happen with json_object mode
        """
        start_time = time.time()
        
        if not self._client:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=0,
                error="openai_not_configured"
            )
        
        messages = [
            {"role": "system", "content": request.system_prompt},
            {"role": "user", "content": request.user_prompt}
        ]
        
        try:
            response = self._client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=request.temperature,
                max_tokens=request.max_tokens,
                response_format={"type": "json_object"},  # Enforces JSON output
                timeout=self.timeout,
            )
            
            content = response.choices[0].message.content
            latency_ms = int((time.time() - start_time) * 1000)
            tokens_used = response.usage.total_tokens if response.usage else None
            
            # OpenAI JSON mode guarantees valid JSON
            try:
                parsed = json.loads(content) if content else {}
                
                # Check schema compliance (optional, for observability)
                warnings = []
                schema_required = request.json_schema.get("required", [])
                missing_fields = [f for f in schema_required if f not in parsed]
                
                if missing_fields:
                    warnings.append(f"missing_required_fields: {missing_fields}")
                
                return GenerationResult(
                    success=True,
                    output=parsed,
                    raw_response=content,
                    provider="openai",
                    latency_ms=latency_ms,
                    tokens_used=tokens_used,
                    warnings=warnings
                )
                
            except json.JSONDecodeError as e:
                # Should never happen with json_object mode, but handle defensively
                return GenerationResult(
                    success=False,
                    output=None,
                    raw_response=content,
                    provider="openai",
                    latency_ms=latency_ms,
                    tokens_used=tokens_used,
                    error=f"unexpected_json_error: {str(e)[:100]}"
                )
                
        except RateLimitError as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"rate_limit: {str(e)[:100]}"
            )
        
        except APITimeoutError as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"timeout: {str(e)[:100]}"
            )
        
        except AuthenticationError as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"authentication: {str(e)[:100]}"
            )
        
        except APIError as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"api_error: {str(e)[:100]}"
            )
        
        except Exception as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="openai",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"unexpected: {str(e)[:100]}"
            )
