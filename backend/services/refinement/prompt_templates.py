"""
Prompt templates for the Tandaganon announcement refinement pipeline.

ADAPTIVE REFINEMENT MODES:
- SHORT (≤25 words): Ultra-minimal editing, tiny prompt, no examples
- MEDIUM (26-120 words): Light refinement, moderate prompt, optional 1 example
- LONG (>120 words OR multi-paragraph): Conservative refinement, short prompt, no examples

Prompt ordering varies by mode to optimize for CPU-only hardware.
"""

import re

# ============================================================================
# MODE 1: SHORT INPUT (≤25 words) - Ultra Minimal
# ============================================================================

SHORT_ROLE = """You are a strict text editor for Barangay announcements in Surigao del Sur.
Fix grammar only. Preserve exact meaning. No additions."""

SHORT_RULES = """RULES:
1. Fix spelling and grammar only
2. Improve Tandaganon tone (Surigao Cebuano)
3. Preserve meaning exactly - no additions
4. Do not add sentences
5. Do not add greeting or closing
6. Do not add invitation language
7. Keep output close to source length
8. Return ONLY the edited text"""

SHORT_OUTPUT = """OUTPUT:
Return ONLY the edited text. No explanations. No prefixes."""

# ============================================================================
# MODE 2: MEDIUM INPUT (26-120 words) - Light Refinement
# ============================================================================

MEDIUM_ROLE = """You are a strict text editor for Barangay announcements in Surigao del Sur, Philippines.

Your ONLY job is to fix grammar and improve clarity while preserving the exact meaning.
You are NOT writing a new announcement. You are NOT expanding the text.
You are editing what is already there - nothing more, nothing less.

Write in Tandaganon dialect (Surigao del Sur Cebuano) but keep it minimal."""

MEDIUM_RULES = """RULES:
1. Improve wording and clarity
2. Maintain paragraph structure
3. Maintain meaning - do not invent facts
4. Do not invent dates, times, locations
5. Do not add greeting or closing unless present
6. Do not add invitation language unless present
7. Keep output within 20% of source length

FORBIDDEN:
- Adding new information not in source
- Adding new sentences not supported by source
- Adding opening phrases like "Nagpahibalo ang Barangay" UNLESS already in source
- Adding closing phrases like "Daghang salamat" UNLESS already in source
- Adding invitation language ("gihangyo", "ginaimbitar", "motambong") UNLESS already in source"""

MEDIUM_OUTPUT = """OUTPUT:
Return ONLY the edited text - no explanations, no prefixes.
Preserve all information from the source exactly."""

# ============================================================================
# MODE 3: LONG INPUT (>120 words OR multi-paragraph) - Conservative
# ============================================================================

LONG_ROLE = """You are a strict text editor for Barangay announcements in Surigao del Sur, Philippines.

Your ONLY job is to fix grammar and improve clarity while preserving the exact meaning and structure.
You are NOT rewriting the announcement. You are NOT expanding or shortening the text.
You are editing what is already there - nothing more, nothing less."""

LONG_RULES = """CRITICAL RULES:
1. Preserve paragraph structure exactly
2. Preserve sentence order as much as possible
3. Do not shorten the announcement
4. Do not expand the announcement
5. Fix grammar and clarity only
6. Do not add greeting or closing if not present
7. Do not add invitation language if not present
8. Do not invent facts, dates, times, or locations
9. Keep output within 10% of source length

CONSTRAINTS:
- Make the SMALLEST possible changes
- Fix spelling errors only
- Fix grammar mistakes only
- Add missing punctuation only
- Prefer "kay" over "tungod kay"
- Keep sentences direct and short"""

LONG_OUTPUT = """OUTPUT:
Return ONLY the edited text. No explanations. No prefixes.
Preserve the original structure and length."""

# ============================================================================
# LEGACY TEMPLATES (kept for compatibility)
# ============================================================================

# Base role definition - STRICT EDITOR, not speechwriter
BASE_ROLE = """You are a strict text editor for Barangay announcements in Surigao del Sur, Philippines.

Your ONLY job is to fix grammar and improve clarity while preserving the exact meaning.
You are NOT writing a new announcement. You are NOT expanding the text.
You are editing what is already there - nothing more, nothing less.

Write in Tandaganon dialect (Surigao del Sur Cebuano) but keep it minimal."""

def build_prompt_short(draft_text: str) -> str:
    """
    Build an ultra-minimal prompt for short inputs (≤25 words).
    
    Structure: ROLE + RULES + SOURCE + OUTPUT
    No examples. No patterns. No facts section.
    """
    word_count = len(draft_text.split())
    
    prompt_parts = [
        SHORT_ROLE,
        "",
        SHORT_RULES,
        "",
        f"SOURCE TEXT ({word_count} words):",
        draft_text,
        "",
        SHORT_OUTPUT
    ]
    
    return "\n".join(prompt_parts)


def build_prompt_medium(
    draft_text: str,
    protected_facts: dict,
    examples: list,
    dialect_patterns: str = ""
) -> str:
    """
    Build a moderate prompt for medium inputs (26-120 words).
    
    Structure: ROLE + RULES + FACTS + OPTIONAL EXAMPLE + SOURCE + OUTPUT
    """
    word_count = len(draft_text.split())
    
    # Build protected facts section
    facts_section = _build_protected_facts_section(protected_facts)
    
    # Optional: Add dialect patterns if provided (shortened)
    dialect_section = ""
    if dialect_patterns:
        # Extract just the essential patterns
        dialect_section = "\nTANDAGANON TONE:\n- Prefer \"kay\" over \"tungod kay\"\n- Use direct, short phrasing\n"
    
    # Optional: Add one short example if provided
    example_section = ""
    if examples:
        example = examples[0]
        example_section = f"\nEXAMPLE:\nDraft: {example.get('draft', '')}\nEdit: {example.get('refined', '')}\n"
    
    prompt_parts = [
        MEDIUM_ROLE,
        "",
        MEDIUM_RULES,
        dialect_section,
        facts_section,
        example_section,
        "",
        f"SOURCE TEXT ({word_count} words):",
        draft_text,
        "",
        MEDIUM_OUTPUT
    ]
    
    return "\n".join(prompt_parts)


def build_prompt_long(
    draft_text: str,
    protected_facts: dict
) -> str:
    """
    Build a conservative prompt for long inputs (>120 words or multi-paragraph).
    
    Structure: ROLE + STRICT RULES + FACTS + SOURCE + OUTPUT
    NO examples. NO dialect patterns. NO structure guidance.
    """
    word_count = len(draft_text.split())
    
    # Build minimal protected facts section
    facts_section = _build_protected_facts_section(protected_facts)
    
    prompt_parts = [
        LONG_ROLE,
        "",
        LONG_RULES,
        "",
        facts_section,
        "",
        f"SOURCE TEXT ({word_count} words, preserve structure):",
        draft_text,
        "",
        LONG_OUTPUT
    ]
    
    return "\n".join(prompt_parts)


# ============================================================================
# LEGACY TEMPLATES (kept for backward compatibility)
# ============================================================================

MINIMAL_EDIT_INSTRUCTION = """
EDIT MODE: MINIMAL EDIT (Strict)

You must make the SMALLEST possible changes to fix the draft.

PERMITTED EDITS ONLY:
- Fix spelling errors
- Fix grammar mistakes
- Improve word order for clarity
- Add missing punctuation
- Change Tagalog words to Tandaganon equivalents
- Shorten overly long sentences

FORBIDDEN (Will cause rejection):
- Adding new information not in the source
- Adding new sentences not supported by source
- Adding opening phrases like "Nagpahibalo ang Barangay" UNLESS already in source
- Adding closing phrases like "Daghang salamat" UNLESS already in source
- Adding invitation language ("gihangyo", "ginaimbitar", "motambong") UNLESS already in source
- Adding timing details ("karong hapon", "ipahigayon") UNLESS already in source
- Adding calls to action ("palihog", "pag-apil") UNLESS already in source
- Expanding a short draft into a full announcement

LENGTH PRESERVATION:
- If source is 1 sentence, output should be 1 sentence
- If source is 2-3 sentences, output should be 2-3 sentences
- Output word count must be within 20% of source word count
- Do not turn a note into a speech

TANDAGANON DIALECT (use minimally):
- Prefer "kay" over "tungod kay"
- Prefer direct, short phrasing
- Avoid literary/formal Cebuano patterns
- Avoid Tagalog loanwords
"""

# Expanded mode: only for explicit expansion requests
EXPANDED_MODE_INSTRUCTION = """
EDIT MODE: EXPANDED ANNOUNCEMENT

Transform the rough draft into a complete Barangay announcement.

You may:
- Add appropriate opening ("Nagpahibalo ang Barangay...")
- Add clear structure with all relevant details
- Add closing if appropriate ("Daghang salamat")
- Expand brief notes into complete announcements

Follow the type-specific structure provided.
Use Tandaganon dialect throughout.
"""

# Strict rules for ALL modes
STRICT_RULES = """
CRITICAL RULES - NEVER VIOLATE:

1. NEVER add facts, dates, times, locations not in the source
2. NEVER add invitation/call-to-action language not in source
3. NEVER add opening "Nagpahibalo ang Barangay..." unless source has announcement intent
4. NEVER add closing "Daghang salamat" unless source already has closing
5. NEVER turn a short note into a long formal announcement (unless EXPANDED mode)
6. NEVER remove dates, times, locations that ARE in the source
7. NEVER change names or numerical values
8. ALWAYS preserve the original detail level and intent

Source length: {source_word_count} words
Output must be within 20% of source length (unless explicitly expanding)
"""

# Short input protection rules
SHORT_INPUT_RULES = """
SHORT DRAFT PROTECTION (Source is brief):

This is a SHORT draft ({source_word_count} words, {sentence_count} sentence(s)).

MANDATORY CONSTRAINTS:
- Do NOT add any opening line
- Do NOT add any closing line
- Do NOT add "gihangyo", "ginaimbitar", "motambong", "gidapit" (invitation)
- Do NOT add "palihog", "hangyo" (requests)
- Do NOT add timing phrases like "karong hapon", "ipahigayon"
- Do NOT add filler like "alang sa kaayohan", "para sa tanan"
- Keep the same sentence count as source
- Make only grammar/clarity fixes

PERMITTED: Fix grammar, improve word order, add punctuation
FORBIDDEN: Everything else - especially expansion
"""

# Output instruction for minimal edit mode
OUTPUT_INSTRUCTION = """
OUTPUT REQUIREMENT:

Return ONLY the edited text - no explanations, no prefixes.

The output must:
1. Preserve all information from the source exactly
2. Use the same detail level (don't expand short notes)
3. Be ready to use as-is
4. Stay close to source length

If the source is a brief note, return a brief note - NOT a full announcement."""


def build_prompt(
    draft_text: str,
    announcement_type: str,
    protected_facts: dict,
    examples: list,
    type_structure: str = "",
    dialect_patterns: str = "",
    edit_mode: str = "minimal",
    is_short_input: bool = False
) -> str:
    """
    Build a complete prompt for the refinement pipeline.
    
    Args:
        draft_text: The original announcement draft
        announcement_type: Classified type of announcement
        protected_facts: Dict with 'dates', 'times', 'locations', 'names', 'numbers'
        examples: List of example dicts with 'draft' and 'refined' keys
        type_structure: Type-specific structural guidance
        dialect_patterns: Formatted Tandaganon dialect patterns string
        edit_mode: "minimal" (default) or "expanded"
        is_short_input: True if input is short (triggers strict protection)
        
    Returns:
        Complete prompt string ready for Ollama
    """
    # Count source metrics
    source_word_count = len(draft_text.split())
    sentence_count = len([s for s in re.split(r'[.!?]+', draft_text) if s.strip()])
    
    # Build protected facts section
    facts_section = _build_protected_facts_section(protected_facts)
    
    # Select edit mode instruction
    if edit_mode == "expanded":
        mode_instruction = EXPANDED_MODE_INSTRUCTION
        examples_section = _build_examples_section(examples, full_format=True)
        structure_section = type_structure or _get_minimal_structure()
    else:
        mode_instruction = MINIMAL_EDIT_INSTRUCTION
        # For short inputs: minimal or no examples
        if is_short_input:
            examples_section = _build_minimal_examples_section()
            structure_section = ""  # No structure guidance for short inputs
        else:
            examples_section = _build_examples_section(examples[:1], full_format=False)  # Only 1 example
            structure_section = ""
    
    # Add short input protection if applicable
    if is_short_input:
        short_rules = SHORT_INPUT_RULES.format(
            source_word_count=source_word_count,
            sentence_count=sentence_count
        )
        mode_instruction = mode_instruction + "\n" + short_rules
    
    # Format strict rules with source word count
    strict_rules_formatted = STRICT_RULES.format(source_word_count=source_word_count)
    
    # Assemble the complete prompt
    prompt_parts = [
        BASE_ROLE,
        mode_instruction,
    ]
    
    # Add dialect patterns if provided and not short input
    if dialect_patterns and not is_short_input:
        prompt_parts.append(dialect_patterns)
    
    prompt_parts.extend([
        strict_rules_formatted,
        facts_section,
    ])
    
    # Add structure only for non-short inputs in expanded mode
    if structure_section and not is_short_input:
        prompt_parts.append(structure_section)
    
    prompt_parts.extend([
        examples_section,
        f"\nDRAFT TO EDIT (\n{source_word_count} words, {sentence_count} sentences - preserve this length):\n\n{draft_text}",
        OUTPUT_INSTRUCTION
    ])
    
    return "\n".join(prompt_parts)


def _build_protected_facts_section(facts: dict) -> str:
    """Build the protected facts section of the prompt."""
    lines = ["\nFACTS IN SOURCE (preserve exactly):", ""]
    
    dates = facts.get("dates", [])
    times = facts.get("times", [])
    locations = facts.get("locations", [])
    names = facts.get("names", [])
    numbers = facts.get("numbers", [])
    
    has_facts = False
    if dates:
        lines.append(f"Dates: {', '.join(dates)}")
        has_facts = True
    if times:
        lines.append(f"Times: {', '.join(times)}")
        has_facts = True
    if locations:
        lines.append(f"Locations: {', '.join(locations)}")
        has_facts = True
    if names:
        lines.append(f"Names: {', '.join(names)}")
        has_facts = True
    if numbers:
        lines.append(f"Numbers: {', '.join(numbers)}")
        has_facts = True
    
    if not has_facts:
        lines.append("(No specific dates/times/locations detected - preserve all text as-is)")
    
    return "\n".join(lines)


def _build_examples_section(examples: list, full_format: bool = True) -> str:
    """Build the examples section of the prompt."""
    if not examples:
        return ""
    
    if full_format:
        lines = ["\nREFERENCE EXAMPLES:", ""]
        for i, example in enumerate(examples, 1):
            draft = example.get("draft", "")
            refined = example.get("refined", "")
            lines.append(f"Example {i}:")
            lines.append(f"  Draft: {draft}")
            lines.append(f"  Refined: {refined}")
            lines.append("")
    else:
        # Minimal format - just one example
        lines = ["\nREFERENCE (minimal edit style):", ""]
        example = examples[0]
        draft = example.get("draft", "")
        refined = example.get("refined", "")
        lines.append(f"Draft: {draft}")
        lines.append(f"Edit: {refined}")
    
    return "\n".join(lines)


def _build_minimal_examples_section() -> str:
    """Build a minimal examples section for short inputs - no expansion examples."""
    return """
MINIMAL EDIT EXAMPLES:
Draft: "Miting sa martes alas 3"
Edit: "Miting sa Martes sa alas 3:00 sa hapon"
(Direct edit - no added opening or closing)

Draft: "Linis sa kalsada ugma"
Edit: "Paghinlo sa kalsada ugma"
(Grammar fix only)
"""


def _get_minimal_structure() -> str:
    """Get minimal structure guidance."""
    return """
STRUCTURE (preserve source structure):
- Keep the same organization as the source
- Don't add new sections
- Don't rearrange information
"""


def _get_default_structure(announcement_type: str) -> str:
    """Get default structural guidance for an announcement type."""
    structures = {
        "meeting_notice": """
STRUCTURE FOR MEETING NOTICE:
1. Opening announcement phrase (Nagpahibalo ang...)
2. Who is being called/invited
3. What kind of meeting
4. When (date and time)
5. Where (location)
6. Purpose or agenda
7. Closing (optional, if present in draft)""",
        
        "community_event": """
STRUCTURE FOR COMMUNITY EVENT:
1. Event announcement
2. What activity/program
3. When (date, time, duration)
4. Where (venue)
5. Who can join/participate
6. What to bring or prepare (if any)
7. Additional details from draft""",
        
        "clean_up_drive": """
STRUCTURE FOR CLEAN-UP DRIVE:
1. Activity announcement
2. When (dates/times)
3. Where (areas to clean)
4. Who should participate
5. What to bring (tools, supplies)
6. Expected activities
7. Call to action""",
        
        "health_advisory": """
STRUCTURE FOR HEALTH ADVISORY:
1. Service/program announcement
2. What service is offered
3. When (schedule)
4. Where (venue)
5. Who is eligible/target
6. What to bring (requirements)
7. Additional information""",
        
        "government_service": """
STRUCTURE FOR GOVERNMENT SERVICE:
1. Service announcement
2. What service is available
3. When (schedule/hours)
4. Where (location/office)
5. Who can avail
6. Requirements to bring
7. Process or instructions""",
        
        "emergency_notice": """
STRUCTURE FOR EMERGENCY NOTICE:
1. Urgent announcement
2. What is happening
3. When (schedule of interruption/emergency)
4. Affected areas or people
5. Reason/cause (if known)
6. What to do/prepare
7. Contact for concerns""",
        
        "reminder_deadline": """
STRUCTURE FOR REMINDER/DEADLINE:
1. Reminder notice
2. What the deadline is for
3. When the deadline is
4. Where to go/process
5. Requirements or fees
6. Consequence of missing deadline (if stated)
7. Urgency statement""",
        
        "general_announcement": """
STRUCTURE FOR GENERAL ANNOUNCEMENT:
1. Opening statement
2. Main information/announcement
3. Relevant details (who, what, when, where)
4. Additional context
5. Closing (if appropriate)"""
    }
    
    return structures.get(announcement_type, structures["general_announcement"])


def get_retry_prompt(original_prompt: str, validation_errors: list, draft_text: str = "") -> str:
    """
    Build a stricter retry prompt when validation fails.
    
    Args:
        original_prompt: The previous prompt that failed
        validation_errors: List of validation error messages
        draft_text: The original draft text to re-inject
        
    Returns:
        Modified prompt with stricter constraints
    """
    error_section = "\n".join([f"- {error}" for error in validation_errors])
    
    # Count source metrics
    source_word_count = len(draft_text.split()) if draft_text else 0
    sentence_count = len([s for s in re.split(r'[.!?]+', draft_text) if s.strip()]) if draft_text else 0
    
    retry_addition = f"""

⚠️ VALIDATION FAILED - FIX REQUIRED:
{error_section}

STRICT MINIMAL EDIT REQUIREMENTS:
1. Make ONLY grammar/spelling fixes
2. Add NO new information, NO new sentences
3. Add NO opening like "Nagpahibalo ang Barangay"
4. Add NO closing like "Daghang salamat"
5. Add NO invitation words (gihangyo, gidapit, motambong)
6. Add NO timing phrases (karong hapon, ipahigayon)
7. Keep output within 20% of source length ({source_word_count} words, {sentence_count} sentences)
8. If you cannot meet these requirements, return the source text with only spelling fixes

SOURCE TEXT ({source_word_count} words):
{draft_text}

Make the smallest possible edits. Do not expand.
"""
    
    # Try to remove examples and structure sections
    prompt_cleaned = re.sub(
        r'\nREFERENCE EXAMPLES:.*?\nDRAFT TO EDIT',
        '\nDRAFT TO EDIT',
        original_prompt,
        flags=re.DOTALL
    )
    prompt_cleaned = re.sub(
        r'\nSTRUCTURE.*?\nREFERENCE',
        '\nREFERENCE',
        prompt_cleaned,
        flags=re.DOTALL
    )
    prompt_cleaned = re.sub(
        r'\nTANDAGANON DIALECT PATTERNS.*?\nCRITICAL RULES',
        '\nCRITICAL RULES',
        prompt_cleaned,
        flags=re.DOTALL
    )
    
    # Insert retry addition before OUTPUT REQUIREMENT
    prompt_parts = prompt_cleaned.split(OUTPUT_INSTRUCTION.strip())
    if len(prompt_parts) == 2:
        return prompt_parts[0] + retry_addition + "\n" + OUTPUT_INSTRUCTION + prompt_parts[1]
    
    return prompt_cleaned + retry_addition
