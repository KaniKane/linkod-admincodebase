from llm.prompt_builder import (
    build_non_official_refinement_prompt,
    build_refinement_prompt,
)
import re
from llm.client import generate_text, generate_text_with_model
from llm.types import GenerationRequest
from config.ai_settings import LLM_MODEL_FALLBACK


PROMPT_ECHO_MARKERS = [
    "how to use the examples",
    "examples (style reference only)",
    "decision logic (very important)",
    "critical rules",
    "internal check (do not skip)",
    "required output format (strict)",
    "output rules (strict)",
    "you are the official announcement editor",
    "do not copy sentences",
    "style reference only",
]


# ---------------------------
# 1. CLASSIFIER
# ---------------------------
def is_official_announcement(text: str) -> bool:
    text = text.lower()

    # Strong signals that the message is an official LGU/barangay notice.
    official_markers = [
        "hon.",
        "barangay captain",
        "municipal mayor",
        "kapitan",
        "sangguniang barangay",
        "office of the barangay captain",
        "official advisory",
    ]

    # Broad public-address style often used in official notices.
    community_markers = [
        "tinahod kong mga baryuhanon",
        "tinahod kong mga barangayanon",
        "pahibalo alang sa tanang",
        "sa tanang residente",
        "public advisory",
        "barangay advisory",
    ]

    # Civic notices that are typically official when framed in barangay context.
    official_event_markers = [
        "general assembly",
        "barangay assembly",
        "public meeting",
        "community assembly",
        "official meeting",
    ]

    barangay_context_markers = [
        "barangay",
        "covered court",
        "barangay hall",
        "session hall",
        "residente",
    ]

    # Signals for non-official/community contributor style posts.
    non_official_markers = [
        "from:",
        "sk kagawad",
        "sk chairman",
        "basketball club",
    ]

    has_non_official = any(marker in text for marker in non_official_markers)
    has_authority = any(marker in text for marker in official_markers)
    has_community_tone = any(marker in text for marker in community_markers)
    has_official_event = any(marker in text for marker in official_event_markers)
    has_barangay_context = any(marker in text for marker in barangay_context_markers)

    # If it has explicit non-official markers and no authority markers, classify non-official.
    if has_non_official and not has_authority:
        return False

    if has_authority:
        return True

    if has_community_tone and not has_non_official:
        return True

    if has_official_event and has_barangay_context and not has_non_official:
        return True

    return False


# ---------------------------
# 2. LLM CALL (EDIT THIS PART)
# ---------------------------
def call_llm(prompt: str) -> str:
    """Call configured LLM provider and return generated text or empty string."""
    request = GenerationRequest(prompt=prompt, temperature=0.0)

    primary = generate_text(request)
    if primary.success and primary.text:
        return primary.text.strip()

    fallback_model = LLM_MODEL_FALLBACK
    if fallback_model:
        fallback = generate_text_with_model(request, fallback_model)
        if fallback.success and fallback.text:
            return fallback.text.strip()

    return ""


# ---------------------------
# 3. VALIDATOR
# ---------------------------
def validate_output(output: str, is_official: bool, source_text: str) -> bool:
    output_lower = output.lower()
    source_lower = source_text.lower()

    if "note:" in output_lower:
        return False

    if output.startswith("---"):
        return False

    if any(marker in output_lower for marker in PROMPT_ECHO_MARKERS):
        return False

    if len(output.strip()) == 0:
        return False

    if is_official:
        required = [
            "tinahod kong",
            "gipanghinaut",
        ]

        for r in required:
            if r not in output_lower:
                return False

        # Accept either standard closing or preserved sender attribution.
        has_closing_or_signature = (
            "kaninyo matinahuron" in output_lower
            or "gikan kang" in output_lower
            or bool(re.search(r"\bhon\.", output_lower))
        )
        if not has_closing_or_signature:
            return False

    else:
        # Non-official messages must not be converted into official signature format
        # unless those markers were already present in the input.
        injected_official_markers = [
            "kaninyo matinahuron",
            "hon.",
            "barangay captain",
            "tinahod kong mga baryuhanon",
            "tinahod kong mga barangayanon",
        ]

        for marker in injected_official_markers:
            if marker in output_lower and marker not in source_lower:
                return False

    return True


# ---------------------------
# 4. FALLBACK (GUARANTEED FORMAT)
# ---------------------------
def force_official_format_fallback(raw_text: str) -> str:
    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    sender_match = re.search(r"(gikan kang\s+[^\n]+)$", raw_text, flags=re.IGNORECASE)
    sender_line = sender_match.group(1).strip() if sender_match else None

    if not sender_line:
        sender_line = next(
            (
                line
                for line in reversed(lines)
                if re.match(r"^(gikan kang|hon\.)", line, flags=re.IGNORECASE)
            ),
            None,
        )

    if sender_match:
        body_source = (raw_text[:sender_match.start()] + raw_text[sender_match.end():]).strip()
    else:
        body_lines = [line for line in lines if line != sender_line]
        body_source = " ".join(body_lines).strip() or raw_text.strip()

    body_text = re.sub(r"\s+", " ", body_source).strip(" .,")

    if sender_line:
        signature_block = sender_line
    else:
        signature_block = "Kaninyo matinahuron,\n\nHON. ALBERTO C. PACHECO\nBarangay Captain"

    return f"""Tinahod kong mga baryuhanon,

Gihigayon ang atong {body_text}.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

{signature_block}"""


def force_non_official_fallback(raw_text: str) -> str:
    """Keep non-official posts simple; never inject official signature blocks."""
    return raw_text.strip()


# ---------------------------
# 5. RETRY SYSTEM
# ---------------------------
def refine_with_retry(raw_text: str, max_retries: int = 3) -> str:
    is_official = is_official_announcement(raw_text)

    for attempt in range(max_retries):
        prompt = (
            build_refinement_prompt(raw_text)
            if is_official
            else build_non_official_refinement_prompt(raw_text)
        )
        output = call_llm(prompt)

        if validate_output(output, is_official, raw_text):
            return output

    if is_official:
        return force_official_format_fallback(raw_text)

    return force_non_official_fallback(raw_text)


# ---------------------------
# 6. FINAL FUNCTION
# ---------------------------
def generate_announcement(raw_text: str) -> str:
    result = refine_with_retry(raw_text)
    return result.strip()