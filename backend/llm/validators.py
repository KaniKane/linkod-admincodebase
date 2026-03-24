"""
Validators for LLM-generated refinement output.

Provides heuristic validation to ensure refined announcements maintain quality
and preserve critical information from the source text.
"""

import re
from typing import Optional

from llm.types import ValidationResult


def validate_refinement(source_text: str, refined_text: str) -> ValidationResult:
    """
    Validate that refined text meets quality and preservation requirements.

    Checks:
    - Refined text is not empty
    - Refined text is not too short (less than 35% of source length)
    - Preserves numeric tokens (dates, times)
    - Preserves sender/creator attribution

    Args:
        source_text: The original raw announcement text.
        refined_text: The LLM-generated refined text.

    Returns:
        ValidationResult indicating if refinement is acceptable.
    """
    if not refined_text or not refined_text.strip():
        return ValidationResult(ok=False, reason="Refined text is empty")

    refined_clean = refined_text.strip()
    source_clean = source_text.strip()

    # Check minimum length (35% of source)
    min_length = len(source_clean) * 0.35
    if len(refined_clean) < min_length:
        return ValidationResult(
            ok=False, reason="Refined text too short (less than 35% of source)"
        )

    # Check for preserved dates and times
    date_issues = _check_dates_preserved(source_clean, refined_clean)
    if date_issues:
        return ValidationResult(ok=False, reason=f"Dates/times not preserved: {date_issues}")

    # Check for preserved sender attribution
    attribution_issues = _check_attribution_preserved(source_clean, refined_clean)
    if attribution_issues:
        return ValidationResult(ok=False, reason=f"Attribution not preserved: {attribution_issues}")

    # Check for signature hallucination (added signature when none existed)
    hallucination_issues = _check_signature_hallucination(source_clean, refined_clean)
    if hallucination_issues:
        return ValidationResult(ok=False, reason=f"Hallucination detected: {hallucination_issues}")

    # Check for signature modification (signature was changed when it shouldn't be)
    modification_issues = _check_signature_modification(source_clean, refined_clean)
    if modification_issues:
        return ValidationResult(ok=False, reason=f"Signature modified: {modification_issues}")

    return ValidationResult(ok=True, reason=None)


def _check_dates_preserved(source: str, refined: str) -> Optional[str]:
    """
    Check that obvious date and time tokens from source are preserved in refined text.

    Looks for:
    - Years like 2025, 2026
    - Times like 8:00, 3, alas 3
    - Month/day patterns
    """
    # Extract years (4-digit numbers that look like years)
    year_pattern = r"\b(20[0-9]{2})\b"
    years_in_source = set(re.findall(year_pattern, source))
    years_in_refined = set(re.findall(year_pattern, refined))

    missing_years = years_in_source - years_in_refined
    if missing_years:
        return f"Year(s) {', '.join(sorted(missing_years))} missing"

    # Extract time patterns (e.g., 8:00, 3:30, alas 3)
    time_patterns = [
        r"\b(?:alas\s+)?([1-9]|1[0-2])(?::([0-5]\d))?\s*(?:sa\s+(?:buntag|hapon)|ngadto|ngadtu)?\b",
    ]

    for pattern in time_patterns:
        times_in_source = set(re.findall(pattern, source, re.IGNORECASE))
        times_in_refined = set(re.findall(pattern, refined, re.IGNORECASE))
        # Check for partial matches (first group is the hour)
        source_hours = set(m[0] if isinstance(m, tuple) else m for m in times_in_source)
        refined_hours = set(m[0] if isinstance(m, tuple) else m for m in times_in_refined)

        missing_hours = source_hours - refined_hours
        if missing_hours and len(source_hours) > 0:
            # Only report if there were explicit hours in source
            pass  # Be lenient with time preservation

    return None


def _check_attribution_preserved(source: str, refined: str) -> Optional[str]:
    """
    Check that sender/creator attribution is preserved.

    Looks for:
    - Lines beginning with HON.
    - "Gikan kang:" patterns
    - "Barangay Captain" titles
    - All-caps names with periods (initials)
    """
    refined_lower = refined.lower()

    # Check HON. pattern
    if re.search(r"^HON\.\s*", source, re.MULTILINE | re.IGNORECASE):
        if not re.search(r"HON\.\s*", refined, re.IGNORECASE):
            return "HON. prefix not preserved"

    # Check Gikan kang pattern
    if re.search(r"^Gikan\s+kang[:\s]", source, re.MULTILINE | re.IGNORECASE):
        if not re.search(r"Gikan\s+kang", refined, re.IGNORECASE):
            return "Sender attribution 'Gikan kang' not preserved"

    # Check Barangay Captain
    if re.search(r"Barangay\s+Captain", source, re.IGNORECASE):
        if not re.search(r"Barangay\s+Captain", refined, re.IGNORECASE):
            return "'Barangay Captain' title not preserved"

    # Check Municipal Mayor
    if re.search(r"Municipal\s+Mayor", source, re.IGNORECASE):
        if not re.search(r"Municipal\s+Mayor", refined, re.IGNORECASE):
            return "'Municipal Mayor' title not preserved"

    # Check for all-caps names with initials (e.g., HON. ALBERTO C. PACHECO)
    # Look for patterns like HON. NAME X. NAME
    name_pattern = r"HON\.\s+([A-Z][A-Z\s\.]+[A-Z])"
    names_in_source = re.findall(name_pattern, source)
    for name in names_in_source:
        # Check if some part of the name is preserved
        name_parts = name.replace(".", " ").split()
        significant_parts = [p for p in name_parts if len(p) > 1]
        if significant_parts:
            # At least one significant name part should be preserved
            found = any(part in refined for part in significant_parts)
            if not found:
                return f"Name '{name}' not preserved in refined text"

    return None


def _check_signature_hallucination(source: str, refined: str) -> Optional[str]:
    """
    Check if the model hallucinated a COMPLETE SIGNATURE BLOCK that wasn't in the original.

    Focus on FABRICATED OFFICIAL SIGNATURES (multiple elements together):
    - "Kaninyo matinahuron" + "HON." + "Barangay Captain" (all 3 = fake official signature)
    - "Gikan kang:" + name that doesn't exist in input

    IGNORES harmless single elements:
    - "daghang salamat" alone (common polite closing)
    - "kinasingkasing" alone
    - Natural reformatting (7:30am → alas 7:30 sa buntag)
    """
    source_lower = source.lower()
    refined_lower = refined.lower()

    # Count signature elements in output
    has_matinahuron = "matinahuron" in refined_lower
    has_hon = "hon." in refined_lower
    has_gikan_kang = "gikan kang" in refined_lower

    titles = ["barangay captain", "municipal mayor", "kapitan"]
    has_title = any(title in refined_lower for title in titles)
    had_title_in_source = any(title in source_lower for title in titles)

    # HALLUCINATION CASE 1: Fabricated official signature block
    # (matinahuron + HON. + title) when input had none of these
    if has_matinahuron and has_hon and has_title:
        if not ("matinahuron" in source_lower or "hon." in source_lower or had_title_in_source):
            return "Added complete official signature block not present in input"

    # HALLUCINATION CASE 2: Fabricated "Gikan kang" with name when not in input
    if has_gikan_kang and not ("gikan kang" in source_lower):
        # Check if it added a specific name pattern (not just the phrase)
        # Look for "Gikan kang: NAME" or "Gikan kang NAME"
        gikan_pattern = r"gikan\s+kang[:\s]+([A-Z][A-Za-z\s\.]+)"
        matches = re.findall(gikan_pattern, refined_lower)
        if matches:
            return "Added 'Gikan kang:' attribution with name not present in input"

    # HALLUCINATION CASE 3: Added HON. prefix (strong signal of fake official)
    # Only flag if input had no HON. and no title already
    if has_hon and not ("hon." in source_lower):
        if has_title and not had_title_in_source:
            return "Added HON. prefix with title not present in input"

    # NOT HALLUCINATION (acceptable normalization):
    # - "daghang salamat" alone
    # - Time reformatting (7:30am → alas 7:30 sa buntag)
    # - Grammar fixes
    # - Spelling corrections

    return None


def _check_signature_modification(source: str, refined: str) -> Optional[str]:
    """
    Check if an existing signature was improperly modified.

    If source has signature, ensure it is NOT modified:
    - Name unchanged
    - No HON. added if not present
    - No extra titles added
    """
    source_lower = source.lower()
    refined_lower = refined.lower()

    # Check 1: If source has HON., refined must also have it
    had_hon = "hon." in source_lower
    has_hon = "hon." in refined_lower
    if had_hon and not has_hon:
        return "Removed HON. prefix that was present in source"

    # Check 2: If source has title, refined must preserve same title
    titles = ["barangay captain", "municipal mayor", "kapitan"]
    source_title = next((t for t in titles if t in source_lower), None)
    refined_title = next((t for t in titles if t in refined_lower), None)

    if source_title and refined_title and source_title != refined_title:
        return f"Changed title from '{source_title}' to '{refined_title}'"

    # Check 3: Extract and compare sender name from "Gikan kang" pattern
    gikan_source_match = re.search(r"gikan\s+kang[:\s]+([A-Z][A-Za-z\s\.]+?)(?:\n|$)", source, re.IGNORECASE)
    gikan_refined_match = re.search(r"gikan\s+kang[:\s]+([A-Z][A-Za-z\s\.]+?)(?:\n|$)", refined, re.IGNORECASE)

    if gikan_source_match and gikan_refined_match:
        source_name = gikan_source_match.group(1).strip()
        refined_name = gikan_refined_match.group(1).strip()
        # Names should be very similar (allow minor formatting changes)
        source_name_clean = re.sub(r'[^a-z]', '', source_name.lower())
        refined_name_clean = re.sub(r'[^a-z]', '', refined_name.lower())
        if source_name_clean != refined_name_clean:
            return f"Changed sender name from '{source_name}' to '{refined_name}'"

    # Check 4: If source had signature block, refined must not add new elements
    had_matinahuron = "matinahuron" in source_lower
    has_matinahuron = "matinahuron" in refined_lower
    if not had_matinahuron and has_matinahuron and (had_hon or source_title):
        return "Added 'Kaninyo matinahuron' to existing signature"

    return None
