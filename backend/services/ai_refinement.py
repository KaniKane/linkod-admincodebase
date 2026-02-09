"""
AI-Based Text Refinement module.

Calls local Ollama (llama3.2:3b) to refine announcement text only.
- Does NOT add new information.
- Does NOT decide audience.
- Output: formal, clear, concise version of the input.
"""

import httpx
from typing import Optional

# Default Ollama base URL (local)
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "llama3.2:3b"

# System prompt: constrain the model to refinement only
REFINEMENT_SYSTEM_PROMPT = """You are a text refinement assistant for barangay announcements.
Your task is ONLY to:
- Make the text formal, clear, and concise.
- Fix grammar and spelling.
- Improve readability.

You must NOT:
- Add new information or facts.
- Suggest or decide who the audience should be.
- Change the meaning of the message.


Output ONLY the refined text, nothing else. No preamble, no explanation."""

# System prompt: Tandaganon Expert (Rule-Based + Contextual)
TANDAGANON_SYSTEM_PROMPT = """You are a Barangay Official from Tandag City, Surigao del Sur. 
Rewrite the following announcement into authentic **Tandaganon Bisaya** (Surigaonon).

**STRICT DIALECT RULES:**
1. CHANGE 'Karon' (Now) -> 'Kuman'
2. CHANGE 'Ugma' (Tomorrow) -> 'Silom'
3. CHANGE 'Gahapon' (Yesterday) -> 'Kahapon'
4. CHANGE 'Unya' (Later) -> 'Ngaj-an'
5. CHANGE 'Wala' (None) -> 'Waya'
6. CHANGE 'Diri' (Here) -> 'Dini'
7. CHANGE 'Didto' (There) -> 'Did-on'
8. CHANGE 'Unsa' (What) -> 'Uno'
9. CHANGE 'Kinsa' (Who) -> 'Sin-o'
10. CHANGE 'Asa' (Where) -> 'Hain'
11. CHANGE 'Maayo' (Good) -> 'Marajaw'
12. CHANGE 'Daghan' (Many) -> 'Hamok'
13. USE 'Nan' instead of 'Ug' or 'Og' (e.g., "Hatag nan tambal").

**TONE:** Formal, Clear, and Authoritative but Local.

Output ONLY the translated/refined text, nothing else."""


def refine_text(raw_text: str, dialect: str = "english", ollama_base_url: str = OLLAMA_BASE_URL) -> Optional[str]:
    """
    Call Ollama to refine or translate the given text.
    - dialect: "english" (default refinement) or "tandaganon" (dialect translation).
    Returns refined text or None on failure.
    """
    if not raw_text or not raw_text.strip():
        return None

    if dialect.lower() == "tandaganon":
        system_prompt = TANDAGANON_SYSTEM_PROMPT
        user_prompt = f"**INPUT TEXT:**\n\"{raw_text.strip()}\"\n\n**OUTPUT (Tandaganon Only):**"
    else:
        system_prompt = REFINEMENT_SYSTEM_PROMPT
        user_prompt = f"Refine the following announcement:\n\n{raw_text.strip()}"

    try:
        # Ollama can be slow on first run or under load; 90s reduces client timeouts
        with httpx.Client(timeout=90.0) as client:
            # Ollama /api/generate for completion-style response
            response = client.post(
                f"{ollama_base_url}/api/generate",
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": user_prompt,
                    "system": system_prompt,
                    "stream": False,
                },
            )
            response.raise_for_status()
            data = response.json()
            refined = (data.get("response") or "").strip()
            if not refined:
                return None
            return refined
    except (httpx.HTTPError, httpx.RequestError, KeyError):
        return None
