"""
Refinement service orchestrating AI providers with validation and retry logic.

Implements a 5-stage pipeline:
1. Input analysis (content classification, fact extraction)
2. Example retrieval (relevant few-shot examples)
3. Prompt building (structured prompts with constraints)
4. Generation with validation
5. Retry/downgrade resolution

Design principles:
- Factual preservation is paramount
- Conservative dialect application (default to Cebuano)
- Structured JSON outputs from all providers
- Provider-agnostic orchestration
- Machine validation before returning to clients
"""

import uuid
import time
import logging
import json
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any, Tuple
from enum import Enum

# Local imports - TODO: adjust paths based on actual project structure
from config.settings import get_settings
from providers.base_provider import BaseProvider
from services.prompt_builder import PromptBuilder, StructuredPrompt, PromptContext
from services.output_validator import OutputValidator, ValidationResult
from services.example_retriever import ExampleRetriever, RetrievedExample

logger = logging.getLogger(__name__)


class ContentType(Enum):
    """Supported content types for barangay announcements."""
    EMERGENCY = "emergency"
    EVENT = "event"
    REMINDER = "reminder"
    HEALTH = "health"
    FOUR_PS = "4ps"
    ORDINANCE = "ordinance"
    GENERAL = "general"


class DialectMode(Enum):
    """Dialect application levels."""
    NONE = "none"
    CEBUANO = "cebuano"
    TANDAGANON_LIGHT = "tandaganon_light"
    TANDAGANON_HIGH = "tandaganon_high"


@dataclass
class PreservedFact:
    """A fact extracted from input that must be preserved."""
    fact_type: str  # e.g., "date", "time", "location", "name"
    value: str
    confidence: float = 1.0  # extraction confidence


@dataclass
class AnalysisResult:
    """Result of input analysis stage."""
    content_type: ContentType
    audience: List[str]
    preserved_facts: List[PreservedFact]
    dialect_recommendation: DialectMode
    dialect_confidence: float
    input_length: int


@dataclass
class RefinementResult:
    """Complete result from refinement operation."""
    # Core fields
    success: bool
    original_text: str
    refined_text: str
    
    # Provider metadata
    provider_used: str
    fallback_used: bool
    
    # Analysis metadata
    content_type: str
    audience: List[str]
    dialect_applied: str
    dialect_confidence: float
    
    # Validation metadata
    preserved_facts: Dict[str, Any]
    validation_passed: bool
    validation_warnings: List[str]
    fact_preservation_score: float
    
    # System metadata
    request_id: str
    latency_ms: int
    prompt_version: str
    retry_count: int
    
    # Optional fields
    warnings: List[str] = field(default_factory=list)
    tandaganon_terms_used: List[str] = field(default_factory=list)


class InputAnalyzer:
    """
    Stage 1: Analyze input text to extract facts and classify content.
    
    Uses rule-based extraction with regex patterns. In production,
    consider adding NER (Named Entity Recognition) for better accuracy.
    """
    
    # Patterns for content type detection
    CONTENT_PATTERNS = {
        ContentType.EMERGENCY: [
            r'\b(emergency|alert|evacuat|delikado|peligro|alerto|baha|bagyo|sunog)',
            r'\b(immediate|urgent|kritikal|importante kaayo)',
        ],
        ContentType.EVENT: [
            r'\b(event|activity|program|celebration|fiesta|tournament|miting)',
            r'\b(pagpahigayon|kalihukan|selebrasyon)',
        ],
        ContentType.HEALTH: [
            r'\b(health|medical|clinic|checkup|vaccine|bakuna|doktor|klinika)',
            r'\b(konsulta|tambal|gamot|ospital)',
        ],
        ContentType.FOUR_PS: [
            r'\b(4ps|pantawid|ayuda|cash grant|dswd|4p\'s)',
            r'\b(miyembro|benepesyaryo)',
        ],
        ContentType.ORDINANCE: [
            r'\b(ordinance|regulation|comply|tumanon|mando|regulasyon)',
            r'\b(pagbawal|silot|multa)',
        ],
        ContentType.REMINDER: [
            r'\b(remind|palihug|ayaw kalimot|hatag og hinumdum|pahinumdom)',
        ],
    }
    
    # Patterns for fact extraction
    FACT_PATTERNS = {
        "date": [
            r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Hunyo|Hulyo|Agosto|Setyembre|Oktubre|Nobyembre|Disyembre)\s+\d{1,2},?\s*\d{4}',
            r'\b(?:karong\s+)?(?:umaabot\s+)?(?:ng(?:ga)?\s+)?(?:Lunes|Martes|Miyerkules|Huwebes|Biyernes|Sabado|Domingo)',
            r'\b\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{2,4}',
        ],
        "time": [
            r'\b(?:alas\s+)?\d{1,2}(?::\d{2})?\s*(?:sa\s+buntag|sa\s+hapon|sa\s+gabii|am|pm|AM|PM|buntag|hapon|gabii)',
        ],
        "location": [
            r'\b(?:Barangay|Brgy|Barangay\s+Hall|Covered\s+Court|Gym|Session\s+Hall|Eskwelahan|Tunghaan)',
            r'\b(?:Kalsada|Dalan| intersection of|corner of)',
        ],
        "organizer": [
            r'\b(?:HON\.?\s+)?[A-Z][a-zA-Z\s]*(?:Barangay\s+Captain|Kapitan|Secretary|Kagawad)',
            r'\b(?:Gikan\s+kang|From):?\s*[A-Z][a-zA-Z\s\.]*',
        ],
    }
    
    # Tandaganon indicators with confidence weights
    TANDAGANON_INDICATORS = {
        r'\bkaigsuonan\b': 0.95,
        r'\bgihulagway\b': 0.90,
        r'\bayaw\b(?!\s*na)': 0.85,  # "ayaw" without "na"
        r'\btabang\b(?![\w\s]*an)': 0.80,  # "tabang" as standalone
        r'\bpurga\b': 0.75,
        r'\bkatiguwang\b': 0.90,
    }
    
    def __init__(self, audience_rules_path: Optional[str] = None):
        """Initialize with optional audience rules configuration."""
        self.audience_rules = self._load_audience_rules(audience_rules_path)
    
    def analyze(self, raw_text: str) -> AnalysisResult:
        """
        Analyze input text and return structured analysis.
        
        Args:
            raw_text: The original announcement text
            
        Returns:
            AnalysisResult with content type, audience, facts, and dialect recommendation
        """
        import re
        
        text_lower = raw_text.lower()
        
        # Classify content type
        content_type = self._classify_content(text_lower)
        
        # Detect audience
        audience = self._detect_audience(text_lower)
        
        # Extract facts
        preserved_facts = self._extract_facts(raw_text)
        
        # Assess dialect
        dialect_rec, dialect_conf = self._assess_dialect(text_lower)
        
        return AnalysisResult(
            content_type=content_type,
            audience=audience,
            preserved_facts=preserved_facts,
            dialect_recommendation=dialect_rec,
            dialect_confidence=dialect_conf,
            input_length=len(raw_text)
        )
    
    def _classify_content(self, text: str) -> ContentType:
        """Classify content type based on keyword patterns."""
        import re
        
        scores = {ct: 0 for ct in ContentType}
        
        for content_type, patterns in self.CONTENT_PATTERNS.items():
            for pattern in patterns:
                matches = len(re.findall(pattern, text, re.IGNORECASE))
                scores[content_type] += matches
        
        # Return type with highest score, default to GENERAL
        max_type = max(scores, key=scores.get)
        return max_type if scores[max_type] > 0 else ContentType.GENERAL
    
    def _detect_audience(self, text: str) -> List[str]:
        """Detect target audience using keyword matching."""
        import re
        
        if not self.audience_rules:
            return ["General Residents"]
        
        audiences = set()
        rules = self.audience_rules.get("rules", [])
        
        for rule in rules:
            keywords = rule.get("keywords", [])
            for keyword in keywords:
                # Use word boundary matching for accuracy
                if re.search(r'\b' + re.escape(keyword.lower()) + r'\b', text):
                    audiences.update(rule.get("audiences", []))
                    break
        
        return list(audiences) if audiences else ["General Residents"]
    
    def _extract_facts(self, text: str) -> List[PreservedFact]:
        """Extract facts that must be preserved in output."""
        import re
        
        facts = []
        
        for fact_type, patterns in self.FACT_PATTERNS.items():
            for pattern in patterns:
                matches = re.finditer(pattern, text, re.IGNORECASE)
                for match in matches:
                    facts.append(PreservedFact(
                        fact_type=fact_type,
                        value=match.group(0),
                        confidence=1.0
                    ))
        
        # Remove duplicates while preserving order
        seen = set()
        unique_facts = []
        for fact in facts:
            key = (fact.fact_type, fact.value.lower())
            if key not in seen:
                seen.add(key)
                unique_facts.append(fact)
        
        return unique_facts
    
    def _assess_dialect(self, text: str) -> Tuple[DialectMode, float]:
        """
        Assess Tandaganon dialect confidence.
        
        Returns:
            Tuple of (recommended dialect mode, confidence score)
        """
        import re
        
        total_confidence = 0.0
        indicator_count = 0
        
        for pattern, weight in self.TANDAGANON_INDICATORS.items():
            if re.search(pattern, text, re.IGNORECASE):
                total_confidence += weight
                indicator_count += 1
        
        # Calculate average confidence
        if indicator_count == 0:
            return DialectMode.CEBUANO, 0.0
        
        avg_confidence = total_confidence / indicator_count
        
        # Determine mode based on confidence and indicators
        if indicator_count >= 2 and avg_confidence >= 0.85:
            return DialectMode.TANDAGANON_HIGH, avg_confidence
        elif indicator_count >= 1 and avg_confidence >= 0.70:
            return DialectMode.TANDAGANON_LIGHT, avg_confidence
        else:
            return DialectMode.CEBUANO, avg_confidence
    
    def _load_audience_rules(self, path: Optional[str]) -> Optional[Dict]:
        """Load audience rules from JSON file."""
        if not path:
            return None
        
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            logger.warning(f"Could not load audience rules from {path}: {e}")
            return None


class ProviderRouter:
    """Routes requests to appropriate provider based on content and retry state."""
    
    def __init__(self):
        self.settings = get_settings()
        self._providers = {}
        self._initialized = False
    
    def _initialize(self):
        """Lazy initialization of providers."""
        if self._initialized:
            return
        
        from providers.openai_provider import OpenAIProvider
        from providers.ollama_provider import OllamaProvider
        
        self._providers["openai"] = OpenAIProvider()
        self._providers["ollama"] = OllamaProvider()
        
        self._initialized = True
        logger.info("Provider router initialized")
    
    def select_provider(
        self,
        analysis: AnalysisResult,
        attempt: int = 0,
        force_fallback: bool = False
    ) -> Tuple[BaseProvider, str]:
        """
        Select provider based on content type and retry attempt.
        
        Args:
            analysis: Input analysis result
            attempt: Current retry attempt number
            force_fallback: Force use of fallback provider
            
        Returns:
            Tuple of (provider instance, provider name)
        """
        self._initialize()
        
        # Check provider health
        available_providers = []
        for name, provider in self._providers.items():
            if provider.is_available():
                available_providers.append(name)
        
        if not available_providers:
            raise RuntimeError("No AI providers available")
        
        # Emergency content always prefers OpenAI for reliability
        if analysis.content_type == ContentType.EMERGENCY and not force_fallback:
            if "openai" in available_providers:
                return self._providers["openai"], "openai"
        
        # High dialect confidence needs reliable provider
        if analysis.dialect_recommendation == DialectMode.TANDAGANON_HIGH and not force_fallback:
            if "openai" in available_providers:
                return self._providers["openai"], "openai"
        
        # Retry attempts: escalate to more capable provider
        if attempt > 0:
            if "openai" in available_providers:
                return self._providers["openai"], "openai"
        
        # Default: use configured primary provider
        provider_name = self.settings.AI_PROVIDER
        if provider_name == "auto":
            # Prefer OpenAI if available, fallback to Ollama
            provider_name = "openai" if "openai" in available_providers else "ollama"
        
        if provider_name not in available_providers:
            # Fallback to any available provider
            provider_name = available_providers[0]
        
        return self._providers[provider_name], provider_name


class RefinementService:
    """
    Main refinement service implementing the 5-stage pipeline.
    
    This is the primary entry point for text refinement operations.
    """
    
    MAX_RETRIES = 1  # Matches MAX_REFINEMENT_RETRIES in settings
    
    def __init__(
        self,
        analyzer: Optional[InputAnalyzer] = None,
        retriever: Optional[ExampleRetriever] = None,
        prompt_builder: Optional[PromptBuilder] = None,
        validator: Optional[OutputValidator] = None,
        router: Optional[ProviderRouter] = None
    ):
        """
        Initialize service with optional component injection for testing.
        """
        self.settings = get_settings()
        
        self.analyzer = analyzer or InputAnalyzer(
            audience_rules_path="config/audience_rules.json"
        )
        self.retriever = retriever or ExampleRetriever(
            example_bank_path="data/example_bank.jsonl"
        )
        self.prompt_builder = prompt_builder or PromptBuilder()
        self.validator = validator or OutputValidator(
            min_fact_preservation_score=self.settings.MIN_FACT_PRESERVATION_SCORE
        )
        self.router = router or ProviderRouter()
        
        logger.info("RefinementService initialized")
    
    def refine(self, raw_text: str) -> RefinementResult:
        """
        Main refinement entry point.
        
        Executes the full 5-stage pipeline:
        1. Analyze input
        2. Retrieve examples
        3. Build prompt and generate
        4. Validate output
        5. Resolve (retry or return)
        
        Args:
            raw_text: Raw announcement text to refine
            
        Returns:
            RefinementResult with refined text and metadata
            
        Raises:
            ValueError: If input validation fails
        """
        request_id = str(uuid.uuid4())[:8]
        start_time = time.time()
        
        logger.info(f"[{request_id}] Starting refinement, input length: {len(raw_text)}")
        
        # Input validation
        if not raw_text or not raw_text.strip():
            raise ValueError("Input text cannot be empty")
        
        if len(raw_text) > self.settings.MAX_INPUT_LENGTH:
            raise ValueError(
                f"Input exceeds maximum length of {self.settings.MAX_INPUT_LENGTH} characters"
            )
        
        try:
            # Stage 1: Input Analysis
            analysis = self.analyzer.analyze(raw_text)
            logger.info(
                f"[{request_id}] Analysis: type={analysis.content_type.value}, "
                f"dialect={analysis.dialect_recommendation.value}, "
                f"facts={len(analysis.preserved_facts)}"
            )
            
            # Stage 2: Retrieve Examples
            examples = self.retriever.retrieve(
                content_type=analysis.content_type.value,
                audience=analysis.audience,
                dialect_mode=analysis.dialect_recommendation.value,
                k=2
            )
            logger.info(f"[{request_id}] Retrieved {len(examples)} examples")
            
            # Stage 3-5: Generate with validation and retry
            result = self._generate_with_retry(
                raw_text=raw_text,
                analysis=analysis,
                examples=examples,
                request_id=request_id
            )
            
            latency = int((time.time() - start_time) * 1000)
        
            # Update result with total latency
            result.latency_ms = latency if result.latency_ms == 0 else result.latency_ms
            
            # Log structured metadata (never log raw text)
            logger.info({
                "event": "refinement_complete",
                "request_id": request_id,
                "success": result.success,
                "input_length": len(raw_text),
                "output_length": len(result.refined_text),
                "provider_used": result.provider_used,
                "fallback_used": result.fallback_used,
                "latency_ms": result.latency_ms,
                "total_latency_ms": latency,
                "validation_passed": result.validation_passed,
                "retry_count": result.retry_count,
                "prompt_version": result.prompt_version,
            })
            
            return result
            
        except Exception as e:
            logger.error(f"[{request_id}] Refinement failed: {e}")
            # Return failed result rather than raising
            return self._create_error_result(raw_text, request_id, start_time, str(e))
    
    def _generate_with_retry(
        self,
        raw_text: str,
        analysis: AnalysisResult,
        examples: List[RetrievedExample],
        request_id: str
    ) -> RefinementResult:
        """
        Generate output with validation and retry logic.
        
        Implements intelligent retry with parameter adjustment.
        """
        last_validation = None
        
        for attempt in range(self.MAX_RETRIES + 1):
            logger.debug(f"[{request_id}] Generation attempt {attempt + 1}")
            
            # Select provider
            try:
                provider, provider_name = self.router.select_provider(
                    analysis, attempt=attempt
                )
            except NotImplementedError:
                # TODO: Remove this once providers are implemented
                logger.error("Providers not yet implemented")
                return self._create_error_result(
                    raw_text, request_id, time.time(), "Providers not implemented"
                )
            
            # Build prompt context
            context = PromptContext(
                raw_text=raw_text,
                content_type=analysis.content_type.value,
                audience=analysis.audience,
                preserved_facts=analysis.preserved_facts,
                dialect_mode=analysis.dialect_recommendation.value,
                examples=examples,
                attempt=attempt
            )
            
            # Build structured prompt
            prompt = self.prompt_builder.build(context)
            
            # Generate using real provider
            from providers.base_provider import GenerationRequest
            
            gen_request = GenerationRequest(
                system_prompt=prompt.system,
                user_prompt=prompt.user,
                json_schema=prompt.schema,
                temperature=0.3 if attempt == 0 else 0.1,  # Lower temp on retry
                max_tokens=800
            )
            
            gen_result = provider.generate_structured(gen_request)
            
            logger.info(
                f"[{request_id}] Provider {provider_name}: "
                f"success={gen_result.success}, latency={gen_result.latency_ms}ms"
            )
            
            if not gen_result.success:
                logger.warning(
                    f"[{request_id}] Provider {provider_name} failed: {gen_result.error}"
                )
                if attempt < self.MAX_RETRIES:
                    continue
                return self._create_error_result(
                    raw_text, request_id, time.time(), 
                    f"Provider failed: {gen_result.error}"
                )
            
            output = gen_result.output
            
            # Validate
            validation = self.validator.validate(
                output=output,
                input_facts=analysis.preserved_facts,
                original_text=raw_text
            )
            last_validation = validation
            
            if validation.is_valid:
                # Success - build result
                return RefinementResult(
                    success=True,
                    original_text=raw_text,
                    refined_text=output.get("refined_text", ""),
                    provider_used=provider_name,
                    fallback_used=attempt > 0,
                    content_type=analysis.content_type.value,
                    audience=analysis.audience,
                    dialect_applied=analysis.dialect_recommendation.value,
                    dialect_confidence=output.get("dialect_confidence", 0.0),
                    preserved_facts={
                        "extracted": [
                            {"type": f.fact_type, "value": f.value}
                            for f in analysis.preserved_facts
                        ]
                    },
                    validation_passed=True,
                    validation_warnings=validation.warnings,
                    fact_preservation_score=validation.scores.get("fact_preservation", 0.0),
                    request_id=request_id,
                    latency_ms=gen_result.latency_ms,  # Use actual provider latency
                    prompt_version=self.prompt_builder.get_version(),
                    retry_count=attempt,
                    warnings=gen_result.warnings + output.get("warnings", []),
                    tandaganon_terms_used=output.get("tandaganon_terms_used", [])
                )
            
            # Validation failed - log and retry
            logger.warning(
                f"[{request_id}] Validation failed (attempt {attempt + 1}): "
                f"{validation.reason}"
            )
            
            if attempt < self.MAX_RETRIES:
                # Adjust parameters for retry
                analysis, examples = self._adjust_for_retry(
                    analysis, examples, validation.reason
                )
        
        # Max retries exceeded - return with warnings
        return self._create_fallback_result(
            raw_text, analysis, request_id, last_validation, self.MAX_RETRIES
        )
    
    def _adjust_for_retry(
        self,
        analysis: AnalysisResult,
        examples: List[RetrievedExample],
        failure_reason: str
    ) -> Tuple[AnalysisResult, List[RetrievedExample]]:
        """
        Adjust parameters for retry based on failure reason.
        
        Implements downgrade strategies:
        - Dialect issues: downgrade to Cebuano
        - Fact issues: keep trying with same dialect but stricter constraints
        """
        if "dialect" in failure_reason.lower() or "tandaganon" in failure_reason.lower():
            # Downgrade dialect
            logger.debug(f"Downgrading dialect from {analysis.dialect_recommendation} to CEBUANO")
            analysis.dialect_recommendation = DialectMode.CEBUANO
            analysis.dialect_confidence = 0.0
        
        # Remove examples on retry to reduce noise
        if len(examples) > 0:
            examples = examples[:1]  # Keep only 1 example
        
        return analysis, examples
    
    def _create_fallback_result(
        self,
        raw_text: str,
        analysis: AnalysisResult,
        request_id: str,
        validation: Optional[ValidationResult],
        retry_count: int
    ) -> RefinementResult:
        """Create result when all retries exhausted - returns original with cleanup."""
        
        # Minimal cleanup of original (strip extra whitespace, fix obvious issues)
        cleaned_text = raw_text.strip()
        
        return RefinementResult(
            success=False,
            original_text=raw_text,
            refined_text=cleaned_text,  # Return cleaned original
            provider_used="none",
            fallback_used=False,
            content_type=analysis.content_type.value,
            audience=analysis.audience,
            dialect_applied="none",
            dialect_confidence=0.0,
            preserved_facts={},
            validation_passed=False,
            validation_warnings=validation.warnings if validation else [],
            fact_preservation_score=1.0,  # Original preserves all facts
            request_id=request_id,
            latency_ms=0,
            prompt_version=self.prompt_builder.get_version(),
            retry_count=retry_count,
            warnings=[f"Refinement failed after {retry_count} retries: {validation.reason if validation else 'unknown'}"],
            tandaganon_terms_used=[]
        )
    
    def _create_error_result(
        self,
        raw_text: str,
        request_id: str,
        start_time: float,
        error_message: str
    ) -> RefinementResult:
        """Create result for catastrophic error."""
        latency = int((time.time() - start_time) * 1000)
        
        return RefinementResult(
            success=False,
            original_text=raw_text,
            refined_text=raw_text,  # Return original
            provider_used="error",
            fallback_used=False,
            content_type="unknown",
            audience=["General Residents"],
            dialect_applied="none",
            dialect_confidence=0.0,
            preserved_facts={},
            validation_passed=False,
            validation_warnings=[error_message],
            fact_preservation_score=0.0,
            request_id=request_id,
            latency_ms=latency,
            prompt_version="error",
            retry_count=0,
            warnings=[f"System error: {error_message}"],
            tandaganon_terms_used=[]
        )
    
    # TODO: Remove when production testing complete
    def _mock_generate(self, prompt: StructuredPrompt) -> Dict[str, Any]:
        """Mock generation for development/testing."""
        return {
            "refined_text": "[MOCK] " + prompt.user[:50] + "...",
            "dialect_confidence": 0.5,
            "tandaganon_terms_used": [],
            "warnings": ["Mock generation"],
            "fact_check": {"all_present": True}
        }


# Convenience function for backward compatibility
def refine_with_fallback(raw_text: str) -> RefinementResult:
    """
    Convenience function for backward compatibility.
    
    Creates a new service instance and runs refinement.
    For production, prefer using RefinementService directly.
    """
    service = RefinementService()
    return service.refine(raw_text)
