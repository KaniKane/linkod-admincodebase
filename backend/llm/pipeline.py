from llm.prompt_builder import (
    build_generation_prompt,
    build_non_official_refinement_prompt,
    build_refinement_prompt,
)
import re
from llm.client import generate_text_with_model
from llm.types import GenerationRequest
from config.ai_settings import LLM_MODEL_FALLBACK


PROMPT_ECHO_MARKERS = [
    "how to use the examples",
    "decision logic",
    "output rules",
    "required output format",
]

GENERATION_PLACEHOLDERS = [
    "[Petsa]",
    "[Oras]",
    "[Lugar/Covered Court]",
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

    # Normalize to token-friendly text so minor punctuation/spacing differences
    # do not prevent intent detection.
    normalized = re.sub(r"[^a-z\s]", " ", lower)
    tokens = [token for token in normalized.split() if token]
    token_set = set(tokens)

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
    announcement_words = {"announcement", "anunsyo", "pahibalo", "advisory", "notice"}

    has_instruction_verb = any(verb in token_set for verb in instruction_verbs)

    # Accept common spelling variants like "announcemet", "annoucement", etc.
    has_announcement_word = any(word in token_set for word in announcement_words) or any(
        token.startswith("announ") for token in tokens
    )

    has_draft_keyword = "draft" in token_set
    has_topic_connector = any(
        connector in token_set
        for connector in ["about", "for", "regarding", "kabahin", "mahitungod"]
    )

    # Most prompt-style requests are short and imperative.
    return (
        has_instruction_verb
        and (has_announcement_word or (has_draft_keyword and has_topic_connector))
        and len(stripped) <= 280
    )


# ---------------------------
# 2. LLM CALL (EDIT THIS PART)
# ---------------------------
def call_llm(prompt: str) -> str:
    """Call only the 70B model for refinement/generation and return generated text or empty string."""
    request = GenerationRequest(prompt=prompt, temperature=0.0)

    # Force a single-model path: use 70B versatile only, no 8B fallback.
    model_70b = (LLM_MODEL_FALLBACK or "llama-3.3-70b-versatile").strip()
    result = generate_text_with_model(request, model_70b)
    if result.success and result.text:
        return result.text.strip()

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

    # Must look like a proper barangay draft structure, not a loose sentence.
    if "tinahod kong" not in output_lower:
        return False
    if "kaninyo matinahuron" not in output_lower:
        return False

    # Reject prompt echo responses.
    if re.search(r"\b(create|make|write|generate|draft)\b", output_lower):
        if "announcement" in output_lower or "announc" in output_lower:
            return False

    # Reject obvious placeholder corruption.
    if "[" in output and "]" in output:
        malformed = re.search(r"\[[^\]]{0,2}\]", output)
        if malformed:
            return False

    # If source instruction does not include specific date/time/location,
    # output should contain placeholders.
    has_date_hint = bool(re.search(r"\b20\d{2}\b|\benero\b|\bfebrero\b|\bmarso\b|\babril\b|\bmayo\b|\bhunyo\b|\bhulyo\b|\bagosto\b|\bsetyembre\b|\boktubre\b|\bnovyembre\b|\bdisyembre\b", source_lower))
    has_time_hint = bool(re.search(r"\balas\b|\b\d{1,2}:\d{2}\b|\bam\b|\bpm\b", source_lower))
    has_place_hint = any(k in source_lower for k in ["covered court", "barangay hall", "session hall", "lugar", "venue", "place"])

    if not (has_date_hint and has_time_hint and has_place_hint):
        if not all(ph in output for ph in GENERATION_PLACEHOLDERS):
            return False

    return True


def _extract_generation_topic(raw_text: str) -> str:
    """Extract a clean topic phrase from prompt-style generation input."""
    text = (raw_text or "").strip()
    if not text:
        return "kalihokan sa barangay"

    normalized = re.sub(r"\s+", " ", text)

    patterns = [
        r"^(?:please\s+)?(?:create|make|write|generate|draft)\s+(?:an?\s+)?(?:official\s+)?(?:barangay\s+)?(?:announcement|announc\w+)\s+(?:about|for|regarding)\s+",
        r"^(?:please\s+)?(?:create|make|write|generate|draft)\s+",
    ]

    topic = normalized
    for pattern in patterns:
        topic = re.sub(pattern, "", topic, flags=re.IGNORECASE)

    topic = topic.strip(" .:-")
    if not topic:
        return "kalihokan sa barangay"

    return topic


def _build_generation_fallback(
    raw_text: str,
    signature_name: str | None,
    signature_title: str | None,
) -> str:
    """Return a clean, readable Cebuano draft when model output is unsuitable."""
    topic = _extract_generation_topic(raw_text)
    final_name = (signature_name or "").strip() or "[Ngalan]"
    final_title = (signature_title or "").strip() or "[Posisyon]"

    return f"""Tinahod kong mga baryuhanon,

Ania ang pahibalo kabahin sa {topic}.
Ang kalihokan pagahigayon sa [Petsa], alas [Oras], sa [Lugar/Covered Court].

Palihog makigkoordinar ug mosunod sa giya sa barangay aron hapsay ang kalihokan.

Daghang salamat.

Kaninyo matinahuron,

{final_name}
{final_title}"""


# ---------------------------
# 4. FALLBACK (GUARANTEED FORMAT)
# ---------------------------
def force_official_format_fallback(
    raw_text: str,
    signature_name: str,
    signature_title: str,
    source_signature_line: str | None = None,
) -> str:
    # Preserve original casing (names, places, dates) and collapse extra spaces.
    body_text = re.sub(r"\s+", " ", raw_text.strip())
    if body_text and body_text[-1] not in ".!?":
        body_text = f"{body_text}."

    if source_signature_line:
        return f"""Tinahod kong mga baryuhanon,

{body_text}

Gipanghinaut ko ang inyong 100% nga kooperasyon.
Daghang salamat.

{source_signature_line}"""

    return f"""Tinahod kong mga baryuhanon,

{body_text}

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

        # Clean fallback for prompt-based generation when model output is low-quality.
        return _build_generation_fallback(
            raw_text,
            signature_name=signature_name,
            signature_title=signature_title,
        )

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