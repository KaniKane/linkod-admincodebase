from llm.prompt_builder import (
    build_non_official_refinement_prompt,
    build_refinement_prompt,
)
import re
from llm.client import generate_text, generate_text_with_model
from llm.types import GenerationRequest
from config.ai_settings import LLM_MODEL_FALLBACK


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
    source_has_signature = _has_existing_signature(source_text)

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
            "kaninyo matinahuron"
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
    return f"""Tinahod kong mga baryuhanon,

Gihigayon ang atong {body_text}.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

HON. ALBERTO C. PACHECO
Barangay Captain"""


def force_non_official_fallback(
    raw_text: str,
    signature_name: str | None = None,
) -> str:
    """Keep non-official posts simple; never inject official signature blocks."""
    cleaned = raw_text.strip()
    has_signature = _has_existing_signature(cleaned)
    signer = (signature_name or "").strip()

    if has_signature or not signer:
        return cleaned

    return f"{cleaned}\n\n-{signer}"


# ---------------------------
# 5. RETRY SYSTEM
# ---------------------------
def refine_with_retry(
    raw_text: str,
    max_retries: int = 3,
    signature_name: str | None = None,
    signature_title: str | None = None,
) -> str:
    is_official = is_official_announcement(raw_text)
    source_signature_line = _extract_signature_line(raw_text)
    has_existing_signature = _has_existing_signature(raw_text)

    # Official defaults: always fall back to Barangay Captain identity when source has no signature.
    official_default_name = "HON. ALBERTO C. PACHECO"
    official_default_title = "Barangay Captain"
    non_official_user_signature = (signature_name or "").strip() or None

    for attempt in range(max_retries):
        prompt = (
            build_refinement_prompt(
                raw_text,
                signature_name=None if has_existing_signature else official_default_name,
                signature_title=None if has_existing_signature else official_default_title,
            )
            if is_official
            else build_non_official_refinement_prompt(
                raw_text,
                signature_name=non_official_user_signature,
            )
        )
        output = call_llm(prompt)

        if validate_output(output, is_official, raw_text):
            return output

    if is_official:
        return force_official_format_fallback(
            raw_text,
            signature_name=official_default_name,
            signature_title=official_default_title,
            source_signature_line=source_signature_line,
        )

    return force_non_official_fallback(
        raw_text,
        signature_name=non_official_user_signature,
    )


# ---------------------------
# 6. FINAL FUNCTION
# ---------------------------
def generate_announcement(
    raw_text: str,
    signature_name: str | None = None,
    signature_title: str | None = None,
) -> str:
    result = refine_with_retry(
        raw_text,
        signature_name=signature_name,
        signature_title=signature_title,
    )
    return result.strip()