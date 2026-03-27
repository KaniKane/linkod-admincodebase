"""
AI refinement service - Compatibility layer for LINKod Admin backend.

This module provides the public API for text refinement. It delegates to the
internal LLM pipeline which contains classification, validation, and retries.

Public API:
    refine_text(raw_text: str, ollama_base_url: str = OLLAMA_BASE_URL) -> Optional[str]

For internal use, import directly from llm.pipeline:
    from llm.pipeline import generate_announcement
"""

from typing import Optional

# Keep OLLAMA_BASE_URL constant for backward compatibility
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"

# Import the pipeline entrypoint
from llm.pipeline import generate_announcement


def refine_text(
    raw_text: str,
    ollama_base_url: str = OLLAMA_BASE_URL,
) -> Optional[str]:
    """
    Refine announcement text using the LLM pipeline.

    This function maintains backward compatibility with existing Flutter
    integration. It delegates to generate_announcement which applies pipeline
    stages (classification, retry, validation, and fallback formatting).

    Args:
        raw_text: The raw announcement text to refine.
        ollama_base_url: Optional Ollama base URL override.
                         Default is http://localhost:11434.

    Returns:
        Refined text string if successful, None if input is empty.
    """
    stripped = (raw_text or "").strip()
    if not stripped:
        return None

    refined = generate_announcement(stripped)
    refined = refined.strip()
    return refined or None


