"""
Simplified AI Refinement for LINKod Admin Backend.

Thesis-aligned flow:
1. Receive announcement text
2. Basic validation (not empty, no inappropriate content)
3. Send to Ollama with single simple prompt
4. Basic output validation
5. Return refined text OR explicit error

This replaces the complex multi-stage pipeline with a simple, predictable flow.
"""

import httpx
import logging
from typing import Optional

from .refinement_data.sample_announcements import select_samples
from .refinement_data.tandaganon_guide import is_chatbot_output, contains_template_artifacts, contains_sample_content, STYLE_GUIDE

logger = logging.getLogger(__name__)

# Configuration
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"
OLLAMA_TIMEOUT = 60.0  # CPU-safe single attempt

def _build_refinement_prompt(raw_text: str, samples: list[dict]) -> str:
    """
    Build a refinement prompt with minimal-edit examples.
    Emphasizes strict editing, not template generation.
    Uses conservative mode for long inputs (no examples, shorter prompt).
    """
    # Determine if this is a long input
    word_count = len(raw_text.split())
    paragraph_count = raw_text.count('\n\n') + 1
    is_long_input = word_count > 40 or paragraph_count > 1
    
    # Build examples block (skip for long inputs to avoid misleading the model)
    # Put examples at the TOP, clearly separated from the actual task
    examples_block = ""
    if samples and not is_long_input:
        rendered = []
        for i, s in enumerate(samples, 1):
            rendered.append(
                f"EXAMPLE {i} (FOR STYLE REFERENCE ONLY - DO NOT COPY THIS CONTENT):\n"
                f"Draft: {s['input']}\n"
                f"Refined: {s['output']}"
            )
        examples_block = "\n\n".join(rendered)
        examples_block = f"{examples_block}\n\n" + "="*60 + "\n\n"
    
    # Build style rules from guide
    style_rules = "\n".join(f"- {rule}" for rule in STYLE_GUIDE["style_rules"])
    
    # Avoid phrases note
    avoid_note = "Do not use phrases like: " + ", ".join(STYLE_GUIDE["avoid_phrases"][:5]) + ", etc."
    
    # Long input conservative mode instructions
    long_input_note = ""
    if is_long_input:
        long_input_note = """
LONG INPUT MODE:
This is a longer announcement. Preserve the paragraph structure and sentence order as much as possible.
If the draft is already clear and correct, keep it nearly unchanged.
Make only small corrections to grammar, punctuation, and wording.
Do not replace correct Cebuano/Tandaganon words with awkward or less natural alternatives."""
    
    return f"""{examples_block}You are a STRICT EDITOR for barangay announcements.

Task:
Make minimal improvements to grammar, clarity, and wording. Preserve meaning exactly.

CRITICAL RULES:
{style_rules}

{avoid_note}

ANTI-COPYING RULES (MANDATORY):
- The examples above show STYLE ONLY - grammar fixes, word choice patterns
- NEVER copy sentences, names, places, or specific details from examples
- NEVER use content from examples in your output
- Edit ONLY the announcement below, not the examples
- Your output must be based 100% on the announcement below, not on examples
- If you copy any content from examples, you have failed the task

STRICT CONSTRAINT:
- Do not add any sentence, section, signature, or official title not directly in the source text
- Do NOT turn the draft into a full formal memo
{long_input_note}

ENGLISH HANDLING:
If the announcement is written partly in English, translate it naturally into Cebuano/Tandaganon.
Translate formal English openings like "I would like to inform", "Please be advised", "This is to inform" into natural Cebuano phrases like "Pahibalo", "Adunay", or "Giawhag ang".
Do not keep English phrases in the output - fully translate to Cebuano/Tandaganon.

Return only one final refined announcement.
Do not provide explanations or multiple versions.

Announcement to refine (EDIT THIS ONLY):
{raw_text}"""


def refine_text(raw_text: str) -> dict:
    """
    Refine announcement text using Ollama.
    
    Improved simple flow with sample guidance:
    1. Basic input validation
    2. Select relevant samples (1-2 max, 0 for long inputs)
    3. Build prompt with examples and style guide
    4. Single Ollama call (no retries)
    5. Basic output validation (including chatbot detection)
    6. Return success with refined text OR explicit error
    """
    # Step 1: Basic input validation
    if not raw_text or not raw_text.strip():
        return {
            "success": False,
            "original_text": raw_text or "",
            "refined_text": "",
            "error": "Input text cannot be empty."
        }
    
    raw_text_stripped = raw_text.strip()
    input_word_count = len(raw_text_stripped.split())
    is_long_input = input_word_count > 40 or raw_text_stripped.count('\n\n') > 0
    
    # Step 2: Select relevant samples (lightweight, 1 max, 0 for long inputs)
    samples = select_samples(raw_text_stripped, max_samples=1)
    if is_long_input:
        logger.info(f"[REFINE] Long input detected ({input_word_count} words, {raw_text_stripped.count(chr(10)+chr(10))+1} paragraphs) - skipping examples")
        samples = []  # Force no examples for long inputs
    else:
        logger.info(f"[REFINE] Selected {len(samples)} relevant sample for short input ({input_word_count} words)")
    
    # Step 3: Build improved prompt with examples and style guide
    prompt = _build_refinement_prompt(raw_text_stripped, samples)
    prompt_length = len(prompt)
    logger.info(f"[REFINE] Starting refinement: input={input_word_count} words, prompt={prompt_length} chars, examples={len(samples)}")
    
    # Step 4: Single Ollama call
    try:
        refined, raw_response_info = _call_ollama(prompt)
        
        if not refined:
            # Detailed logging for empty output diagnosis
            logger.error(f"[REFINE] Empty generation: input_words={input_word_count}, prompt_len={prompt_length}, examples={len(samples)}, is_long={is_long_input}")
            if raw_response_info:
                logger.error(f"[REFINE] Raw response info: {raw_response_info}")
            return {
                "success": False,
                "original_text": raw_text_stripped,
                "refined_text": "",
                "error": "Unable to generate refined announcement. AI service returned empty response."
            }
        
        refined_stripped = refined.strip()
        refined_word_count = len(refined_stripped.split())
        logger.info(f"[REFINE] Ollama response: {len(refined_stripped)} chars, {refined_word_count} words")
        
        # Step 5: Basic output validation (includes chatbot detection)
        is_valid, error_message = _validate_output(refined_stripped, raw_text_stripped)
        
        if not is_valid:
            logger.warning(f"[REFINE] Validation failed: {error_message}")
            return {
                "success": False,
                "original_text": raw_text_stripped,
                "refined_text": "",
                "error": error_message
            }
        
        # Step 6: Return success
        logger.info(f"[REFINE] Success: {input_word_count} words -> {refined_word_count} words")
        return {
            "success": True,
            "original_text": raw_text_stripped,
            "refined_text": refined_stripped,
            "error": None
        }
        
    except httpx.TimeoutException:
        logger.error(f"[REFINE] Ollama timeout after {OLLAMA_TIMEOUT}s (input={input_word_count} words)")
        return {
            "success": False,
            "original_text": raw_text_stripped,
            "refined_text": "",
            "error": "Unable to generate refined announcement. AI service timed out. Please try again."
        }
        
    except Exception as e:
        logger.error(f"[REFINE] Unexpected error: {str(e)} (input={input_word_count} words)")
        return {
            "success": False,
            "original_text": raw_text_stripped,
            "refined_text": "",
            "error": f"Unable to generate refined announcement. Error: {str(e)}"
        }


def _call_ollama(prompt: str) -> tuple[Optional[str], Optional[dict]]:
    """
    Make a single call to Ollama for text generation.
    
    Args:
        prompt: The prompt to send to Ollama
        
    Returns:
        Tuple of (generated_text, raw_response_info_dict)
        - generated_text: The cleaned output or None if failed/empty
        - raw_response_info: Dict with raw response metadata for debugging
    """
    url = f"{OLLAMA_BASE_URL}/api/generate"
    
    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.3,
            "top_p": 0.9,
            "top_k": 40,
            "num_predict": 500
        }
    }
    
    logger.info(f"[REFINE] Calling Ollama at {url} with model {OLLAMA_MODEL}")
    
    with httpx.Client(timeout=OLLAMA_TIMEOUT) as client:
        response = client.post(url, json=payload)
        response.raise_for_status()
        data = response.json()
        
        # Extract raw response info for debugging empty outputs
        raw_info = {
            "model": data.get("model"),
            "done": data.get("done"),
            "total_duration": data.get("total_duration"),
            "load_duration": data.get("load_duration"),
            "eval_count": data.get("eval_count"),
            "prompt_eval_count": data.get("prompt_eval_count"),
        }
        
        # Extract the generated text
        generated = data.get("response", "").strip()
        
        # Clean up common prefixes
        generated = _clean_output(generated)
        
        return generated if generated else None, raw_info


def _clean_output(text: str) -> str:
    """Clean common unwanted prefixes from AI output."""
    prefixes_to_remove = [
        "refined announcement:",
        "refined text:",
        "output:",
        "result:",
        "announcement:",
        "here is the refined announcement:",
        "here is the refined text:",
    ]
    
    text_lower = text.lower()
    for prefix in prefixes_to_remove:
        if text_lower.startswith(prefix):
            text = text[len(prefix):].strip()
            break
    
    return text


def _validate_output(refined: str, original: str) -> tuple[bool, Optional[str]]:
    """
    Output validation including chatbot detection and template artifact detection.
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    # Check not empty
    if not refined or not refined.strip():
        return False, "AI returned empty output."
    
    # Check not wildly longer than input (adaptive threshold)
    # Short inputs need more room for translation/list formatting
    # Long inputs should stay closer to original length
    original_words = len(original.split())
    refined_words = len(refined.split())
    
    if original_words > 0:
        if original_words <= 15:
            # Short input: allow up to 5x for translation/list formatting
            max_multiplier = 5
        elif original_words <= 30:
            # Medium input: allow up to 4x
            max_multiplier = 4
        else:
            # Long input: stricter 3x limit
            max_multiplier = 3
        
        if refined_words > original_words * max_multiplier:
            return False, f"AI output is too long ({refined_words} words vs {original_words} input). Possible uncontrolled expansion."
    
    # Check for chatbot-style output (pass source to allow phrases already in input)
    is_chatbot, matched_phrase = is_chatbot_output(refined, original)
    if is_chatbot:
        return False, f"AI output contains chatbot-style response: '{matched_phrase}'. Please try again."
    
    # Check for sample content copying (model copied from examples)
    has_sample_content, matched_signature = contains_sample_content(refined)
    if has_sample_content:
        return False, f"AI output appears to copy content from examples: '{matched_signature}'. Please try again with different input."
    
    # Check for template artifacts (signatures, titles, etc. not in source)
    has_artifacts, artifact_reason = contains_template_artifacts(refined, original)
    if has_artifacts:
        return False, f"AI output added unsupported content: {artifact_reason}"
    
    return True, None


# Legacy compatibility - simple function for old code
def refine_text_legacy(raw_text: str, ollama_base_url: Optional[str] = None) -> Optional[str]:
    """
    Legacy-compatible interface.
    Returns just the refined text or None on failure.
    """
    result = refine_text(raw_text)
    if result["success"]:
        return result["refined_text"]
    return None



