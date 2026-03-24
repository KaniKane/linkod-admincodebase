"""
Fallback client for local Ollama generation.

Provides functions to generate text via local Ollama instance.
"""

import time
from typing import Optional

import httpx

from config.ai_settings import OLLAMA_BASE_URL, OLLAMA_MODEL, AI_TIMEOUT_SECONDS
from llm.types import GenerationRequest, GenerationResult


def generate_text_local(
    prompt: str,
    ollama_base_url: Optional[str] = None,
) -> GenerationResult:
    """
    Generate text using local Ollama instance.

    Args:
        prompt: The prompt text to send to Ollama.
        ollama_base_url: Optional override for Ollama base URL.
                         Uses config OLLAMA_BASE_URL if not provided.

    Returns:
        GenerationResult with success status, generated text, and metadata.
    """
    base_url = ollama_base_url or OLLAMA_BASE_URL
    model = OLLAMA_MODEL
    start_time = time.time()

    try:
        with httpx.Client(timeout=AI_TIMEOUT_SECONDS) as client:
            response = client.post(
                f"{base_url}/api/generate",
                json={
                    "model": model,
                    "prompt": prompt,
                    "stream": False,
                    "temperature": 0.0,
                },
            )

            response.raise_for_status()
            data = response.json()

            generated_text = data.get("response", "").strip()
            latency_ms = int((time.time() - start_time) * 1000)

            if generated_text:
                return GenerationResult(
                    success=True,
                    text=generated_text,
                    provider="ollama",
                    model=model,
                    latency_ms=latency_ms,
                )
            else:
                return GenerationResult(
                    success=False,
                    text=None,
                    provider="ollama",
                    model=model,
                    error="Empty response from Ollama",
                    latency_ms=latency_ms,
                )

    except httpx.HTTPStatusError as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="ollama",
            model=model,
            error=f"HTTP error {e.response.status_code}",
            latency_ms=latency_ms,
        )
    except httpx.RequestError as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="ollama",
            model=model,
            error=f"Request error: {str(e)}",
            latency_ms=latency_ms,
        )
    except (KeyError, AttributeError) as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="ollama",
            model=model,
            error=f"Invalid response format: {str(e)}",
            latency_ms=latency_ms,
        )
    except Exception as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="ollama",
            model=model,
            error=f"Unexpected error: {str(e)}",
            latency_ms=latency_ms,
        )


def generate_text_local_from_request(
    request: GenerationRequest,
    ollama_base_url: Optional[str] = None,
) -> GenerationResult:
    """
    Generate text using local Ollama from a GenerationRequest.

    Args:
        request: The generation request containing prompt and parameters.
        ollama_base_url: Optional override for Ollama base URL.

    Returns:
        GenerationResult with success status, generated text, and metadata.
    """
    return generate_text_local(request.prompt, ollama_base_url)
