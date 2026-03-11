"""
Rewrite generator for the refinement pipeline.

Calls Ollama with stricter parameters to reduce hallucination.
"""

import httpx
from typing import Optional, Dict, Any

# Ollama configuration
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"

# Stricter generation parameters for the 3B model
# Lower temperature reduces creativity/hallucination
DEFAULT_PARAMS = {
    "temperature": 0.3,      # Low temperature for deterministic output
    "top_p": 0.9,           # Nucleus sampling
    "num_predict": 400,     # Max tokens to generate
    "top_k": 40,            # Top-k sampling
    "repeat_penalty": 1.1,  # Penalize repetition
    "stop": ["\n\n", "Explanation:", "Note:", "Draft:", "Examples:"]  # Stop sequences
}


def generate_refinement(
    prompt: str,
    ollama_base_url: str = OLLAMA_BASE_URL,
    model: str = OLLAMA_MODEL,
    generation_params: Optional[Dict[str, Any]] = None,
    timeout: float = 60.0  # 60s timeout - single attempt with max_retries=0 fits in 120s frontend limit
) -> Optional[str]:
    """
    Generate refined text using Ollama.
    
    Args:
        prompt: The complete prompt to send to Ollama
        ollama_base_url: Base URL for Ollama API
        model: Model name to use
        generation_params: Optional override for generation parameters
        timeout: Request timeout in seconds
        
    Returns:
        Generated text or None if generation failed
    """
    if not prompt or not prompt.strip():
        return None
    
    # Merge default params with any overrides
    params = {**DEFAULT_PARAMS, **(generation_params or {})}
    
    # Check Ollama health first (quick check, 2s timeout)
    is_healthy, health_msg = check_ollama_health(ollama_base_url, timeout=2.0)
    if not is_healthy:
        print(f"[WARNING] Ollama health check failed: {health_msg}")
        return None
    
    try:
        with httpx.Client(timeout=timeout) as client:
            response = client.post(
                f"{ollama_base_url}/api/generate",
                json={
                    "model": model,
                    "prompt": prompt,
                    "stream": False,
                    **params
                }
            )
            
            response.raise_for_status()
            data = response.json()
            
            generated_text = data.get("response", "").strip()
            
            # Clean up common unwanted prefixes
            generated_text = _clean_output(generated_text)
            
            return generated_text if generated_text else None
            
    except httpx.TimeoutException:
        # Timeout is a common issue with local models
        print(f"[ERROR] Ollama timeout after {timeout}s - model may be slow or overloaded")
        return None
    except httpx.HTTPError as e:
        # Connection or HTTP error
        print(f"[ERROR] Ollama HTTP error: {e}")
        return None
    except Exception as e:
        # Any other error
        print(f"[ERROR] Ollama generation failed: {e}")
        return None


def _clean_output(text: str) -> str:
    """
    Clean common unwanted prefixes from model output.
    
    Args:
        text: Raw generated text
        
    Returns:
        Cleaned text
    """
    if not text:
        return text
    
    # List of prefixes to remove
    prefixes_to_remove = [
        "Refined:",
        "Refined text:",
        "Refined announcement:",
        "Here is the refined text:",
        "Here is the refined announcement:",
        "Output:",
        "Result:",
        "Final:",
        "---",
    ]
    
    cleaned = text
    for prefix in prefixes_to_remove:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()
    
    # Remove quotes if the entire text is wrapped
    if (cleaned.startswith('"') and cleaned.endswith('"')) or \
       (cleaned.startswith("'") and cleaned.endswith("'")):
        cleaned = cleaned[1:-1].strip()
    
    return cleaned


def check_ollama_health(
    ollama_base_url: str = OLLAMA_BASE_URL,
    model: str = OLLAMA_MODEL,
    timeout: float = 5.0
) -> Dict[str, Any]:
    """
    Check if Ollama is running and the model is available.
    
    Args:
        ollama_base_url: Base URL for Ollama API
        model: Model name to check
    Returns:
        Tuple of (is_healthy: bool, message: str)
    """
    try:
        response = httpx.get(f"{ollama_base_url}/api/tags", timeout=timeout)
        if response.status_code == 200:
            data = response.json()
            models = [m.get('name', m.get('model', 'unknown')) for m in data.get('models', [])]
            if OLLAMA_MODEL in [m.split(':')[0] for m in models] or any(OLLAMA_MODEL in m for m in models):
                return True, f"Ollama running, model {OLLAMA_MODEL} available"
            else:
                return False, f"Ollama running but {OLLAMA_MODEL} not found. Available: {models[:3]}"
        else:
            return False, f"Ollama returned status {response.status_code}"
    except httpx.ConnectError:
        return False, f"Cannot connect to Ollama at {ollama_base_url}. Is it running?"
    except httpx.TimeoutException:
        return False, "Connection to Ollama timed out"
    except Exception as e:
        return False, f"Error checking Ollama: {str(e)[:50]}"


def get_model_info(
    ollama_base_url: str = OLLAMA_BASE_URL,
    model: str = OLLAMA_MODEL,
    timeout: float = 5.0
) -> Dict[str, Any]:
    """
    Get information about the configured model.
    
    Args:
        ollama_base_url: Base URL for Ollama API
        model: Model name
        timeout: Request timeout
        
    Returns:
        Dictionary with model information
    """
    health = check_ollama_health(ollama_base_url, model, timeout)
    
    return {
        "model": model,
        "base_url": ollama_base_url,
        "generation_params": DEFAULT_PARAMS,
        **health
    }
