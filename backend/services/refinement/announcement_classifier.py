"""
Rule-based announcement classifier for the refinement pipeline.

Uses keyword matching to classify announcements into predefined types.
Lightweight and deterministic - no AI required.
"""

from typing import Optional

from .examples import get_classification_keywords


# Fallback type when no match found
DEFAULT_TYPE = "general_announcement"


def classify_announcement(text: str) -> str:
    """
    Classify announcement type based on keyword matching.
    
    Args:
        text: The announcement text to classify
        
    Returns:
        Announcement type string (e.g., "meeting_notice", "health_advisory")
    """
    if not text or not text.strip():
        return DEFAULT_TYPE
    
    text_lower = text.lower()
    keywords_map = get_classification_keywords()
    
    # Count keyword matches for each type
    scores = {}
    for ann_type, keywords in keywords_map.items():
        score = 0
        for keyword in keywords:
            keyword_lower = keyword.lower()
            # Count occurrences (weighted by keyword length for specificity)
            count = text_lower.count(keyword_lower)
            if count > 0:
                # Longer keywords get higher weight (more specific)
                weight = len(keyword_lower)
                score += count * weight
        scores[ann_type] = score
    
    # Find the type with highest score
    if scores:
        best_type = max(scores, key=scores.get)
        best_score = scores[best_type]
        
        # Only return a type if we have a minimum score threshold
        # This prevents misclassification when only weak signals exist
        if best_score >= 3:  # Minimum threshold
            return best_type
    
    return DEFAULT_TYPE


def classify_with_confidence(text: str) -> tuple:
    """
    Classify announcement and return confidence score.
    
    Args:
        text: The announcement text to classify
        
    Returns:
        Tuple of (announcement_type, confidence_score)
        confidence_score is 0.0 to 1.0
    """
    if not text or not text.strip():
        return DEFAULT_TYPE, 0.0
    
    text_lower = text.lower()
    keywords_map = get_classification_keywords()
    
    # Calculate scores
    scores = {}
    for ann_type, keywords in keywords_map.items():
        score = 0
        for keyword in keywords:
            keyword_lower = keyword.lower()
            count = text_lower.count(keyword_lower)
            if count > 0:
                weight = len(keyword_lower)
                score += count * weight
        scores[ann_type] = score
    
    if not scores or sum(scores.values()) == 0:
        return DEFAULT_TYPE, 0.0
    
    best_type = max(scores, key=scores.get)
    best_score = scores[best_type]
    total_score = sum(scores.values())
    
    # Confidence is the ratio of best score to total score
    # But also factor in absolute score for low-signal texts
    if best_score < 3:
        confidence = 0.3  # Low confidence for weak signal
    else:
        confidence = best_score / max(total_score, best_score)
        # Boost confidence for clear signals
        if best_score > 20:
            confidence = min(0.95, confidence + 0.2)
    
    return best_type, round(confidence, 2)


def get_type_description(ann_type: str) -> str:
    """
    Get a human-readable description of an announcement type.
    
    Args:
        ann_type: The announcement type string
        
    Returns:
        Human-readable description
    """
    descriptions = {
        "meeting_notice": "Meeting or assembly notice",
        "community_event": "Community event or celebration",
        "clean_up_drive": "Clean-up drive or environmental activity",
        "health_advisory": "Health service or medical advisory",
        "government_service": "Government service or program",
        "emergency_notice": "Emergency or service interruption notice",
        "reminder_deadline": "Reminder or deadline notice",
        "general_announcement": "General announcement or information"
    }
    
    return descriptions.get(ann_type, "General announcement")


def get_type_structure_hint(ann_type: str) -> str:
    """
    Get a structural hint for a specific announcement type.
    
    Args:
        ann_type: The announcement type string
        
    Returns:
        Brief structural guidance
    """
    hints = {
        "meeting_notice": "Focus on who, when, where, and purpose of meeting",
        "community_event": "Focus on activity details, participation, and logistics",
        "clean_up_drive": "Focus on schedule, area, participants, and materials",
        "health_advisory": "Focus on service, eligibility, schedule, and requirements",
        "government_service": "Focus on service details, requirements, and process",
        "emergency_notice": "Focus on urgency, what/where/when, and action needed",
        "reminder_deadline": "Focus on deadline, requirements, and consequences",
        "general_announcement": "Focus on clear information delivery"
    }
    
    return hints.get(ann_type, "Focus on clear communication")
