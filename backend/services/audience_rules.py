"""
Rule-Based Audience Recommendation module.

Audience targeting is rule-based only (no AI). Rules map keywords to audience groups.
Transparent and explainable: returns which rules matched and why.
"""

import json
import re
import sys
from pathlib import Path
from typing import Any, List, Optional


def _to_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _build_keyword_pattern(keyword: str) -> str:
    """Build a safe boundary-aware regex; plurals are only expanded for simple alpha tokens."""
    kw = (keyword or "").strip().lower()
    if not kw:
        return ""

    escaped = re.escape(kw)
    is_simple_alpha_word = bool(re.fullmatch(r"[a-z]{3,}", kw))
    suffix = r"(?:s|es)?" if is_simple_alpha_word else ""

    # Use non-word boundaries so keywords with apostrophes/hyphens still match safely.
    return rf"(?<!\w){escaped}{suffix}(?!\w)"


def _keyword_weight(
    keyword: str,
    weak_keywords: set[str],
    strong_keywords: set[str],
) -> float:
    kw = (keyword or "").strip().lower()
    if not kw:
        return 0.0
    if kw in strong_keywords:
        return 1.3
    if kw in weak_keywords:
        return 0.35

    token_count = len(re.findall(r"[a-z0-9']+", kw))
    if token_count >= 2:
        return 1.2
    if any(ch.isdigit() for ch in kw):
        return 1.2

    normalized_len = len(re.sub(r"[^a-z0-9]", "", kw))
    if normalized_len >= 9:
        return 1.1
    if normalized_len >= 6:
        return 1.0
    if normalized_len >= 4:
        return 0.8
    return 0.6

def _default_rules_path() -> Path:
    """Config path: dev = backend root; PyInstaller = bundle root or next to exe."""
    base = Path(__file__).resolve().parent.parent
    candidate = base / "config" / "audience_rules.json"
    if candidate.exists():
        return candidate
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        fallback = exe_dir / "config" / "audience_rules.json"
        if fallback.exists():
            return fallback
        return exe_dir / "config" / "audience_rules.json"
    return candidate

DEFAULT_RULES_PATH = _default_rules_path()

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
        require_strong_keyword = bool(rule.get("require_strong_keyword", False))
        weak_keywords = {
            (k or "").strip().lower()
            for k in (rule.get("weak_keywords") or [])
            if (k or "").strip()
        }
        strong_keywords = {
            (k or "").strip().lower()
            for k in (rule.get("strong_keywords") or [])
            if (k or "").strip()
        }
        min_score = _to_float(rule.get("min_score"), 1.0)

        if not keywords or not audiences:
            continue
        if not isinstance(keywords, list):
            keywords = [keywords]
        if not isinstance(audiences, list):
            audiences = [audiences]

        matched_keywords: list[str] = []
        score = 0.0
        matched_strong_keyword = False

        # Score all matched keywords; ignore very weak single-word accidental matches.
        for kw in keywords:
            kw_clean = (kw or "").strip().lower()
            if not kw_clean:
                continue

            pattern = _build_keyword_pattern(kw_clean)
            if not pattern:
                continue
            if re.search(pattern, text_lower):
                matched_keywords.append(kw_clean)
                if kw_clean in strong_keywords:
                    matched_strong_keyword = True
                score += _keyword_weight(kw_clean, weak_keywords, strong_keywords)

        if not matched_keywords or score < min_score:
            continue

        if require_strong_keyword and strong_keywords and not matched_strong_keyword:
            continue

        # Prevent generic one-word matches like "kita" from deciding a demographic.
        if len(matched_keywords) == 1:
            only_kw = matched_keywords[0]
            only_weight = _keyword_weight(only_kw, weak_keywords, strong_keywords)
            if only_weight < 0.7:
                continue

        matched_rules.append({"keywords": keywords, "audiences": audiences})
        for a in audiences:
            a_str = (a or "").strip()
            if a_str and a_str not in seen_audiences:
                seen_audiences.add(a_str)
                audiences_ordered.append(a_str)

    if not audiences_ordered:
        return [DEFAULT_AUDIENCE], []

    return audiences_ordered, matched_rules
