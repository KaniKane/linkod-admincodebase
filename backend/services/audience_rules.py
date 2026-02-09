"""
Rule-Based Audience Recommendation module.

Audience targeting is rule-based only (no AI). Rules map keywords to audience groups.
Transparent and explainable: returns which rules matched and why.
"""

import json
import re
from pathlib import Path
from typing import Any, List, Optional

# Default path for rules config (relative to backend root)
DEFAULT_RULES_PATH = Path(__file__).resolve().parent.parent / "config" / "audience_rules.json"

# When no rule matches, return this default audience
DEFAULT_AUDIENCE = "General Residents"


def load_rules(rules_path: Optional[Path] = None) -> List[dict]:
    """
    Load rules from JSON. Each rule: { "keywords": ["word1", ...], "audiences": ["Senior", ...] }.
    Returns empty list if file missing or invalid.
    """
    path = rules_path or DEFAULT_RULES_PATH
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        rules = data.get("rules", data) if isinstance(data, dict) else data
        if not isinstance(rules, list):
            return []
        return rules
    except (FileNotFoundError, json.JSONDecodeError, TypeError):
        return []


def recommend_audiences(
    text: str,
    rules: Optional[List[dict]] = None,
    rules_path: Optional[Path] = None,
) -> tuple:
    """
    Rule-based audience recommendation from text (e.g. refined announcement).

    - text: the announcement text to check (refined or original).
    - rules: optional in-memory list; if None, loaded from rules_path.
    - rules_path: optional path to JSON; used if rules is None.

    Returns:
        (audiences, matched_rules)
        - audiences: list of audience group names (no duplicates, order preserved).
        - matched_rules: list of {"keywords": [...], "audiences": [...]} that matched (for transparency).
    If no rule matches, audiences = [DEFAULT_AUDIENCE], matched_rules = [].
    """
    if rules is None:
        rules = load_rules(rules_path)

    text_lower = (text or "").strip().lower()
    if not text_lower:
        return [DEFAULT_AUDIENCE], []

    seen_audiences: set[str] = set()
    audiences_ordered: list[str] = []
    matched_rules: list[dict[str, Any]] = []

    for rule in rules:
        keywords = rule.get("keywords") or rule.get("keyword_list") or []
        audiences = rule.get("audiences") or rule.get("audience_groups") or []
        if not keywords or not audiences:
            continue
        if not isinstance(keywords, list):
            keywords = [keywords]
        if not isinstance(audiences, list):
            audiences = [audiences]
        # Check if any keyword matches using regex (case-insensitive due to text_lower)
        for kw in keywords:
            kw_clean = (kw or "").strip().lower()
            if not kw_clean:
                continue
            
            # Escape keyword but allow for simple English plurals (s or es) at the end
            # \b ensures distinct word boundaries (e.g. "task" won't match "sk")
            # We use re.escape to handle special chars like "4p's" safely
            pattern = r'\b' + re.escape(kw_clean) + r'(?:s|es)?\b'
            
            if re.search(pattern, text_lower):
                matched_rules.append({"keywords": keywords, "audiences": audiences})
                for a in audiences:
                    a_str = (a or "").strip()
                    if a_str and a_str not in seen_audiences:
                        seen_audiences.add(a_str)
                        audiences_ordered.append(a_str)
                break

    if not audiences_ordered:
        return [DEFAULT_AUDIENCE], []

    return audiences_ordered, matched_rules
