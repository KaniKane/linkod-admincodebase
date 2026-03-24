"""
Internal LLM gateway orchestrator.

Routes generation requests through a fallback chain:
1. Primary hosted LLM
2. Hosted fallback model (if configured and different)
3. Local Ollama (in auto mode)

Includes logging and validation at each step.
"""

import logging
from typing import Optional

from config.ai_settings import (
    AI_PROVIDER_MODE,
    LLM_MODEL_PRIMARY,
    LLM_MODEL_FALLBACK,
    OLLAMA_BASE_URL,
)
from llm.types import GenerationRequest, GenerationResult
from llm.prompt_builder import build_refinement_prompt
from llm.client import generate_text, generate_text_with_model
from llm.fallback import generate_text_local_from_request
from llm.validators import validate_refinement

# Configure logging for the gateway
logger = logging.getLogger(__name__)


def refine_text_via_gateway(
    raw_text: str,
    ollama_base_url: Optional[str] = None,
) -> Optional[str]:
    """
    Refine text using the LLM gateway with fallback chain.

    Routing behavior based on AI_PROVIDER_MODE:
    - "ollama": Use local Ollama only
    - "hosted": Use hosted LLM only (primary + fallback)
    - "auto": Full chain - hosted primary -> hosted fallback -> local Ollama

    Args:
        raw_text: The raw announcement text to refine.
        ollama_base_url: Optional override for Ollama base URL.

    Returns:
        Refined text if successful, None otherwise.
    """
    if not raw_text or not raw_text.strip():
        return None

    # Build the prompt
    prompt = build_refinement_prompt(raw_text)
    request = GenerationRequest(prompt=prompt, temperature=0.0)

    mode = AI_PROVIDER_MODE
    logger.info(f"Starting refinement with mode={mode}")

    # Route based on provider mode
    if mode == "ollama":
        return _try_ollama_only(request, raw_text, ollama_base_url)

    if mode in ("hosted", "auto"):
        return _try_hosted_then_fallback(request, raw_text, ollama_base_url, mode)

    # Unknown mode - default to safe Ollama fallback
    logger.warning(f"Unknown AI_PROVIDER_MODE='{mode}', defaulting to Ollama")
    return _try_ollama_only(request, raw_text, ollama_base_url)


def _try_hosted_then_fallback(
    request: GenerationRequest,
    source_text: str,
    ollama_base_url: Optional[str],
    mode: str,
) -> Optional[str]:
    """
    Try hosted LLM primary, then fallback, then Ollama if in auto mode.

    Args:
        request: The generation request.
        source_text: Original source for validation.
        ollama_base_url: Optional Ollama override.
        mode: The provider mode (hosted or auto).

    Returns:
        Refined text if any attempt succeeds and validates, None otherwise.
    """
    # Try primary model
    primary_model = LLM_MODEL_PRIMARY
    if primary_model:
        logger.info(f"Attempting primary model: {primary_model}")
        result = generate_text(request)
        if _is_valid_result(result, source_text):
            logger.info(f"Primary model succeeded: latency={result.latency_ms}ms")
            return result.text
        logger.warning(f"Primary model failed or invalid: {result.error}")

    # Try fallback model (if different from primary and configured)
    fallback_model = LLM_MODEL_FALLBACK
    if fallback_model and fallback_model != primary_model:
        logger.info(f"Attempting hosted fallback model: {fallback_model}")
        result = generate_text_with_model(request, fallback_model)
        if _is_valid_result(result, source_text):
            logger.info(f"Hosted fallback succeeded: latency={result.latency_ms}ms")
            return result.text
        logger.warning(f"Hosted fallback failed or invalid: {result.error}")

    # If in auto mode, try local Ollama as final fallback
    if mode == "auto":
        logger.info("Attempting local Ollama fallback")
        return _try_ollama_only(request, source_text, ollama_base_url)

    # Hosted mode - no more fallbacks
    logger.error("All hosted options exhausted, no refinement produced")
    return None


def _try_ollama_only(
    request: GenerationRequest,
    source_text: str,
    ollama_base_url: Optional[str],
) -> Optional[str]:
    """
    Try local Ollama generation only.

    Args:
        request: The generation request.
        source_text: Original source for validation.
        ollama_base_url: Optional Ollama override.

    Returns:
        Refined text if successful and validates, None otherwise.
    """
    base_url = ollama_base_url or OLLAMA_BASE_URL
    logger.info(f"Attempting Ollama at {base_url}")

    result = generate_text_local_from_request(request, base_url)
    if _is_valid_result(result, source_text):
        logger.info(f"Ollama succeeded: latency={result.latency_ms}ms")
        return result.text

    logger.error(f"Ollama failed or invalid: {result.error}")
    return None


def _is_valid_result(result: GenerationResult, source_text: str) -> bool:
    """
    Check if generation result is successful and passes validation.

    Args:
        result: The generation result to check.
        source_text: Original source text for validation comparison.

    Returns:
        True if result is valid and passes quality checks.
    """
    if not result.success or not result.text:
        return False

    validation = validate_refinement(source_text, result.text)
    if not validation.ok:
        logger.warning(f"Validation failed: {validation.reason}")
        return False

    return True
