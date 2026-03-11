"""
Output validation for refined announcements.

Implements conservative validation rules that prioritize factual preservation
over stylistic improvements. Designed to catch hallucinations, fact drift,
and inappropriate dialect usage.

Validation philosophy:
- Better to reject good output than accept bad output
- Facts are sacred - any deviation is a failure
- Dialect confidence must be explicitly validated
- Length and repetition are soft warnings, not hard failures
- Unknown terms are flagged for review
"""

import re
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from abc import ABC, abstractmethod


@dataclass
class ValidationResult:
    """Result of output validation."""
    is_valid: bool
    reason: Optional[str] = None
    warnings: List[str] = field(default_factory=list)
    scores: Dict[str, float] = field(default_factory=dict)


@dataclass
class CheckResult:
    """Result of a single validation check."""
    passed: bool
    reason: Optional[str] = None
    warnings: Optional[List[str]] = None
    scores: Optional[Dict[str, float]] = None


class ValidationCheck(ABC):
    """Abstract base class for validation checks."""
    
    @abstractmethod
    def check(
        self,
        output: Dict[str, Any],
        input_facts: List[Any],
        original_text: str
    ) -> CheckResult:
        """
        Perform validation check.
        
        Args:
            output: Parsed JSON output from provider
            input_facts: List of PreservedFact objects
            original_text: Original input text
            
        Returns:
            CheckResult indicating pass/fail with details
        """
        pass


class EmptyCheck(ValidationCheck):
    """Check that output is not empty."""
    
    def check(self, output, input_facts, original_text):
        text = output.get("refined_text", "")
        if not text or not text.strip():
            return CheckResult(
                passed=False,
                reason="Empty output"
            )
        return CheckResult(passed=True)


class MarkdownCheck(ValidationCheck):
    """Check that output doesn't contain markdown artifacts."""
    
    def check(self, output, input_facts, original_text):
        text = output.get("refined_text", "")
        
        # Check for code blocks
        if "```" in text:
            return CheckResult(
                passed=False,
                reason="Contains markdown code blocks"
            )
        
        # Check for explanation prefixes
        explanation_patterns = [
            r'^(Explanation|Note|Here is|Below is|Refined text):',
            r'^(Here is the|The following is a) refined',
            r'^(I have|The model has) refined',
        ]
        
        for pattern in explanation_patterns:
            if re.search(pattern, text, re.IGNORECASE):
                return CheckResult(
                    passed=False,
                    reason=f"Contains explanation prefix matching pattern"
                )
        
        return CheckResult(passed=True)


class FactPreservationCheck(ValidationCheck):
    """
    Check that all preserved facts appear in output.
    This is the most critical validation.
    """
    
    def __init__(self, min_preservation_score: float = 0.9):
        self.min_preservation_score = min_preservation_score
    
    def check(self, output, input_facts, original_text):
        refined_text = output.get("refined_text", "").lower()
        
        if not input_facts:
            # No facts to preserve - pass with neutral score
            return CheckResult(
                passed=True,
                scores={"fact_preservation": 1.0}
            )
        
        missing_facts = []
        found_facts = []
        
        for fact in input_facts:
            fact_value_lower = fact.value.lower()
            
            # Try exact match first
            if fact_value_lower in refined_text:
                found_facts.append(fact)
                continue
            
            # Try normalized match (remove punctuation, extra spaces)
            normalized_fact = self._normalize(fact_value_lower)
            normalized_text = self._normalize(refined_text)
            
            if normalized_fact in normalized_text:
                found_facts.append(fact)
                continue
            
            # Try fuzzy match for dates/times (common variations)
            if fact.fact_type in ["date", "time"]:
                if self._fuzzy_time_date_match(fact.value, refined_text):
                    found_facts.append(fact)
                    continue
            
            missing_facts.append(fact)
        
        # Calculate preservation score
        preservation_score = len(found_facts) / len(input_facts)
        
        # Build result
        if missing_facts:
            missing_types = [f.fact_type for f in missing_facts]
            return CheckResult(
                passed=False,
                reason=f"Missing facts: {', '.join(missing_types)}. "
                       f"Preservation score: {preservation_score:.0%}",
                scores={"fact_preservation": preservation_score}
            )
        
        return CheckResult(
            passed=True,
            scores={"fact_preservation": preservation_score}
        )
    
    def _normalize(self, text: str) -> str:
        """Normalize text for comparison."""
        # Remove extra whitespace
        text = ' '.join(text.split())
        # Remove common punctuation
        text = re.sub(r'[.,;:]', '', text)
        return text.lower()
    
    def _fuzzy_time_date_match(self, fact_value: str, text: str) -> bool:
        """
        Fuzzy matching for dates and times with common variations.
        
        Examples:
        - "January 15, 2026" matches "January 15 2026" or "Jan 15, 2026"
        - "8:00 sa buntag" matches "8:00 AM" or "8:00 buntag"
        """
        import re
        
        # Extract numbers from fact
        numbers_in_fact = set(re.findall(r'\d+', fact_value))
        numbers_in_text = set(re.findall(r'\d+', text))
        
        # If all numbers from fact appear in text, consider it a match
        if numbers_in_fact and numbers_in_fact <= numbers_in_text:
            return True
        
        return False


class FactIntegrityCheck(ValidationCheck):
    """
    Check that facts haven't been modified (not just missing).
    Verifies dates, times, and numbers are unchanged.
    """
    
    def check(self, output, input_facts, original_text):
        refined_text = output.get("refined_text", "")
        warnings = []
        
        for fact in input_facts:
            if fact.fact_type == "date":
                # Extract year from original
                years_original = set(re.findall(r'\d{4}', fact.value))
                years_output = set(re.findall(r'\d{4}', refined_text))
                
                # Check for year mismatch
                if years_original and years_original != years_output:
                    # Years changed - this is serious
                    return CheckResult(
                        passed=False,
                        reason=f"Year changed in date: {fact.value} -> years found: {years_output}"
                    )
        
        return CheckResult(passed=True, warnings=warnings)


class LengthCheck(ValidationCheck):
    """
    Context-aware length validation with content type sensitivity.
    
    Philosophy:
    - Short inputs can expand more (adding formalities)
    - Long inputs should stay compact
    - Emergency content must stay tight
    - Event/community content can breathe more
    """
    
    # Content type multipliers (base ratio * multiplier)
    CONTENT_MULTIPLIERS = {
        "emergency": 1.2,      # Emergency: tight, no fluff
        "reminder": 2.0,       # Reminders: can expand for clarity
        "event": 2.5,          # Events: more descriptive OK
        "health": 2.0,         # Health: educational content OK
        "4ps": 1.8,            # 4Ps: official but can explain
        "ordinance": 1.5,       # Ordinances: formal, tight
        "general": 2.0,        # General: default expansion
    }
    
    # Input length thresholds for different base ratios
    SHORT_INPUT_MAX = 50      # <=50 chars: can expand 4x
    MEDIUM_INPUT_MAX = 150    # 51-150 chars: can expand 3x
    LONG_INPUT_MIN = 300      # >=300 chars: max 1.5x expansion
    
    def __init__(self, 
                 min_ratio: float = 0.3,  # Don't shrink below 30%
                 hard_max_ratio: float = 4.0):  # Absolute ceiling
        self.min_ratio = min_ratio
        self.hard_max_ratio = hard_max_ratio
    
    def check(self, output, input_facts, original_text):
        content_type = output.get("content_type", "general")
        refined_text = output.get("refined_text", "")
        
        input_len = len(original_text.strip())
        output_len = len(refined_text)
        
        if input_len == 0:
            return CheckResult(passed=True)
        
        ratio = output_len / input_len
        
        # Determine base max ratio by input length
        if input_len <= self.SHORT_INPUT_MAX:
            base_max = 4.0
        elif input_len <= self.MEDIUM_INPUT_MAX:
            base_max = 3.0
        elif input_len >= self.LONG_INPUT_MIN:
            base_max = 1.5
        else:
            base_max = 2.0
        
        # Apply content type multiplier
        multiplier = self.CONTENT_MULTIPLIERS.get(content_type, 2.0)
        allowed_max = min(base_max * multiplier, self.hard_max_ratio)
        
        warnings = []
        
        # Soft warnings at 80% of limit
        if ratio > allowed_max * 0.8 and ratio <= allowed_max:
            warnings.append(f"Output length {ratio:.0%} near limit {allowed_max:.0%}")
        
        # Hard failures
        if ratio < self.min_ratio:
            return CheckResult(
                passed=False,
                reason=f"Output too short ({ratio:.0%} < {self.min_ratio:.0%})",
                warnings=warnings,
                scores={"length_ratio": ratio}
            )
        
        if ratio > allowed_max:
            return CheckResult(
                passed=False,
                reason=f"Output too long ({ratio:.0%} > {allowed_max:.0%}) for {content_type}",
                warnings=warnings,
                scores={"length_ratio": ratio, "allowed_max": allowed_max}
            )
        
        return CheckResult(
            passed=True,
            warnings=warnings,
            scores={"length_ratio": ratio}
        )


class RepetitionCheck(ValidationCheck):
    """Check for excessive repetition in output."""
    
    def check(self, output, input_facts, original_text):
        text = output.get("refined_text", "")
        words = text.split()
        
        if len(words) < 8:
            return CheckResult(passed=True)
        
        # Check for repeated 4-grams
        ngrams = []
        for i in range(len(words) - 3):
            ngram = ' '.join(words[i:i+4]).lower()
            ngrams.append(ngram)
        
        from collections import Counter
        counts = Counter(ngrams)
        
        # Find repeats
        repeats = [(ng, c) for ng, c in counts.items() if c > 2]
        
        if repeats:
            most_common = repeats[0]
            return CheckResult(
                passed=False,
                reason=f"Excessive repetition detected: '{most_common[0]}' appears {most_common[1]} times"
            )
        
        return CheckResult(passed=True)


class DialectConfidenceCheck(ValidationCheck):
    """
    Check that model-reported dialect confidence is reasonable.
    Also validates that claimed terms were actually used.
    """
    
    def __init__(self, min_confidence: float = 0.5):
        self.min_confidence = min_confidence
    
    def check(self, output, input_facts, original_text):
        warnings = []
        
        # Check model confidence
        dialect_confidence = output.get("dialect_confidence", 0.0)
        
        if dialect_confidence < self.min_confidence:
            warnings.append(
                f"Low dialect confidence ({dialect_confidence:.2f} < {self.min_confidence})"
            )
        
        # Verify claimed terms were actually used
        refined_text = output.get("refined_text", "").lower()
        claimed_terms = output.get("tandaganon_terms_used", [])
        
        unused_terms = []
        for term in claimed_terms:
            if term.lower() not in refined_text:
                unused_terms.append(term)
        
        if unused_terms:
            return CheckResult(
                passed=False,
                reason=f"Claimed Tandaganon terms not found in output: {', '.join(unused_terms)}"
            )
        
        # If terms were used but confidence is low, that's suspicious
        if claimed_terms and dialect_confidence < 0.3:
            return CheckResult(
                passed=False,
                reason=f"Used {len(claimed_terms)} Tandaganon terms but reported low confidence ({dialect_confidence:.2f})"
            )
        
        return CheckResult(
            passed=True,
            warnings=warnings,
            scores={"dialect_confidence": dialect_confidence}
        )


class InventionCheck(ValidationCheck):
    """
    Check for potential hallucinations - entities not in input.
    Conservative check for proper nouns that might be invented.
    """
    
    # Whitelist of common barangay-related terms that can appear
    COMMON_TERMS = {
        'barangay', 'captain', 'kapitan', 'kagawad', 'secretary', 'treasurer',
        'municipal', 'city', 'province', 'bayabas', 'tandag', 'surigao',
        'philippines', 'pilipinas', 'mingham', 'cagbaoto', 'panaosawon',
        'barangayanon', 'kaigsuonan', 'katawhan', 'lumolupyo',
        'brigada', 'eskwela', 'sk', 'sangguniang', 'kabataan',
        'dswd', '4ps', 'pantawid', 'pamilya', 'pwd', 'senior',
    }
    
    def check(self, output, input_facts, original_text):
        refined_text = output.get("refined_text", "")
        original_lower = original_text.lower()
        
        # Extract capitalized words (potential proper nouns)
        # This is a heuristic - in production, use NER
        potential_inventions = re.findall(r'\b[A-Z][a-zA-Z]{2,}\b', refined_text)
        
        inventions = []
        for word in potential_inventions:
            word_lower = word.lower()
            # Skip if in whitelist
            if word_lower in self.COMMON_TERMS:
                continue
            # Skip if in original
            if word_lower in original_lower:
                continue
            # Skip common English words
            if word_lower in {'the', 'and', 'for', 'you', 'your', 'our', 'their'}:
                continue
            inventions.append(word)
        
        # If more than 2 potential inventions, flag for review
        if len(inventions) > 2:
            return CheckResult(
                passed=False,
                reason=f"Potential inventions detected: {', '.join(inventions[:3])}. "
                       f"Total: {len(inventions)} new terms not in input."
            )
        
        warnings = []
        if inventions:
            warnings.append(f"New terms not in input: {', '.join(inventions)}")
        
        return CheckResult(passed=True, warnings=warnings)


class OutputValidator:
    """
    Comprehensive output validator implementing conservative validation.
    
    Runs multiple validation checks in sequence. Any hard failure rejects
    the output. Warnings are collected but don't block acceptance.
    
    Usage:
        validator = OutputValidator(min_fact_preservation_score=0.9)
        result = validator.validate(
            output={"refined_text": "...", "dialect_confidence": 0.8},
            input_facts=[PreservedFact(...)],
            original_text="..."
        )
        
        if result.is_valid:
            print("Validation passed")
        else:
            print(f"Failed: {result.reason}")
    """
    
    def __init__(
        self,
        min_fact_preservation_score: float = 0.9,
        min_dialect_confidence: float = 0.5
    ):
        """
        Initialize validator with thresholds.
        
        Args:
            min_fact_preservation_score: Minimum fact preservation (0-1)
            min_dialect_confidence: Minimum dialect confidence (0-1)
        """
        self.min_fact_preservation_score = min_fact_preservation_score
        
        # Initialize all checks
        self.checks: List[ValidationCheck] = [
            EmptyCheck(),                          # Must have content
            MarkdownCheck(),                       # No markdown artifacts
            FactPreservationCheck(min_fact_preservation_score),  # Critical
            FactIntegrityCheck(),                  # Facts not modified
            LengthCheck(),                         # Reasonable length
            RepetitionCheck(),                     # No excessive repetition
            DialectConfidenceCheck(min_dialect_confidence),
            InventionCheck(),                      # No hallucinations
        ]
    
    def validate(
        self,
        output: Dict[str, Any],
        input_facts: List[Any],
        original_text: str
    ) -> ValidationResult:
        """
        Validate output against all checks.
        
        Args:
            output: Parsed JSON output from provider
            input_facts: List of PreservedFact objects from input analysis
            original_text: Original input text for comparison
            
        Returns:
            ValidationResult with is_valid, reason, warnings, and scores
        """
        all_warnings = []
        all_scores = {}
        
        for check in self.checks:
            result = check.check(output, input_facts, original_text)
            
            if not result.passed:
                # Hard failure - return immediately
                return ValidationResult(
                    is_valid=False,
                    reason=result.reason,
                    warnings=all_warnings + (result.warnings or []),
                    scores=all_scores
                )
            
            # Collect warnings and scores
            if result.warnings:
                all_warnings.extend(result.warnings)
            if result.scores:
                all_scores.update(result.scores)
        
        # All checks passed
        return ValidationResult(
            is_valid=True,
            warnings=all_warnings,
            scores=all_scores
        )
    
    def validate_fast(self, output: Dict[str, Any]) -> ValidationResult:
        """
        Fast validation without fact comparison.
        
        Use for preliminary checks before full validation.
        """
        # Run only critical checks
        critical_checks = [EmptyCheck(), MarkdownCheck()]
        
        for check in critical_checks:
            result = check.check(output, [], "")
            if not result.passed:
                return ValidationResult(
                    is_valid=False,
                    reason=f"Critical check failed: {result.reason}"
                )
        
        return ValidationResult(is_valid=True)


# Backward compatibility function
def validate_output(output: str, input_text: str) -> ValidationResult:
    """
    Legacy validation function for backward compatibility.
    
    Args:
        output: Refined text (string, not structured dict)
        input_text: Original input text
        
    Returns:
        ValidationResult
    """
    # Wrap string output in expected dict format
    output_dict = {
        "refined_text": output,
        "dialect_confidence": 0.5,
        "tandaganon_terms_used": [],
        "warnings": []
    }
    
    # Create minimal facts list
    # In production, this should use proper fact extraction
    class MockFact:
        def __init__(self, t, v):
            self.fact_type = t
            self.value = v
    
    # Extract simple facts from input for basic validation
    import re
    facts = []
    
    # Look for dates
    dates = re.findall(r'\b\w+\s+\d{1,2},?\s*\d{4}', input_text)
    for d in dates:
        facts.append(MockFact("date", d))
    
    # Look for times
    times = re.findall(r'\b(?:alas\s+)?\d{1,2}(?::\d{2})?\s*(?:sa\s+)?(?:buntag|hapon|gabii)', input_text, re.IGNORECASE)
    for t in times:
        facts.append(MockFact("time", t))
    
    validator = OutputValidator()
    return validator.validate(output_dict, facts, input_text)
