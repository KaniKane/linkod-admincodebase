"""
Tandaganon/Cebuano style guide for barangay announcements.

Lightweight guidance for natural local wording.
Supports MINIMAL EDITING - not template generation.
"""

# Unique content signatures from samples that should NEVER appear in output
# These help detect when the model is copying from examples
SAMPLE_CONTENT_SIGNATURES = [
    # From long-form parent meeting example
    "peligro ug dili maayong impluwensya",
    "sige og laag tunga sa gabii",
    "magtinabangay ang barangay ug ang mga pamilya",
    "pag-atiman sa mga kabataan",
    # From other examples - specific unique phrases
    "wala pa bakunaha",
    "katag mga dula",
    "pista sa cagbaoto",
    "libreng birth certificate",
]


def contains_sample_content(text: str) -> tuple[bool, str]:
    """
    Check if output contains content copied from sample examples.
    Returns (has_sample_content, matched_signature)
    """
    text_lower = text.lower()
    
    for signature in SAMPLE_CONTENT_SIGNATURES:
        if signature.lower() in text_lower:
            return True, signature
    
    return False, ""

STYLE_GUIDE = {
    "preferred_phrases": [
        "Adunay...",
        "Ang mga...",
        "Sa mga...",
        "Giawhag ang...",
        "Gihangyo ang..."
    ],
    
    "avoid_phrases": [
        "Here's the refined announcement",
        "Here is the refined text",
        "Or, in a more polished",
        "Pinaagi niini",
        "Pinangga namong",
        "Kami po ay",
        "I would like to inform",
        "This is to inform",
        "Please be advised",
        "In compliance with",
        "Refined version:",
        "Alternative version:",
        "Option 1:",
        "Option 2:"
    ],
    
    "style_rules": [
        "You are a STRICT EDITOR, not a speechwriter.",
        "Make only the smallest necessary improvements.",
        "Fix grammar, spelling, and clarity only.",
        "Do not add any sentence, section, or paragraph not in the source.",
        "Do not add signatures, titles, or official names unless already in source.",
        "Do not add 'Daghang salamat' or closing courtesies unless already in source.",
        "Do not turn the draft into a full formal memo.",
        "Use the examples only as style guidance, not as templates to copy.",
        "Do not copy names, titles, or structure from the examples.",
        "Return only one final refined announcement.",
        "Do not explain the answer.",
        "Do not give two versions.",
        "Do not add facts not in the draft.",
        "Use natural Cebuano/Tandaganon phrasing when appropriate.",
        "If the draft contains multiple requirements, you may format them as a numbered list for clarity.",
        "Do not replace correct Cebuano/Tandaganon words with awkward or less natural alternatives.",
        "If the draft is already clear and correct, keep it nearly unchanged.",
        "Preserve the paragraph structure for longer announcements.",
        "Preserve the sentence order as much as possible."
    ],
    
    "common_terms": {
        "tomorrow": "ugma",
        "meeting": "miting/panagtigom",
        "afternoon": "hapon",
        "morning": "buntag",
        "youth": "kabatan-onan/kabataan",
        "residents": "residente",
        "invited": "giawhag",
        "requested": "gihangyo"
    },
    
    "grammar_corrections": {
        "mo apil": "moapil",
        "mo kuha": "mokuha",
        "kinahanlanon": "kinahanglanon",
        "mo attend": "motambong",
        "mo register": "magparehistro",
        "gusto mo": "gustong",
        "mo gusto": "mogusto",
        "adto mo": "adto mo",
        "mo adto": "moadto"
    },
    
    "preserve_words": [
        "ginikanan",
        "tigulang",
        "bata",
        "kabatan-onan",
        "tambong",
        "hisgot",
        "pahibalo",
        "hangyo",
        "awhag",
        "peligro",
        "impluwensya",
        "kahimtang",
        "panagtigom",
        "miting",
        "laag",
        "atiman"
    ]
}


def get_style_guide_text() -> str:
    """Get a compact style guide text for prompts."""
    lines = [
        "Editing Guidance:",
        "- Make minimal changes only",
        "- Fix grammar and clarity",
        "- Do not add sections not in source",
        "- Natural Cebuano/Tandaganon phrasing",
    ]
    
    # Add preferred phrases (first 3)
    lines.append("\nGood phrasing examples:")
    for phrase in STYLE_GUIDE["preferred_phrases"][:3]:
        lines.append(f"  - {phrase}")
    
    return "\n".join(lines)


def is_chatbot_output(text: str, source_text: str = "") -> tuple[bool, str]:
    """
    Check if output contains chatbot-style phrases or template artifacts.
    Only flags phrases that are NEW in output (not already in source).
    
    Args:
        text: The refined output text to check
        source_text: The original input text (to allow phrases already present)
    
    Returns:
        Tuple of (is_chatbot, matched_phrase)
    """
    text_lower = text.lower()
    source_lower = source_text.lower()
    
    for phrase in STYLE_GUIDE["avoid_phrases"]:
        phrase_lower = phrase.lower()
        # Only flag if phrase is in output but NOT in source
        if phrase_lower in text_lower and phrase_lower not in source_lower:
            return True, phrase
    
    # Check for multiple versions (Options, Version 1, etc.)
    if "option 1" in text_lower or "option 2" in text_lower or "version 1" in text_lower:
        return True, "Multiple versions detected"
    
    # Check for explanation markers
    explanation_markers = [
        "here's", "this is", "below is", "alternative:",
        "option:", "version:", "translation:", "polished version"
    ]
    for marker in explanation_markers:
        if text_lower.startswith(marker) or f"\n{marker}" in text_lower:
            return True, f"Explanation marker: {marker}"
    
    return False, ""


def contains_template_artifacts(text: str, source_text: str) -> tuple[bool, str]:
    """
    Check if output contains template artifacts not present in source.
    Returns (has_artifacts, reason)
    """
    text_lower = text.lower()
    source_lower = source_text.lower()
    
    # Check for signature/title artifacts
    signature_markers = [
        "hon.", "barangay captain", "barangay secretary", "barangay kagawad",
        "municipal mayor", "gikan kang:", "kaninyo matinahuron",
    ]
    
    for marker in signature_markers:
        if marker in text_lower and marker not in source_lower:
            return True, f"Added signature/title artifact: '{marker}'"
    
    # Check for closing courtesy additions
    courtesy_phrases = [
        "daghang salamat", "gipanghinaut ko ang inyung",
        "100% nga kooperasyon", "dugang pahibalo"
    ]
    
    for phrase in courtesy_phrases:
        if phrase in text_lower and phrase not in source_lower:
            return True, f"Added courtesy phrase not in source: '{phrase}'"
    
    # Check for content repetition (input appears at end of output)
    # This detects when AI repeats the raw input after adding template
    text_lines = [l.strip() for l in text.strip().split('\n') if l.strip()]
    source_clean = source_lower.replace(' ', '').replace(',', '').replace('.', '')
    
    if len(text_lines) >= 2:
        # Check if last line or two resembles the input
        last_line_clean = text_lines[-1].lower().replace(' ', '').replace(',', '').replace('.', '')
        if len(last_line_clean) > 20 and last_line_clean in source_clean:
            return True, "Output appears to repeat input content (template + original)"
    
    return False, ""
