"""
Modular prompt builder for structured refinement prompts.

Builds provider-agnostic structured prompts with:
- System prompt with core principles
- User prompt with facts, examples, glossary, and constraints
- JSON schema for structured output

Design principles:
- Factual preservation is paramount
- Conservative dialect application
- Clear constraints and negative patterns
- Provider-agnostic (works with OpenAI JSON mode and Ollama GBNF)
"""

import json
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional

# Version tracking for prompt iterations
PROMPT_VERSION = "v2.structured"


@dataclass
class PromptContext:
    """Context for building a prompt."""
    raw_text: str
    content_type: str
    audience: List[str]
    preserved_facts: List[Any]  # List of PreservedFact objects
    dialect_mode: str
    examples: List[Any]  # List of RetrievedExample objects
    attempt: int = 0


@dataclass
class StructuredPrompt:
    """Complete structured prompt for generation."""
    system: str
    user: str
    schema: Dict[str, Any]
    version: str = PROMPT_VERSION
    
    def to_openai_messages(self) -> List[Dict[str, str]]:
        """Convert to OpenAI message format."""
        return [
            {"role": "system", "content": self.system},
            {"role": "user", "content": self.user}
        ]
    
    def to_ollama_prompt(self) -> str:
        """Convert to Ollama-compatible single prompt."""
        # Ollama with small models works better with combined prompt
        return f"{self.system}\n\n{self.user}"


class GlossaryLoader:
    """Loads and filters Tandaganon glossary terms."""
    
    def __init__(self, lexicon_path: str = "config/tandaganon_lexicon.json"):
        self.lexicon_path = lexicon_path
        self._lexicon: Optional[Dict] = None
    
    def load(self) -> Dict[str, Any]:
        """Lazy load lexicon from JSON."""
        if self._lexicon is not None:
            return self._lexicon
        
        try:
            with open(self.lexicon_path, 'r', encoding='utf-8') as f:
                self._lexicon = json.load(f)
        except FileNotFoundError:
            # Return minimal lexicon if file not found
            self._lexicon = {"terms": {}, "phrases": {}}
        except json.JSONDecodeError as e:
            raise RuntimeError(f"Invalid JSON in {self.lexicon_path}: {e}")
        
        return self._lexicon
    
    def get_terms_for_context(
        self,
        dialect_mode: str,
        content_type: str,
        min_confidence: float = 0.7
    ) -> Dict[str, Any]:
        """
        Get relevant glossary terms for the context.
        
        Args:
            dialect_mode: One of 'cebuano', 'tandaganon_light', 'tandaganon_high'
            content_type: Content type for context matching
            min_confidence: Minimum confidence threshold
            
        Returns:
            Dictionary of term -> term_info
        """
        if dialect_mode == "cebuano":
            return {}  # No Tandaganon terms for Cebuano mode
        
        lexicon = self.load()
        terms = lexicon.get("terms", {})
        
        filtered = {}
        for term, info in terms.items():
            confidence = info.get("confidence", 0)
            if confidence < min_confidence:
                continue
            
            # Check context appropriateness
            contexts = info.get("contexts", [])
            if self._is_context_appropriate(content_type, contexts):
                filtered[term] = info
        
        return filtered
    
    def _is_context_appropriate(self, content_type: str, contexts: List[str]) -> bool:
        """Check if term is appropriate for the content type."""
        if not contexts or "general" in contexts:
            return True
        
        # Map content types to context categories
        content_mapping = {
            "emergency": ["formal", "urgent"],
            "event": ["formal", "invitation"],
            "health": ["formal", "health"],
            "4ps": ["formal", "social_service"],
            "ordinance": ["formal", "legal"],
            "reminder": ["formal"],
            "general": ["general"],
        }
        
        allowed = content_mapping.get(content_type, ["general"])
        return any(ctx in allowed for ctx in contexts)


class ConstraintBuilder:
    """Builds negative constraints and fact bindings."""
    
    # Patterns that should never appear in output
    FORBIDDEN_PATTERNS = [
        # Don't invent officials
        r'(?i)\b(hon\.?|honorable)\s+[A-Z][a-z]+\s+[A-Z]\.\s+[A-Z][a-z]+\b',
        # Don't add AI markers
        r'(?i)\b(created|generated)\s+(by|using)\s+(ai|artificial intelligence)\b',
        # Don't use marketing language
        r'(?i)\b(powerful|amazing|incredible|fantastic|awesome)\b',
        # Don't add explanations
        r'^(Explanation|Note|Here is|Below is|Refined text):',
    ]
    
    # Dialect-specific constraints
    DIALECT_CONSTRAINTS = {
        "cebuano": [
            "Use standard Cebuano (Bisaya) only",
            "Avoid Tandaganon-specific terms",
            "Prefer 'barangayanon' over 'kaigsuonan'",
        ],
        "tandaganon_light": [
            "Use light Tandaganon flavor",
            "Only high-confidence terms from glossary",
            "Fall back to Cebuano if unsure",
        ],
        "tandaganon_high": [
            "Use authentic Tandaganon where appropriate",
            "Only terms from glossary with confidence >= 0.8",
            "Maintain formal barangay tone",
        ],
    }
    
    def build_constraints(
        self,
        preserved_facts: List[Any],
        dialect_mode: str
    ) -> Dict[str, Any]:
        """
        Build constraint block for prompt.
        
        Returns:
            Dictionary with fact_bindings, dialect_rules, forbidden_patterns
        """
        # Fact bindings - immutable facts that must appear
        fact_bindings = []
        for fact in preserved_facts:
            fact_bindings.append({
                "type": fact.fact_type,
                "value": fact.value,
                "instruction": f"MUST include exactly: '{fact.value}'"
            })
        
        # Dialect rules
        dialect_rules = self.DIALECT_CONSTRAINTS.get(
            dialect_mode,
            self.DIALECT_CONSTRAINTS["cebuano"]
        )
        
        return {
            "fact_bindings": fact_bindings,
            "dialect_rules": dialect_rules,
            "forbidden_patterns": self.FORBIDDEN_PATTERNS[:3],  # Limit to top 3 for brevity
            "general_rules": [
                "DO NOT add new information",
                "DO NOT remove important details",
                "DO NOT change dates, times, or locations",
                "DO NOT invent missing details",
                "Keep sentences clear and easy to understand",
            ]
        }


class PromptBuilder:
    """
    Main prompt builder creating structured prompts for refinement.
    
    Usage:
        builder = PromptBuilder()
        context = PromptContext(...)
        prompt = builder.build(context)
        
        # For OpenAI
        messages = prompt.to_openai_messages()
        
        # For Ollama
        ollama_prompt = prompt.to_ollama_prompt()
    """
    
    # System prompt - stable across all requests
    SYSTEM_PROMPT = """You are a barangay announcement refinement assistant for LINKod, a Philippine local government platform.

YOUR CORE PRINCIPLES:
1. FACTUAL PRESERVATION IS PARAMOUNT. You must preserve all dates, times, locations, names, and numbers exactly as provided.
2. CLARITY OVER CREATIVITY. Make text clearer and more readable, not different. Do not rephrase for the sake of it.
3. CONSERVATIVE DIALECT USE. Only use Tandaganon terms when you are confident they are authentic and appropriate. When in doubt, use standard Cebuano.
4. NO INVENTION. Never add details not in the input. Never invent names, locations, events, or officials.
5. FORMAL RESPECTFUL TONE. Maintain barangay captain / official tone suitable for public announcements.

YOUR TASK:
Refine the provided draft announcement to make it:
- Clearer and easier to understand
- Grammatically correct in Cebuano/Bisaya
- Appropriately formal for official barangay communication
- Faithful to all facts from the original

OUTPUT FORMAT:
You must respond with a valid JSON object matching the provided schema. Output ONLY the JSON, no additional text."""
    
    # User prompt template with variable substitution
    USER_TEMPLATE = """## CONTENT TYPE
{content_type}

## TARGET AUDIENCE
{audience}

## PRESERVED FACTS (These MUST appear exactly in your output)
{facts_section}

## DIALECT MODE
{dialect_mode}
{dialect_rules}

## REFERENCE EXAMPLES
Study these examples for tone and structure. Do not copy them exactly.

{examples_section}

## TANDAGANON GLOSSARY (Use ONLY these terms if dialect mode permits)
{glossary_section}

## CONSTRAINTS
{constraints_section}

## RAW INPUT TEXT TO REFINE
```
{raw_text}
```

## YOUR TASK
Refine the RAW INPUT TEXT following the examples' tone and structure. Preserve all PRESERVED FACTS exactly. Follow the CONSTRAINTS strictly. Use Tandaganon terms from the glossary ONLY when dialect mode permits and you are confident.

## OUTPUT SCHEMA
Respond with valid JSON matching this exact structure:
```json
{output_schema}
```

Output ONLY the JSON object. No markdown code blocks, no explanations, no additional text."""
    
    # JSON schema for structured output
    OUTPUT_SCHEMA = {
        "type": "object",
        "required": ["refined_text", "fact_check"],
        "properties": {
            "refined_text": {
                "type": "string",
                "description": "The complete refined announcement text",
                "minLength": 10
            },
            "dialect_confidence": {
                "type": "number",
                "minimum": 0.0,
                "maximum": 1.0,
                "description": "Confidence in dialect authenticity (0-1)"
            },
            "tandaganon_terms_used": {
                "type": "array",
                "items": {"type": "string"},
                "description": "List of Tandaganon terms that were applied"
            },
            "warnings": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Any concerns or uncertainties about the output"
            },
            "fact_check": {
                "type": "object",
                "required": ["all_present"],
                "properties": {
                    "all_present": {
                        "type": "boolean",
                        "description": "True if all preserved facts appear in output"
                    }
                }
            }
        }
    }
    
    def __init__(
        self,
        glossary_loader: Optional[GlossaryLoader] = None,
        constraint_builder: Optional[ConstraintBuilder] = None
    ):
        """Initialize with optional component injection."""
        self.glossary_loader = glossary_loader or GlossaryLoader()
        self.constraint_builder = constraint_builder or ConstraintBuilder()
    
    def build(self, context: PromptContext) -> StructuredPrompt:
        """
        Build a complete structured prompt from context.
        
        Args:
            context: PromptContext with all necessary information
            
        Returns:
            StructuredPrompt ready for generation
        """
        # Load glossary for this context
        glossary = self.glossary_loader.get_terms_for_context(
            context.dialect_mode,
            context.content_type
        )
        
        # Build constraints
        constraints = self.constraint_builder.build_constraints(
            context.preserved_facts,
            context.dialect_mode
        )
        
        # Build sections
        facts_section = self._build_facts_section(context.preserved_facts)
        examples_section = self._build_examples_section(context.examples)
        glossary_section = self._build_glossary_section(glossary)
        constraints_section = self._build_constraints_section(constraints)
        dialect_rules = self._build_dialect_rules(constraints["dialect_rules"])
        
        # Build user prompt
        user_prompt = self.USER_TEMPLATE.format(
            content_type=context.content_type.upper(),
            audience=self._format_audience(context.audience),
            facts_section=facts_section,
            dialect_mode=context.dialect_mode.upper(),
            dialect_rules=dialect_rules,
            examples_section=examples_section,
            glossary_section=glossary_section,
            constraints_section=constraints_section,
            raw_text=context.raw_text.strip(),
            output_schema=json.dumps(self.OUTPUT_SCHEMA, indent=2)
        )
        
        return StructuredPrompt(
            system=self.SYSTEM_PROMPT,
            user=user_prompt,
            schema=self.OUTPUT_SCHEMA,
            version=PROMPT_VERSION
        )
    
    def get_version(self) -> str:
        """Return current prompt version for logging."""
        return PROMPT_VERSION
    
    def _build_facts_section(self, facts: List[Any]) -> str:
        """Build preserved facts section."""
        if not facts:
            return "No specific facts extracted. Preserve all original details."
        
        lines = []
        for fact in facts:
            lines.append(f"- [{fact.fact_type.upper()}] {fact.value}")
        return "\n".join(lines)
    
    def _build_examples_section(self, examples: List[Any]) -> str:
        """Build examples section."""
        if not examples:
            return "No relevant examples available. Use general barangay announcement style."
        
        sections = []
        for i, ex in enumerate(examples[:2], 1):  # Max 2 examples
            section = f"""EXAMPLE {i}:
Input: {ex.raw_input}
Output: {ex.approved_output}"""
            sections.append(section)
        
        return "\n\n".join(sections)
    
    def _build_glossary_section(self, glossary: Dict[str, Any]) -> str:
        """Build glossary section."""
        if not glossary:
            return "No Tandaganon terms recommended for this context. Use standard Cebuano."
        
        lines = []
        for term, info in sorted(glossary.items()):
            confidence = info.get("confidence", 0)
            meaning = info.get("meaning", "No definition")
            example = info.get("example_usage", "")
            
            line = f"- {term} (confidence: {confidence:.2f}): {meaning}"
            if example:
                line += f" | Example: '{example}'"
            lines.append(line)
        
        return "\n".join(lines)
    
    def _build_constraints_section(self, constraints: Dict[str, Any]) -> str:
        """Build constraints section."""
        lines = []
        
        # General rules
        lines.append("General Rules:")
        for rule in constraints["general_rules"]:
            lines.append(f"  - {rule}")
        
        # Fact bindings
        if constraints["fact_bindings"]:
            lines.append("\nFact Bindings (MUST preserve):")
            for binding in constraints["fact_bindings"]:
                lines.append(f"  - {binding['instruction']}")
        
        return "\n".join(lines)
    
    def _build_dialect_rules(self, rules: List[str]) -> str:
        """Build dialect rules subsection."""
        lines = ["Dialect Guidelines:"]
        for rule in rules:
            lines.append(f"  - {rule}")
        return "\n".join(lines)
    
    def _format_audience(self, audience: List[str]) -> str:
        """Format audience list for display."""
        if not audience:
            return "General Residents"
        return ", ".join(audience)


# Backward compatibility function
def build_refinement_prompt(raw_text: str) -> str:
    """
    Legacy function for backward compatibility.
    
    Creates a simple prompt without structured context.
    For new code, use PromptBuilder directly.
    """
    # Create minimal context
    context = PromptContext(
        raw_text=raw_text,
        content_type="general",
        audience=["General Residents"],
        preserved_facts=[],
        dialect_mode="cebuano",
        examples=[],
        attempt=0
    )
    
    builder = PromptBuilder()
    prompt = builder.build(context)
    
    # Return combined prompt for simple usage
    return prompt.to_ollama_prompt()


def get_prompt_version() -> str:
    """Return current prompt version for logging."""
    return PROMPT_VERSION
