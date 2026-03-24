"""
Client for hosted LLM API requests.

Provides functions to generate text via hosted LLM services using httpx.
"""

import time
from typing import Optional

import httpx

from config.ai_settings import (
    LLM_API_KEY,
    LLM_BASE_URL,
    LLM_MODEL_PRIMARY,
    AI_TIMEOUT_SECONDS,
)
from llm.types import GenerationRequest, GenerationResult


def generate_text(request: GenerationRequest) -> GenerationResult:
    """
    Generate text using the primary hosted LLM model.

    Args:
        request: The generation request containing prompt and parameters.

    Returns:
        GenerationResult with success status, generated text, and metadata.
    """
    return generate_text_with_model(request, LLM_MODEL_PRIMARY)


def generate_text_with_model(
    request: GenerationRequest,
    model: Optional[str],
) -> GenerationResult:
    """
    Generate text using a specific hosted LLM model.

    Args:
        request: The generation request containing prompt and parameters.
        model: The model name to use. If None, returns failure.

    Returns:
        GenerationResult with success status, generated text, and metadata.
    """
    if not model:
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=None,
            error="No model specified",
        )

    base_url = LLM_BASE_URL
    if not base_url:
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error="LLM_BASE_URL not configured",
        )

    api_key = LLM_API_KEY
    if not api_key:
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error="LLM_API_KEY not configured",
        )

    start_time = time.time()

    try:
        with httpx.Client(timeout=AI_TIMEOUT_SECONDS) as client:
            response = client.post(
                f"{base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": request.prompt}],
                    "temperature": request.temperature,
                },
            )

            response.raise_for_status()
            data = response.json()

            content = data["choices"][0]["message"]["content"]
            latency_ms = int((time.time() - start_time) * 1000)

            return GenerationResult(
                success=True,
                text=content.strip() if content else None,
                provider="hosted",
                model=model,
                latency_ms=latency_ms,
            )

    except httpx.HTTPStatusError as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error=f"HTTP error {e.response.status_code}",
            latency_ms=latency_ms,
        )
    except httpx.RequestError as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error=f"Request error: {str(e)}",
            latency_ms=latency_ms,
        )
    except (KeyError, IndexError) as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error=f"Invalid response format: {str(e)}",
            latency_ms=latency_ms,
        )
    except Exception as e:
        latency_ms = int((time.time() - start_time) * 1000)
        return GenerationResult(
            success=False,
            text=None,
            provider="hosted",
            model=model,
            error=f"Unexpected error: {str(e)}",
            latency_ms=latency_ms,
        )
