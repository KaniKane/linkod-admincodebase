"""
Prompt builder for the refinement pipeline.

Builds adaptive prompts based on input length:
- SHORT (≤25 words): Ultra-minimal, no examples, no patterns
- MEDIUM (26-120 words): Moderate with optional example
- LONG (>120 words OR multi-paragraph): Conservative, no examples/patterns

Includes prompt size safeguard (>2500 chars → auto-trim).
"""

import re
from typing import Optional, Dict, List

from .examples import get_examples_for_type, format_patterns_for_prompt
from .prompt_templates import (
    build_prompt_short,
    build_prompt_medium, 
    build_prompt_long,
    build_prompt as _legacy_build_prompt
)

# Constants for adaptive modes
SHORT_INPUT_WORDS = 25
MEDIUM_INPUT_WORDS = 120
PROMPT_SIZE_LIMIT = 2500


def _is_short_input(text: str) -> bool:
    """
    Determine if text qualifies as short input (≤25 words or 1 sentence).
    
    Args:
        text: The draft text to check
        
    Returns:
        True if input is short
    """
    word_count = len(text.split())
    sentence_count = len([s for s in re.split(r'[.!?]+', text) if s.strip()])
    
    return word_count <= SHORT_INPUT_WORDS or sentence_count == 1


def _is_long_input(text: str) -> bool:
    """
    Determine if text qualifies as long input (>120 words OR multi-paragraph).
    
    Args:
        text: The draft text to check
        
    Returns:
        True if input is long
    """
    word_count = len(text.split())
    paragraph_count = len([p for p in text.split('\n\n') if p.strip()])
    
    return word_count > MEDIUM_INPUT_WORDS or paragraph_count > 1


def _get_input_mode(text: str) -> str:
    """
    Determine the refinement mode based on input length.
    
    Args:
        text: The draft text
        
    Returns:
        Mode string: "short", "medium", or "long"
    """
    if _is_short_input(text):
        return "short"
    elif _is_long_input(text):
        return "long"
    else:
        return "medium"


def _apply_prompt_size_safeguard(prompt: str, draft_text: str, protected_facts: dict) -> str:
    """
    Apply safeguard if prompt exceeds 2500 characters.
    Removes examples and patterns, keeps only essential rules.
    
    Args:
        prompt: The original prompt
        draft_text: The draft text (for rebuilding if needed)
        protected_facts: Protected facts dict
        
    Returns:
        Potentially trimmed prompt
    """
    if len(prompt) <= PROMPT_SIZE_LIMIT:
        return prompt
    
    # Prompt too large - strip down to essentials
    # Rebuild with minimal components
    return build_prompt_long(draft_text, protected_facts)


def build_refinement_prompt(
    draft_text: str,
    announcement_type: str,
    protected_facts: dict,
    max_examples: int = 1
) -> str:
    """
    Build an adaptive refinement prompt based on input length.
    
    Args:
        draft_text: The original draft text
        announcement_type: Classified type
        protected_facts: Dict with dates, times, locations, names, numbers
        max_examples: Ignored (kept for API compatibility)
        
    Returns:
        Complete prompt string optimized for input length
    """
    # Determine mode based on input length
    mode = _get_input_mode(draft_text)
    
    # Build appropriate prompt for mode
    if mode == "short":
        # Short: Ultra-minimal, no examples, no facts, no patterns
        prompt = build_prompt_short(draft_text)
    elif mode == "long":
        # Long: Conservative, no examples, minimal patterns
        prompt = build_prompt_long(draft_text, protected_facts)
    else:
        # Medium: Moderate with optional example and shortened patterns
        examples = get_examples_for_type(announcement_type, max_examples=1)
        patterns = format_patterns_for_prompt()
        prompt = build_prompt_medium(draft_text, protected_facts, examples, patterns)
    
    # Apply size safeguard
    prompt = _apply_prompt_size_safeguard(prompt, draft_text, protected_facts)
    
    return prompt


def get_mode_for_logging(draft_text: str) -> str:
    """
    Get the mode name for logging purposes.
    
    Args:
        draft_text: The draft text
        
    Returns:
        Mode string for logging
    """
    return _get_input_mode(draft_text)


# Legacy compatibility
def build_retry_prompt(original_prompt: str, validation_errors: list, draft_text: str = "") -> str:
    """
    Build a stricter retry prompt when validation fails.
    Delegates to templates module.
    """
    from .prompt_templates import get_retry_prompt
    return get_retry_prompt(original_prompt, validation_errors, draft_text)
