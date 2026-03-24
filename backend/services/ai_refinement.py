"""
AI refinement service - Compatibility layer for LINKod Admin backend.

This module provides the public API for text refinement. It delegates to the
internal LLM gateway which handles routing between hosted LLM and local Ollama
with proper fallback chains.

Public API:
    refine_text(raw_text: str, ollama_base_url: str = OLLAMA_BASE_URL) -> Optional[str]

For internal use, import directly from llm.gateway:
    from llm.gateway import refine_text_via_gateway
"""

from typing import Optional

# Keep OLLAMA_BASE_URL constant for backward compatibility
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"

# Import the gateway for delegation
from llm.gateway import refine_text_via_gateway


def refine_text(
    raw_text: str,
    ollama_base_url: str = OLLAMA_BASE_URL,
) -> Optional[str]:
    """
    Refine announcement text using the LLM gateway.

    This function maintains backward compatibility with existing Flutter
    integration. It delegates to refine_text_via_gateway which implements
    the full fallback chain (hosted primary -> hosted fallback -> local Ollama).

    Args:
        raw_text: The raw announcement text to refine.
        ollama_base_url: Optional Ollama base URL override.
                         Default is http://localhost:11434.

    Returns:
        Refined text string if successful, None if all providers fail
        or if input is empty.
    """
    return refine_text_via_gateway(raw_text, ollama_base_url=ollama_base_url)


