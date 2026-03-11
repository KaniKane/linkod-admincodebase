"""
Ollama provider for structured JSON generation.

Optimized for Llama 3.2:3B with JSON extraction strategies.
Combines system and user prompts for better small-model performance.
"""

import json
import re
import time
import logging
from typing import Optional
import httpx

from providers.base_provider import (
    BaseProvider, 
    GenerationRequest, 
    GenerationResult,
    ProviderHealth
)
from config.settings import get_settings

logger = logging.getLogger(__name__)


class OllamaProvider(BaseProvider):
    """
    Local Llama-based structured generation provider.
    
    Key design decisions for Llama 3.2:3B:
    - Combines system + user prompts (works better than message format)
    - Aggressive JSON enforcement via prompt suffix
    - Multi-stage JSON extraction (direct -> markdown -> regex)
    - Low temperature (0.1-0.3) for deterministic output
    - Never raises exceptions - always returns GenerationResult
    """
    
    # JSON enforcement suffix appended to all prompts
    JSON_ENFORCEMENT = """

CRITICAL INSTRUCTIONS:
1. Output ONLY valid JSON. No markdown code blocks (no ```json).
2. No explanations before or after the JSON.
3. The JSON must match the schema exactly.
4. Start with { and end with }.

Example of correct output:
{"refined_text": "Your refined text here", "dialect_confidence": 0.8, "tandaganon_terms_used": ["term1"]}

Your JSON output:"""
    
    def __init__(
        self,
        base_url: Optional[str] = None,
        model: Optional[str] = None,
        timeout: int = 60
    ):
        self.settings = get_settings()
        self.base_url = base_url or self.settings.OLLAMA_BASE_URL
        self.model = model or self.settings.OLLAMA_MODEL
        self.timeout = timeout
    
    @property
    def name(self) -> str:
        return "ollama"
    
    def is_available(self) -> bool:
        """Check if Ollama server is reachable."""
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(f"{self.base_url}/api/tags")
                return response.status_code == 200
        except Exception:
            return False
    
    def health_check(self) -> ProviderHealth:
        """Detailed health check including model availability."""
        start = time.time()
        
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.get(f"{self.base_url}/api/tags")
                response.raise_for_status()
                
                data = response.json()
                models = data.get("models", [])
                model_names = [m.get("name", "") for m in models]
                
                latency_ms = int((time.time() - start) * 1000)
                
                if self.model in model_names:
                    return ProviderHealth(
                        is_healthy=True,
                        message=f"Ollama available with {self.model}",
                        latency_ms=latency_ms
                    )
                else:
                    return ProviderHealth(
                        is_healthy=False,
                        message=f"Ollama running but {self.model} not pulled. Available: {model_names[:3]}"
                    )
                    
        except Exception as e:
            return ProviderHealth(
                is_healthy=False,
                message=f"Ollama not reachable: {str(e)[:50]}"
            )
    
    def generate_structured(self, request: GenerationRequest) -> GenerationResult:
        """
        Generate structured JSON using Ollama.
        
        Strategy:
        1. Combine system + user prompts with JSON enforcement
        2. Generate with low temperature
        3. Attempt multi-stage JSON extraction
        4. Return normalized GenerationResult
        """
        start_time = time.time()
        
        # Combine prompts with JSON enforcement
        full_prompt = (
            f"{request.system_prompt}\n\n"
            f"{request.user_prompt}\n"
            f"{self.JSON_ENFORCEMENT}"
        )
        
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.post(
                    f"{self.base_url}/api/generate",
                    json={
                        "model": self.model,
                        "prompt": full_prompt,
                        "stream": False,
                        "options": {
                            "temperature": request.temperature,
                            "num_predict": request.max_tokens or 800,
                            "stop": ["\n\n", "Text:"],  # Prevent runaway generation
                        }
                    }
                )
                response.raise_for_status()
                data = response.json()
                
                raw_output = data.get("response", "").strip()
                latency_ms = int((time.time() - start_time) * 1000)
                
                if not raw_output:
                    return GenerationResult(
                        success=False,
                        output=None,
                        raw_response=raw_output,
                        provider="ollama",
                        latency_ms=latency_ms,
                        error="ollama_returned_empty"
                    )
                
                # Try to extract and parse JSON
                json_text = self._extract_json(raw_output)
                
                if json_text:
                    try:
                        parsed = json.loads(json_text)
                        warnings = []
                        
                        # Flag if we had to extract JSON (not clean output)
                        if json_text != raw_output.strip():
                            warnings.append("json_extracted_from_markdown")
                        
                        # Check for schema drift (extra fields are OK, missing required is not)
                        schema_required = request.json_schema.get("required", [])
                        missing_fields = [f for f in schema_required if f not in parsed]
                        if missing_fields:
                            warnings.append(f"missing_required_fields: {missing_fields}")
                        
                        return GenerationResult(
                            success=len(missing_fields) == 0,
                            output=parsed if len(missing_fields) == 0 else None,
                            raw_response=raw_output,
                            provider="ollama",
                            latency_ms=latency_ms,
                            error=f"missing_fields: {missing_fields}" if missing_fields else None,
                            warnings=warnings
                        )
                        
                    except json.JSONDecodeError as e:
                        return GenerationResult(
                            success=False,
                            output=None,
                            raw_response=raw_output,
                            provider="ollama",
                            latency_ms=latency_ms,
                            error=f"json_parse_error: {str(e)[:100]}"
                        )
                else:
                    return GenerationResult(
                        success=False,
                        output=None,
                        raw_response=raw_output,
                        provider="ollama",
                        latency_ms=latency_ms,
                        error="no_json_found_in_output"
                    )
                    
        except httpx.TimeoutException:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="ollama",
                latency_ms=int((time.time() - start_time) * 1000),
                error="timeout"
            )
        except httpx.HTTPError as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="ollama",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"http_error: {str(e)[:100]}"
            )
        except Exception as e:
            return GenerationResult(
                success=False,
                output=None,
                raw_response=None,
                provider="ollama",
                latency_ms=int((time.time() - start_time) * 1000),
                error=f"unexpected_error: {str(e)[:100]}"
            )
    
    def _extract_json(self, text: str) -> Optional[str]:
        """
        Multi-stage JSON extraction from potentially messy output.
        
        Stages:
        1. Direct parse attempt
        2. Markdown code block extraction
        3. Bracket boundary finding with validation
        
        Returns:
            Clean JSON string or None if extraction fails
        """
        text = text.strip()
        
        # Stage 1: Direct parse
        try:
            json.loads(text)
            return text
        except json.JSONDecodeError:
            pass
        
        # Stage 2: Markdown code block
        if "```json" in text or "```" in text:
            # Try ```json ... ```
            match = re.search(r'```json\s*(.*?)\s*```', text, re.DOTALL | re.IGNORECASE)
            if match:
                candidate = match.group(1).strip()
                try:
                    json.loads(candidate)
                    return candidate
                except:
                    pass
            
            # Try plain ``` ... ```
            match = re.search(r'```\s*(.*?)\s*```', text, re.DOTALL)
            if match:
                candidate = match.group(1).strip()
                try:
                    json.loads(candidate)
                    return candidate
                except:
                    pass
        
        # Stage 3: Find JSON object boundaries
        start = text.find('{')
        end = text.rfind('}')
        
        if start != -1 and end != -1 and end > start:
            candidate = text[start:end+1]
            try:
                json.loads(candidate)
                return candidate
            except:
                pass
        
        # Stage 4: Try finding array boundaries (fallback)
        start = text.find('[')
        end = text.rfind(']')
        if start != -1 and end != -1 and end > start:
            candidate = text[start:end+1]
            try:
                json.loads(candidate)
                return candidate
            except:
                pass
        
        return None
