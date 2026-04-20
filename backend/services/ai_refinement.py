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


def refine_text(
    raw_text: str,
    ollama_base_url: str = OLLAMA_BASE_URL,
    signature_name: str | None = None,
    signature_title: str | None = None,
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
        signature_name: Optional preferred signer name for official outputs.
        signature_title: Optional preferred signer title for official outputs.

    Returns:
        Refined text string if successful, None if input is empty.
    """
    stripped = (raw_text or "").strip()
    if not stripped:
        return None

    refined = generate_announcement(
        stripped,
        signature_name=signature_name,
        signature_title=signature_title,
    )
    refined = refined.strip()
    return refined or None


