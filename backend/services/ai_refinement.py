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
from llm.pipeline import generate_announcement, is_official_announcement


def suggest_announcement_title(text: str) -> Optional[str]:
    """Suggest a concise title from announcement content."""
    stripped = (text or "").strip()
    if not stripped:
        return None

    lower = stripped.lower()

    title_rules = [
        (
            ["general assembly", "barangay assembly"],
            "Pahibalo: Barangay General Assembly",
        ),
        (
            ["public hearing", "hearing"],
            "Pahibalo: Public Hearing",
        ),
        (
            ["meeting", "miting"],
            "Pahibalo: Miting sa Komunidad",
        ),
        (
            ["putol sa tubig", "water interruption", "water service"],
            "Pahibalo: Pagputol sa Tubig",
        ),
        (
            ["vaccination", "bakuna", "immunization"],
            "Pahibalo: Bakuna",
        ),
        (
            ["cleanup", "clean-up", "brigada"],
            "Pahibalo: Community Clean-up Drive",
        ),
        (
            ["registration", "rehistro", "civil registrar"],
            "Pahibalo: Rehistro",
        ),
        (
            ["seminar", "orientation", "training"],
            "Pahibalo: Seminar sa Komunidad",
        ),
        (
            ["relief", "assistance", "tabang"],
            "Pahibalo: Relief Assistance",
        ),
        (
            ["curfew"],
            "Pahibalo: Curfew",
        ),
    ]

    for keywords, suggested in title_rules:
        if any(k in lower for k in keywords):
            return suggested

    if is_official_announcement(stripped):
        return "Pahibalo: Opisyal nga Anunsyo sa Barangay"

    return "Pahibalo: Anunsyo sa Komunidad"


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
        Refined text string if successful.

    Raises:
        ValueError: If the announcement is empty or shorter than 10 characters.
    """
    stripped = _normalize_and_validate_raw_text(raw_text)

    refined = generate_announcement(
        stripped,
        signature_name=signature_name,
        signature_title=signature_title,
    )
    refined = refined.strip()
    return refined or None


