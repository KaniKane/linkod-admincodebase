"""
AI refinement service - Compatibility layer for LINKod Admin backend.

This module provides the public API for text refinement. It delegates to the
internal LLM pipeline which contains classification, validation, and retries.

Public API:
    refine_text(raw_text: str) -> Optional[str]

For internal use, import directly from llm.pipeline:
    from llm.pipeline import generate_announcement
"""

import re
from typing import Optional

# Import the pipeline entrypoint
from llm.pipeline import generate_announcement, is_official_announcement


def suggest_announcement_title(text: str) -> Optional[str]:
    """Suggest a concise title from announcement content."""
    stripped = (text or "").strip()
    if not stripped:
        return None

    lower = stripped.lower()

    def contains_any(keywords: list[str]) -> bool:
        for keyword in keywords:
            if re.search(rf"\b{re.escape(keyword)}\b", lower):
                return True
        return False

    meeting_terms = ["meeting", "miting"]

    # Prioritize specific topics first to avoid generic titles.
    if contains_any(["general assembly", "barangay assembly"]):
        return "Pahibalo: Barangay General Assembly"

    if contains_any(["sports fest", "sportsfest", "basketball", "volleyball", "tournament", "liga", "sports"]):
        if contains_any(meeting_terms):
            return "Pahibalo: Miting Alang sa Sports Fest"
        return "Pahibalo: Sports Fest sa Barangay"

    if contains_any(["public hearing", "hearing"]):
        return "Pahibalo: Public Hearing"

    if contains_any(["putol sa tubig", "water interruption", "water service", "walay tubig"]):
        return "Pahibalo: Pagputol sa Tubig"

    if contains_any(["vaccination", "bakuna", "immunization"]):
        return "Pahibalo: Bakuna"

    if contains_any(["cleanup", "clean-up", "brigada", "limpyo", "hinlo"]):
        return "Pahibalo: Brigada Limpyo"

    if contains_any(["registration", "rehistro", "civil registrar"]):
        return "Pahibalo: Rehistro"

    if contains_any(["seminar", "orientation", "training"]):
        return "Pahibalo: Seminar sa Komunidad"

    if contains_any(["relief", "assistance", "tabang"]):
        return "Pahibalo: Relief Assistance"

    if contains_any(["curfew"]):
        return "Pahibalo: Curfew"

    # Generic meeting title only after all specific categories are checked.
    if contains_any(meeting_terms):
        return "Pahibalo: Miting sa Komunidad"

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
        signature_name: Optional preferred signer name for refine output.
        signature_title: Optional preferred signer title for official output.

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


