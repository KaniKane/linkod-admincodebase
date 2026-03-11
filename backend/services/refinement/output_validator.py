"""
Output validator for the refinement pipeline.

Validates that generated output meets quality criteria and preserves protected facts.
Implements retry logic when validation fails.
"""

import re
from typing import Dict, List, Any, Tuple, Optional

from .entity_extractor import verify_facts_preserved


def validate_output(
    refined_text: str,
    original_text: str,
    protected_facts: Dict[str, List[str]],
    is_retry: bool = False
) -> Tuple[bool, List[str], Dict[str, Any]]:
    """
    Validate the refined output against quality criteria.
    
    Args:
        refined_text: The generated refined text
        original_text: The original draft text
        protected_facts: Facts that must be preserved
        is_retry: Whether this is a retry attempt
        
    Returns:
        Tuple of (is_valid, list_of_errors, metadata_dict)
    """
    errors = []
    metadata = {}
    
    # Skip validation for empty output
    if not refined_text or not refined_text.strip():
        errors.append("Output is empty")
        return False, errors, {"empty": True}
    
    # 1. Check length is reasonable
    length_check = _check_length(refined_text, original_text)
    if not length_check["valid"]:
        errors.append(length_check["error"])
    metadata["length_ratio"] = length_check.get("ratio", 0)
    
    # 2. Check for expansion (new content not in source)
    expansion_check = _check_expansion(refined_text, original_text)
    if expansion_check["has_expansion"]:
        errors.append(f"Output adds unsupported content: {expansion_check['details']}")
    metadata["expansion_detected"] = expansion_check["has_expansion"]
    metadata["added_phrases"] = expansion_check.get("added_phrases", [])
    
    # 3. Verify protected facts are preserved
    fact_check = verify_facts_preserved(protected_facts, refined_text)
    if not fact_check["all_preserved"]:
        errors.append(f"Missing protected facts: {', '.join(fact_check['missing'])}")
    metadata["facts_preserved"] = fact_check["all_preserved"]
    metadata["missing_facts"] = fact_check["missing"]
    
    # 4. Check for hallucinated dates/times
    hallucination_check = _check_hallucinated_facts(refined_text, protected_facts)
    if hallucination_check["suspicious"]:
        errors.append(f"Possible hallucination: {hallucination_check['details']}")
    metadata["suspicious_additions"] = hallucination_check["suspicious"]
    
    # 5. Check language is Cebuano-based
    language_check = _check_language(refined_text)
    if not language_check["valid"]:
        errors.append(language_check["error"])
    metadata["language_score"] = language_check.get("score", 0)
    
    # 6. Check no English explanation text
    explanation_check = _check_no_explanation(refined_text)
    if not explanation_check["valid"]:
        errors.append(explanation_check["error"])
    
    # 7. Check detail level preservation for short inputs
    short_input_check = _check_detail_level_preserved(refined_text, original_text)
    if not short_input_check["valid"]:
        errors.append(short_input_check["error"])
    metadata["detail_preserved"] = short_input_check.get("detail_preserved", True)
    
    # 8. Check structure (basic Cebuano patterns)
    structure_check = _check_structure(refined_text)
    metadata["has_valid_structure"] = structure_check["valid"]
    
    # For retry attempts, be more lenient
    if is_retry:
        # On retry, only fail on critical errors
        critical_errors = [e for e in errors if any(crit in e for crit in ["Missing protected facts", "Output is empty", "adds unsupported content"])]
        is_valid = len(critical_errors) == 0
        return is_valid, critical_errors, metadata
    
    is_valid = len(errors) == 0
    return is_valid, errors, metadata


def _check_length(refined: str, original: str) -> Dict[str, Any]:
    """Check if refined text length is reasonable."""
    refined_words = len(refined.strip().split())
    original_words = len(original.strip().split())
    
    if refined_words == 0:
        return {"valid": False, "error": "Output is empty", "ratio": 0}
    
    if original_words == 0:
        return {"valid": True, "ratio": 1.0}
    
    ratio = refined_words / original_words
    
    # For minimal editing, output should be within 50% to 200% of original
    # (was 50% to 300%, now stricter)
    if ratio < 0.5:
        return {
            "valid": False,
            "error": f"Output too short ({ratio:.1%} of original - {refined_words} vs {original_words} words)",
            "ratio": ratio
        }
    
    if ratio > 2.0:
        return {
            "valid": False,
            "error": f"Output too long ({ratio:.1%} of original - {refined_words} vs {original_words} words)",
            "ratio": ratio
        }
    
    return {"valid": True, "ratio": ratio}


def _check_hallucinated_facts(refined: str, original_facts: Dict[str, List[str]]) -> Dict[str, Any]:
    """Check for potentially hallucinated dates, times, or numbers."""
    suspicious = False
    details = []
    
    # Extract dates from refined
    refined_dates = _extract_dates_simple(refined)
    original_dates = set(d.lower() for d in original_facts.get("dates", []))
    
    # Check for dates in refined that weren't in original
    for date in refined_dates:
        date_lower = date.lower()
        if not any(date_lower in orig or orig in date_lower for orig in original_dates):
            # Could be hallucination, but might also be formatting change
            suspicious = True
            details.append(f"Date '{date}' not in original facts")
    
    # Extract numbers from refined
    refined_numbers = _extract_numbers_simple(refined)
    original_numbers = set(n.lower() for n in original_facts.get("numbers", []))
    
    # Check for significant numbers that weren't in original
    for num in refined_numbers:
        num_lower = num.lower()
        # Skip if it's a substring of any original number
        if not any(num_lower in orig or orig in num_lower for orig in original_numbers):
            suspicious = True
            details.append(f"Number '{num}' not in original facts")
    
    return {
        "suspicious": suspicious,
        "details": "; ".join(details) if details else ""
    }


def _extract_dates_simple(text: str) -> List[str]:
    """Simple date extraction for validation."""
    patterns = [
        r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Enero|Pebrero|Marso|Abril|Mayo|Hunyo|Hulyo|Agosto|Septiyembre|Oktubre|Nobyembre|Disyembre)\s+\d{1,2}(?:,\s+\d{4})?\b',
        r'\b(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Linggo)\b',
    ]
    
    dates = []
    for pattern in patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        dates.extend(matches)
    
    return list(set(dates))


def _extract_numbers_simple(text: str) -> List[str]:
    """Simple number extraction for validation."""
    # Look for 4+ digit numbers (likely phone numbers, years, amounts)
    patterns = [
        r'\b\d{4,}\b',  # 4+ digit numbers
        r'\b09\d{9}\b',  # Phone numbers
    ]
    
    numbers = []
    for pattern in patterns:
        matches = re.findall(pattern, text)
        numbers.extend(matches)
    
    return list(set(numbers))


def _check_language(text: str) -> Dict[str, Any]:
    """Check if text appears to be Tandaganon (not generic Cebuano or Tagalog)."""
    text_lower = text.lower()
    
    # Import patterns from examples module
    from .examples import TANDAGANON_PATTERNS, PHRASES_TO_AVOID
    
    # Check for prohibited formal/literary patterns (instant fail)
    formal_violations = []
    for category, phrases in PHRASES_TO_AVOID.items():
        for phrase in phrases:
            if phrase in text_lower:
                formal_violations.append(phrase)
    
    # Check for positive Tandaganon patterns
    positive_matches = {}
    positive_score = 0
    
    for category, patterns in TANDAGANON_PATTERNS.items():
        matches = []
        for pattern in patterns:
            if pattern.lower() in text_lower:
                matches.append(pattern)
        if matches:
            positive_matches[category] = matches
            # Simple scoring: each match adds points based on category importance
            if category == "preferred_openings":
                positive_score += len(matches) * 2.0
            elif category == "preferred_reminders":
                positive_score += len(matches) * 1.5
            else:
                positive_score += len(matches) * 0.5
    
    # Basic Cebuano markers (acceptable but not distinctive)
    cebuano_markers = [
        "ang", "sa", "nga", "og", "ug", "kay", "si", "ni", "diha", "adto",
        "nag", "mag", "gi", "pag", "ka", "pa", "mi", "mo", "sila", "kita",
        "barangay", "tanod", "kapitan", "kagawad",
        "miting", "tambong", "linis", "bakuna", "permit", "clearance"
    ]
    
    # English words that shouldn't dominate
    english_indicators = [
        "the", "is", "are", "was", "were", "will", "shall", "would", "could",
        "should", "may", "might", "can", "cannot", "please", "thank you",
        "announcement", "notice", "informed", "advised", "instructed"
    ]
    
    cebuano_count = sum(1 for marker in cebuano_markers if marker in text_lower)
    english_count = sum(1 for marker in english_indicators if marker in text_lower)
    
    words = text.split()
    total_words = len(words)
    
    if total_words == 0:
        return {"valid": False, "error": "No words found", "score": 0}
    
    # If formal/literary patterns detected, FAIL validation
    if formal_violations:
        return {
            "valid": False,
            "error": f"Uses formal/literary/Tagalog patterns: {', '.join(formal_violations[:3])}",
            "score": -1,
            "formal_violations": formal_violations,
            "positive_matches": positive_matches
        }
    
    # Check sentence length (Tandaganon uses shorter sentences)
    sentences = re.split(r'[.!?]+', text)
    sentences = [s.strip() for s in sentences if s.strip()]
    long_sentences = sum(1 for s in sentences if len(s.split()) > 25)
    
    if long_sentences > 1:
        positive_score -= long_sentences * 0.5  # Penalize long sentences
    
    # Bonus for having preferred opening
    has_good_opening = (
        "nagpahibalo ang barangay" in text_lower or
        "sa tanang residente" in text_lower or
        "pahimangno" in text_lower
    )
    
    if has_good_opening:
        positive_score += 2.0
    
    # Must have some Cebuano markers and not too many English
    if cebuano_count < 2 and english_count > 5:
        return {
            "valid": False,
            "error": "Output appears to be mostly English, not Cebuano/Tandaganon",
            "score": positive_score,
            "positive_matches": positive_matches
        }
    
    # Final score combines positive patterns with basic language presence
    final_score = positive_score + (cebuano_count * 0.2) - (english_count * 0.3)
    
    return {
        "valid": True, 
        "score": final_score,
        "positive_matches": positive_matches,
        "has_good_opening": has_good_opening,
        "long_sentences": long_sentences
    }


def _check_no_explanation(text: str) -> Dict[str, Any]:
    """Check that output doesn't contain English explanations."""
    explanation_patterns = [
        r'^here is',
        r'^this is',
        r'^refined text',
        r'^output:',
        r'^translation:',
        r'^translated',
        r'^note:',
        r'^explanation:',
        r'\(note:',
        r'\(explanation:',
    ]
    
    text_lower = text.lower().strip()
    
    for pattern in explanation_patterns:
        if re.search(pattern, text_lower):
            return {
                "valid": False,
                "error": f"Output contains explanation prefix: '{pattern}'"
            }
    
    return {"valid": True}


def _check_structure(text: str) -> Dict[str, Any]:
    """Check if text has basic valid announcement structure."""
    text_lower = text.lower()
    
    # Common Cebuano announcement openings
    valid_openings = [
        "nagpahibalo", "gitawag", "gipahibalo", "pahibalo",
        "sa tanang", "sa mga", "alang sa"
    ]
    
    # Check if it has a valid opening pattern
    has_valid_opening = any(opening in text_lower[:100] for opening in valid_openings)
    
    # Check for reasonable sentence structure
    sentences = re.split(r'[.!?]+', text)
    sentences = [s.strip() for s in sentences if s.strip()]
    
    has_multiple_sentences = len(sentences) >= 2
    
    return {
        "valid": has_valid_opening or has_multiple_sentences,
        "has_valid_opening": has_valid_opening,
        "sentence_count": len(sentences)
    }


def determine_fallback_action(
    original_text: str,
    refined_text: Optional[str],
    validation_errors: List[str],
    is_retry: bool
) -> Tuple[str, bool, List[str]]:
    """
    Determine what to return when validation fails.
    RELAXED: Only fallback on severe errors, not minor issues.
    """
    warnings = []
    
    # If retry already failed, return original
    if is_retry:
        warnings.append("Refinement failed after retry; returning original text")
        return original_text, True, warnings
    
    # If no refined text at all, return original
    if not refined_text:
        warnings.append("No refinement generated; returning original text")
        return original_text, True, warnings
    
    # RELAXED: Only fallback on severe errors
    severe_errors = [e for e in validation_errors if any(severe in e.lower() for severe in [
        "output is empty", "output too long", "output too short", "mostly english"
    ])]
    
    # If only minor errors (expansion, missing facts), still return refined
    if len(severe_errors) == 0:
        warnings.append(f"Minor validation issues: {'; '.join(validation_errors[:2])}")
        return refined_text, False, warnings
    
    # Severe errors - return original
    warnings.append(f"Severe validation errors ({len(severe_errors)}); returning original text")
    return original_text, True, warnings


def format_validation_report(
    is_valid: bool,
    errors: List[str],
    metadata: Dict[str, Any]
) -> str:
    """
    Format a validation report for logging.
    
    Args:
        is_valid: Whether validation passed
        errors: List of validation errors
        metadata: Validation metadata
        
    Returns:
        Formatted report string
    """
    lines = ["Validation Report:"]
    lines.append(f"  Valid: {is_valid}")
    
    if errors:
        lines.append("  Errors:")
        for error in errors:
            lines.append(f"    - {error}")
    
    lines.append("  Metadata:")
    for key, value in metadata.items():
        if isinstance(value, list) and len(value) > 3:
            lines.append(f"    {key}: [{len(value)} items]")
        else:
            lines.append(f"    {key}: {value}")
    
    return "\n".join(lines)


def _check_expansion(refined: str, original: str) -> Dict[str, Any]:
    """
    Check if the refined text adds unsupported content not in the source.
    RELAXED for meeting announcements - allows implicit invitation language.
    """
    refined_lower = refined.lower()
    original_lower = original.lower()
    
    # Check if this is a meeting context (where invitation language is implicit)
    is_meeting_context = any(word in original_lower for word in [
        "meeting", "miting", "tigum", "pulong", "conference",
        "join", "wants to", "attend", "tambong", "apil"
    ])
    
    # Suspicious added phrases that indicate expansion
    suspicious_additions = {
        "closing": [
            "daghang salamat",
            "salamat sa inyong pagpakabana",
            "salamat sa kooperasyon",
            "salamat sa inyong kooperasyon"
        ],
        "timing": [
            "karong hapon",
            "karong buntag",
            "karong gabii"
        ],
        "filler": [
            "alang sa kaayohan",
            "para sa tanan",
            "alang sa tanan",
            "para sa kaayohan",
            "maayo alang sa tanan"
        ],
        "opening": [
            "nagpahibalo ang barangay"
        ]
    }
    
    # For non-meeting contexts, also check these
    if not is_meeting_context:
        suspicious_additions["invitation"] = [
            "gihangyo", "ginaimbitar", "gidapit", "imbitado"
        ]
        suspicious_additions["action"] = [
            "pag-apil", "pagtambong", "pagdala", "pagsulod"
        ]
    
    added_phrases = []
    
    for category, phrases in suspicious_additions.items():
        for phrase in phrases:
            if phrase in refined_lower and phrase not in original_lower:
                added_phrases.append(f"{category}:{phrase}")
    
    # Check for significant sentence count increase
    refined_sentences = len([s for s in re.split(r'[.!?]+', refined) if s.strip()])
    original_sentences = len([s for s in re.split(r'[.!?]+', original) if s.strip()])
    
    # If added 2+ sentences, likely expansion
    if refined_sentences > original_sentences + 1:
        added_phrases.append(f"structure:added {refined_sentences - original_sentences} new sentences")
    
    # Check for significant word count increase (>2.5x is suspicious)
    refined_words = len(refined.split())
    original_words = len(original.split())
    if original_words > 0 and refined_words > original_words * 2.5:
        added_phrases.append(f"length:output too long ({refined_words} vs {original_words} words)")
    
    has_expansion = len(added_phrases) > 0
    
    return {
        "has_expansion": has_expansion,
        "added_phrases": added_phrases,
        "details": "; ".join(added_phrases[:3]) if added_phrases else ""
    }


def _check_detail_level_preserved(refined: str, original: str) -> Dict[str, Any]:
    """
    Check if output preserves the detail level of short inputs.
    
    Short inputs should not be expanded with extra clauses or details.
    """
    original_words = len(original.split())
    refined_words = len(refined.split())
    
    # Only strict for short inputs (<= 25 words)
    if original_words > 25:
        return {"valid": True, "detail_preserved": True}
    
    # For short inputs, check if significantly expanded
    word_ratio = refined_words / max(original_words, 1)
    
    # Short input should not expand by more than 50%
    if word_ratio > 1.5:
        return {
            "valid": False,
            "error": f"Short input expanded too much ({word_ratio:.1f}x): {original_words} → {refined_words} words",
            "detail_preserved": False,
            "ratio": word_ratio
        }
    
    # Check sentence count for short inputs
    original_sentences = len([s for s in re.split(r'[.!?]+', original) if s.strip()])
    refined_sentences = len([s for s in re.split(r'[.!?]+', refined) if s.strip()])
    
    # If 1-sentence input became 2+ sentences, likely expansion
    if original_sentences == 1 and refined_sentences > 1:
        return {
            "valid": False,
            "error": f"Single sentence split into {refined_sentences} sentences (expansion detected)",
            "detail_preserved": False
        }
    
    return {"valid": True, "detail_preserved": True}
