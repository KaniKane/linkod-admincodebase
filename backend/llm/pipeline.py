from llm.prompt_builder import (
    build_generation_prompt,
    build_non_official_refinement_prompt,
    build_refinement_prompt,
)
import re
from llm.client import generate_text, generate_text_with_model
from llm.types import GenerationRequest
from config.ai_settings import LLM_MODEL_FALLBACK


PROMPT_ECHO_MARKERS = [
    "how to use the examples",
    "decision logic",
    "output rules",
    "required output format",
]


def _looks_like_name_line(line: str) -> bool:
    cleaned = line.strip()
    if not cleaned:
        return False

    if any(mark in cleaned for mark in [",", "!", "?"]):
        return False

    parts = [p for p in cleaned.replace("-", " ").split() if p]
    if len(parts) < 2 or len(parts) > 5:
        return False

    name_token = re.compile(r"^[A-Za-z][A-Za-z\.'-]*$")
    if not all(name_token.match(p) for p in parts):
        return False

    if cleaned.isupper():
        return True

    return all(p[:1].isupper() for p in parts if p[:1].isalpha())


def _extract_signature_line(raw_text: str) -> str | None:
    lines = [ln.rstrip() for ln in raw_text.splitlines() if ln.strip()]
    if not lines:
        return None

    for line in reversed(lines):
        stripped = line.strip()
        lower = stripped.lower()

        if lower.startswith(("-", "gikan kang", "from:", "hon.")):
            return stripped

        if _looks_like_name_line(stripped):
            return stripped

    return None


def _has_existing_signature(raw_text: str) -> bool:
    return _extract_signature_line(raw_text) is not None


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


def is_generation_intent(text: str) -> bool:
    """Detect prompt-style requests like 'Create announcement for ...'."""
    stripped = (text or "").strip()
    lower = stripped.lower()
    if not lower:
        return False

    instruction_verbs = [
        "create",
        "make",
        "write",
        "generate",
        "draft",
        "himo",
        "buhat",
        "sulat",
        "paghimo",
    ]
    announcement_words = [
        "announcement",
        "anunsyo",
        "pahibalo",
        "advisory",
        "notice",
    ]

    has_instruction_verb = any(v in lower for v in instruction_verbs)
    has_announcement_word = any(w in lower for w in announcement_words)

    # Most prompt-style requests are short and imperative.
    return has_instruction_verb and has_announcement_word and len(stripped) <= 200


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
        required = ["tinahod kong", "gipanghinaut"]
        if not source_has_signature:
            required.append("kaninyo matinahuron")

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


def validate_generation_output(output: str, source_text: str) -> bool:
    output_lower = output.lower()
    source_lower = source_text.lower()

    if len(output.strip()) == 0:
        return False

    if output.startswith("---"):
        return False

    if any(marker in output_lower for marker in PROMPT_ECHO_MARKERS):
        return False

    # If source instruction does not include specific date/time/location,
    # output should contain placeholders.
    has_date_hint = bool(re.search(r"\b20\d{2}\b|\benero\b|\bfebrero\b|\bmarso\b|\babril\b|\bmayo\b|\bhunyo\b|\bhulyo\b|\bagosto\b|\bsetyembre\b|\boktubre\b|\bnovyembre\b|\bdisyembre\b", source_lower))
    has_time_hint = bool(re.search(r"\balas\b|\b\d{1,2}:\d{2}\b|\bam\b|\bpm\b", source_lower))
    has_place_hint = any(k in source_lower for k in ["covered court", "barangay hall", "session hall", "lugar", "venue", "place"])

    if not (has_date_hint and has_time_hint and has_place_hint):
        if "[" not in output or "]" not in output:
            return False

    return True


# ---------------------------
# 4. FALLBACK (GUARANTEED FORMAT)
# ---------------------------
def force_official_format_fallback(
    raw_text: str,
    signature_name: str,
    signature_title: str,
    source_signature_line: str | None = None,
) -> str:
    body_text = raw_text.strip().capitalize()

    if source_signature_line:
        return f"""Tinahod kong mga baryuhanon,

Gihigayon ang atong {body_text}.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

{source_signature_line}"""

    return f"""Tinahod kong mga baryuhanon,

Gihigayon ang atong {body_text}.

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

{signature_name}
{signature_title}"""


def force_non_official_fallback(
    raw_text: str,
    signature_name: str | None = None,
) -> str:
    """Keep non-official posts simple; never inject official signature blocks."""
    cleaned = raw_text.strip()
    has_signature = _has_existing_signature(cleaned)
    signer = (signature_name or "").strip() or "[Ngalan]"

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
    if is_generation_intent(raw_text):
        for attempt in range(max_retries):
            prompt = build_generation_prompt(
                raw_text,
                signature_name=signature_name,
                signature_title=signature_title,
            )
            output = call_llm(prompt)
            if validate_generation_output(output, raw_text):
                return output

        # Generation fallback with placeholders for missing details.
        final_name = (signature_name or "").strip() or "[Ngalan]"
        final_title = (signature_title or "").strip() or "[Posisyon]"
        return f"""Tinahod kong mga baryuhanon,

Ania ang pahibalo kabahin sa: {raw_text.strip()}.
Ang kalihokan pagahigayon sa [Petsa], alas [Oras], sa [Lugar/Covered Court].

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

Kaninyo matinahuron,

{final_name}
{final_title}"""

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