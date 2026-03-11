"""
Refinement service - Pipeline orchestrator for the AI refinement system.

Coordinates the multi-stage refinement process:
1. Preprocess input
2. Classify announcement type
3. Extract protected facts
4. Build type-specific prompt (shortened for weak hardware)
5. Generate with Ollama
6. Validate output
7. Retry if needed (with stricter prompt) - DISABLED by default for weak hardware

Returns structured response with metadata for API consumers.
"""

import re
import time
import logging
from typing import Optional, Dict, List, Any

from .announcement_classifier import classify_announcement, get_type_description
from .entity_extractor import extract_protected_facts
from .prompt_builder import build_refinement_prompt, build_retry_prompt, get_mode_for_logging
from .rewrite_generator import generate_refinement
from .output_validator import validate_output, determine_fallback_action

# Setup logger
logger = logging.getLogger(__name__)

# Increase logging verbosity for diagnostic purposes
logger.setLevel(logging.DEBUG)

# Create a file handler for logging
file_handler = logging.FileHandler('refinement_service.log')
file_handler.setLevel(logging.DEBUG)

# Create a console handler for logging
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)

# Create a formatter and add it to the handlers
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
file_handler.setFormatter(formatter)
console_handler.setFormatter(formatter)

# Add the handlers to the logger
logger.addHandler(file_handler)
logger.addHandler(console_handler)


def refine_text_pipeline(
    raw_text: str,
    enable_logging: bool = True,
    max_retries: int = 0  # Disabled by default for weak hardware
) -> Dict[str, Any]:
    """
    Main entry point for the refinement pipeline.
    
    Args:
        raw_text: The original announcement draft
        enable_logging: Whether to log pipeline steps
        max_retries: Maximum retry attempts (0 = no retry, recommended for weak hardware)
        
    Returns:
        Dictionary with:
        - original_text: Input text
        - refined_text: Output text (may be same as input if refinement fails)
        - announcement_type: Classified type
        - validation_passed: Whether validation succeeded
        - warnings: List of warning messages
        - fallback_used: Whether original was returned unchanged
        - metadata: Pipeline execution details
    """
    start_time = time.time()
    
    # Initialize result structure
    result = {
        "original_text": raw_text,
        "refined_text": raw_text,
        "announcement_type": "general_announcement",
        "validation_passed": False,
        "warnings": [],
        "fallback_used": False,
        "metadata": {}
    }
    
    # Track pipeline steps
    pipeline_log = []
    
    def log_step(step: str, details: Any = None):
        if enable_logging:
            pipeline_log.append({
                "step": step,
                "details": details,
                "timestamp": time.time() - start_time
            })
            # Also log to Python logger for backend visibility
            if details:
                logger.info(f"[REFINE] {step}: {details}")
            else:
                logger.info(f"[REFINE] {step}")
    
    logger.info(f"[REFINE] Starting refinement for text: {raw_text[:50]}...")
    
    # ========================================
    # STEP 1: Preprocess input
    # ========================================
    log_step("preprocess_start")
    preprocessed = _preprocess_input(raw_text)
    log_step("preprocess_complete", {"input_length": len(raw_text), "output_length": len(preprocessed)})
    
    if not preprocessed or not preprocessed.strip():
        result["warnings"].append("Input text is empty after preprocessing")
        result["fallback_used"] = True
        result["metadata"] = {"pipeline_log": pipeline_log, "total_time": time.time() - start_time}
        logger.warning("[REFINE] Empty input after preprocessing")
        return result
    
    # ========================================
    # STEP 2: Classify announcement type
    # ========================================
    log_step("classification_start")
    announcement_type = classify_announcement(preprocessed)
    type_description = get_type_description(announcement_type)
    result["announcement_type"] = announcement_type
    log_step("classification_complete", {"type": announcement_type, "description": type_description})
    
    # ========================================
    # STEP 3: Extract protected facts
    # ========================================
    log_step("extraction_start")
    protected_facts = extract_protected_facts(preprocessed)
    log_step("extraction_complete", {
        "dates": len(protected_facts.get("dates", [])),
        "times": len(protected_facts.get("times", [])),
        "locations": len(protected_facts.get("locations", [])),
        "names": len(protected_facts.get("names", [])),
        "numbers": len(protected_facts.get("numbers", []))
    })
    
    # ========================================
    # STEP 4: Build prompt (ADAPTIVE mode based on input length)
    # ========================================
    log_step("prompt_build_start")
    
    # Determine mode for logging
    mode = get_mode_for_logging(preprocessed)
    word_count = len(preprocessed.split())
    
    prompt = build_refinement_prompt(
        draft_text=preprocessed,
        announcement_type=announcement_type,
        protected_facts=protected_facts,
        max_examples=0 if len(preprocessed.split()) <= 25 else 1  # No examples for short inputs
    )
    prompt_length = len(prompt)
    log_step("prompt_build_complete", {
        "mode": mode,
        "input_length": word_count,
        "prompt_length": prompt_length,
        "prompt_lines": len(prompt.split('\n')),
        "is_short_input": len(preprocessed.split()) <= 25
    })
    
    # Log mode info
    logger.info(f"[REFINE] mode={mode}_input, input_length={word_count}, prompt_length={prompt_length}")
    
    # ========================================
    # STEP 5: Generate with Ollama (attempt 1)
    # ========================================
    log_step("generation_start", {"attempt": 1, "prompt_length": prompt_length})
    gen_start = time.time()
    refined = generate_refinement(prompt)
    gen_time = time.time() - gen_start
    
    # DEBUG: Show what the LLM actually returned
    if refined:
        logger.info(f"[REFINE DEBUG] Raw LLM output ({len(refined)} chars): {refined[:100]}...")
        logger.info(f"[REFINE DEBUG] Original ({len(preprocessed)} chars): {preprocessed[:100]}...")
        is_same = refined.strip().lower() == preprocessed.strip().lower()
        logger.info(f"[REFINE DEBUG] Output same as input: {is_same}")
    
    log_step("generation_complete", {
        "attempt": 1,
        "success": refined is not None,
        "output_length": len(refined) if refined else 0,
        "generation_time_ms": round(gen_time * 1000, 2)
    })
    
    # ========================================
    # STEP 6: Validate output (attempt 1)
    # ========================================
    if refined:
        log_step("validation_start", {"attempt": 1})
        is_valid, errors, validation_meta = validate_output(
            refined_text=refined,
            original_text=preprocessed,
            protected_facts=protected_facts,
            is_retry=False
        )
        log_step("validation_complete", {
            "attempt": 1,
            "valid": is_valid,
            "errors": errors,
            "length_ratio": validation_meta.get("length_ratio", 0),
            "expansion_detected": validation_meta.get("expansion_detected", False)
        })
        
        if is_valid:
            # Success on first try
            result["refined_text"] = refined
            result["validation_passed"] = True
            result["metadata"] = {
                "pipeline_log": pipeline_log,
                "validation": validation_meta,
                "total_time": time.time() - start_time,
                "attempts": 1,
                "generation_time_ms": round(gen_time * 1000, 2),
                "prompt_length": prompt_length,
                "mode": mode
            }
            logger.info(f"[REFINE] SUCCESS: mode={mode}, gen_time={round(gen_time * 1000, 2)}ms, prompt_len={prompt_length}")
            return result
        
        # ========================================
        # STEP 7: Retry if needed and allowed
        # ========================================
        if max_retries > 0:
            log_step("retry_start", {"reason": errors})
            
            # Build stricter retry prompt
            retry_prompt = build_retry_prompt(prompt, errors, preprocessed)
            
            # Generate again with stricter prompt
            log_step("generation_start", {"attempt": 2, "is_retry": True})
            gen_start_retry = time.time()
            refined_retry = generate_refinement(retry_prompt)
            gen_time_retry = time.time() - gen_start_retry
            log_step("generation_complete", {
                "attempt": 2,
                "success": refined_retry is not None,
                "generation_time_ms": round(gen_time_retry * 1000, 2)
            })
            
            if refined_retry:
                # Validate retry output (more lenient)
                log_step("validation_start", {"attempt": 2, "is_retry": True})
                is_valid_retry, errors_retry, validation_meta_retry = validate_output(
                    refined_text=refined_retry,
                    original_text=preprocessed,
                    protected_facts=protected_facts,
                    is_retry=True
                )
                log_step("validation_complete", {"attempt": 2, "valid": is_valid_retry, "errors": errors_retry})
                
                if is_valid_retry:
                    # Success on retry
                    result["refined_text"] = refined_retry
                    result["validation_passed"] = True
                    result["warnings"].append("Refinement succeeded on retry with stricter prompt")
                    result["metadata"] = {
                        "pipeline_log": pipeline_log,
                        "validation": validation_meta_retry,
                        "total_time": time.time() - start_time,
                        "attempts": 2,
                        "generation_time_ms": round(gen_time_retry * 1000, 2)
                    }
                    logger.info(f"[REFINE] SUCCESS on retry in {round(gen_time_retry * 1000, 2)}ms")
                    return result
                else:
                    # Retry failed
                    result["warnings"].append(f"Retry failed: {'; '.join(errors_retry)}")
                    logger.warning(f"[REFINE] Retry failed: {errors_retry}")
            else:
                result["warnings"].append("Retry generation failed (no output)")
                logger.warning("[REFINE] Retry generation failed (timeout)")
        else:
            result["warnings"].append(f"Validation failed: {'; '.join(errors)}")
            logger.warning(f"[REFINE] Validation failed: {errors}")
    else:
        result["warnings"].append("Initial generation failed (no output from Ollama)")
        logger.error(f"[REFINE] Initial generation failed (timeout after {gen_time:.1f}s)")
    
    # ========================================
    # FALLBACK: Return original or best attempt
    # ========================================
    fallback_text, fallback_used, fallback_warnings = determine_fallback_action(
        original_text=preprocessed,
        refined_text=refined,
        validation_errors=errors if refined else ["No output generated"],
        is_retry=(max_retries > 0)
    )
    
    result["refined_text"] = fallback_text
    result["fallback_used"] = fallback_used
    result["warnings"].extend(fallback_warnings)
    
    result["metadata"] = {
        "pipeline_log": pipeline_log,
        "total_time": time.time() - start_time,
        "attempts": 2 if max_retries > 0 and refined else 1,
        "prompt_length": prompt_length,
        "generation_time_ms": round(gen_time * 1000, 2) if refined else None
    }
    
    logger.warning(f"[REFINE] FALLBACK used. Warnings: {result['warnings']}")
    
    return result


def _preprocess_input(text: str) -> str:
    """
    Preprocess input text before refinement.
    
    - Normalize whitespace
    - Clean repeated punctuation
    - Keep original meaning intact
    
    Args:
        text: Raw input text
        
    Returns:
        Preprocessed text
    """
    if not text:
        return ""
    
    # Strip whitespace
    text = text.strip()
    
    # Normalize whitespace (multiple spaces to single)
    text = re.sub(r'\s+', ' ', text)
    
    # Clean repeated punctuation
    text = re.sub(r'\.{3,}', '...', text)  # More than 3 dots to ellipsis
    text = re.sub(r',{2,}', ',', text)     # Multiple commas to one
    text = re.sub(r'!{2,}', '!', text)     # Multiple exclamation to one
    text = re.sub(r'\?{2,}', '?', text)    # Multiple question to one
    
    # Clean space before punctuation
    text = re.sub(r'\s+([.,!?;:])', r'\1', text)
    
    # Ensure space after punctuation (except for abbreviations)
    text = re.sub(r'([.,!?;:])([^\s])', r'\1 \2', text)
    
    # Trim again
    text = text.strip()
    
    return text


# Legacy compatibility - simple function signature for existing code
def refine_text_legacy(raw_text: str, ollama_base_url: Optional[str] = None) -> Optional[str]:
    """
    Legacy-compatible interface that calls the new pipeline.
    
    Args:
        raw_text: The announcement text to refine
        ollama_base_url: Ignored (kept for API compatibility)
        
    Returns:
        Refined text or None if refinement fails completely
    """
    result = refine_text_pipeline(raw_text, enable_logging=False, max_retries=0)
    
    # Return None only if we have a complete failure (shouldn't happen)
    refined = result.get("refined_text", "")
    return refined if refined and refined.strip() else None
