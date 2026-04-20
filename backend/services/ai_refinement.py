"""
AI refinement service - Compatibility layer for LINKod Admin backend.

This module provides the public API for text refinement. It delegates to the
internal LLM pipeline which contains classification, validation, and retries.

Public API:
    refine_text(raw_text: str) -> Optional[str]

For internal use, import directly from llm.pipeline:
    from llm.pipeline import generate_announcement
"""

from typing import Optional

# Import the pipeline entrypoint
from llm.pipeline import generate_announcement


def _normalize_and_validate_raw_text(raw_text: str) -> str:
    """Trim input and enforce the minimum announcement length."""
    stripped = (raw_text or "").strip()
    if not stripped:
        raise ValueError("Announcement content cannot be empty.")

    if len(stripped) < 10:
        raise ValueError("Announcement must be at least 10 characters.")

    return stripped


def refine_text(
    raw_text: str,
) -> Optional[str]:
    """
    Refine announcement text using the LLM pipeline.

    This function maintains backward compatibility with existing Flutter
    integration. It delegates to generate_announcement which applies pipeline
    stages (classification, retry, validation, and fallback formatting).

    Args:
        raw_text: The raw announcement text to refine.

    Returns:
        Refined text string if successful.

    Raises:
        ValueError: If the announcement is empty or shorter than 10 characters.
    """
    stripped = _normalize_and_validate_raw_text(raw_text)

    refined = generate_announcement(stripped)
    refined = refined.strip()
    return refined or None


