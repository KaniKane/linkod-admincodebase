"""
Example retriever for few-shot prompt building.

Retrieves relevant examples from an example bank based on content type,
audience matching, and dialect level. Uses a hybrid scoring approach
combining keyword matching and metadata filtering.

TODO: In production, consider adding:
- Semantic similarity using sentence embeddings
- Vector database integration (e.g., Chroma, FAISS)
- Cache layer for frequent retrievals
"""

import json
import logging
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class RetrievedExample:
    """
    A retrieved example with metadata.
    
    Attributes:
        id: Unique identifier for the example
        raw_input: Original input text
        approved_output: Human-approved refined output
        content_type: Type of announcement (event, health, etc.)
        audience: Target audiences for this example
        dialect_level: Dialect intensity (cebuano, tandaganon_light, etc.)
        similarity_score: Retrieval match score (0-1)
    """
    id: str
    raw_input: str
    approved_output: str
    content_type: str
    audience: List[str]
    dialect_level: str
    similarity_score: float


class ExampleRetriever:
    """
    Retrieves relevant examples from an example bank.
    
    The example bank is expected to be a JSON Lines file where each line
    contains a complete example record. This allows for easy append-only
    updates and streaming reads.
    
    Example bank format (one JSON object per line):
    {
        "id": "ann-2024-001",
        "raw_input": "Miting ugma 3pm...",
        "approved_output": "Tinahod kong mga kaigsuonan...",
        "content_type": "event",
        "audience": ["General Residents"],
        "dialect_level": "tandaganon_light",
        "keywords": ["miting", "tournament"]
    }
    
    Usage:
        retriever = ExampleRetriever("data/example_bank.jsonl")
        examples = retriever.retrieve(
            content_type="event",
            audience=["Youth", "Parent"],
            dialect_mode="tandaganon_light",
            k=2
        )
    """
    
    def __init__(
        self,
        example_bank_path: str = "data/example_bank.jsonl",
        max_examples: int = 1000
    ):
        """
        Initialize the retriever.
        
        Args:
            example_bank_path: Path to JSONL example bank file
            max_examples: Maximum number of examples to keep in memory
        """
        self.example_bank_path = Path(example_bank_path)
        self.max_examples = max_examples
        self._examples: List[Dict[str, Any]] = []
        self._loaded = False
    
    def _load_examples(self) -> List[Dict[str, Any]]:
        """
        Lazy load examples from disk.
        
        Returns:
            List of example dictionaries
        """
        if self._loaded:
            return self._examples
        
        if not self.example_bank_path.exists():
            logger.warning(
                f"Example bank not found: {self.example_bank_path}. "
                "No few-shot examples will be available."
            )
            self._loaded = True
            return []
        
        examples = []
        try:
            with open(self.example_bank_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if not line:
                        continue
                    
                    try:
                        example = json.loads(line)
                        # Validate required fields
                        if self._validate_example(example):
                            examples.append(example)
                        else:
                            logger.debug(f"Skipping invalid example at line {line_num}")
                    except json.JSONDecodeError as e:
                        logger.warning(
                            f"Invalid JSON at line {line_num} in {self.example_bank_path}: {e}"
                        )
                    
                    # Stop at max_examples
                    if len(examples) >= self.max_examples:
                        logger.info(f"Loaded maximum {self.max_examples} examples")
                        break
            
            logger.info(
                f"Loaded {len(examples)} examples from {self.example_bank_path}"
            )
            
        except Exception as e:
            logger.error(f"Error loading example bank: {e}")
        
        self._examples = examples
        self._loaded = True
        return examples
    
    def _validate_example(self, example: Dict[str, Any]) -> bool:
        """
        Validate that an example has required fields.
        
        Args:
            example: Example dictionary to validate
            
        Returns:
            True if valid, False otherwise
        """
        required = ["id", "raw_input", "approved_output"]
        return all(field in example and example[field] for field in required)
    
    def reload(self) -> None:
        """Force reload of example bank from disk."""
        self._loaded = False
        self._examples = []
        self._load_examples()
    
    def retrieve(
        self,
        content_type: str,
        audience: List[str],
        dialect_mode: str = "cebuano",
        k: int = 2
    ) -> List[RetrievedExample]:
        """
        Retrieve k most relevant examples for the given context.
        
        Scoring algorithm:
        1. Content type match: +1.0 if exact match, +0.5 if partial
        2. Audience overlap: +0.3 per matching audience (max 0.9)
        3. Dialect match: +0.2 if exact, +0.1 if compatible
        4. Recency boost: +0.1 for examples from last 6 months
        
        Args:
            content_type: Target content type (event, health, etc.)
            audience: List of target audiences
            dialect_mode: Target dialect mode
            k: Number of examples to retrieve
            
        Returns:
            List of RetrievedExample objects, sorted by relevance
        """
        examples = self._load_examples()
        
        if not examples:
            logger.debug("No examples available in bank")
            return []
        
        # Score all examples
        scored = []
        for example in examples:
            score = self._calculate_score(
                example=example,
                target_content_type=content_type,
                target_audience=set(audience),
                target_dialect=dialect_mode
            )
            scored.append((example, score))
        
        # Sort by score descending
        scored.sort(key=lambda x: x[1], reverse=True)
        
        # Take top k
        top_k = scored[:k]
        
        # Convert to RetrievedExample objects
        results = []
        for example, score in top_k:
            if score > 0:  # Only return examples with some relevance
                results.append(RetrievedExample(
                    id=example.get("id", "unknown"),
                    raw_input=example["raw_input"],
                    approved_output=example["approved_output"],
                    content_type=example.get("content_type", "general"),
                    audience=example.get("audience", ["General Residents"]),
                    dialect_level=example.get("dialect_level", "cebuano"),
                    similarity_score=score
                ))
        
        logger.debug(
            f"Retrieved {len(results)} examples for {content_type}/"
            f"{','.join(audience)}/best score={top_k[0][1] if top_k else 0:.2f}"
        )
        
        return results
    
    def _calculate_score(
        self,
        example: Dict[str, Any],
        target_content_type: str,
        target_audience: set,
        target_dialect: str
    ) -> float:
        """
        Calculate relevance score for an example.
        
        Args:
            example: Example to score
            target_content_type: Desired content type
            target_audience: Set of desired audiences
            target_dialect: Desired dialect mode
            
        Returns:
            Relevance score (0-1)
        """
        score = 0.0
        
        # 1. Content type match (highest weight)
        example_type = example.get("content_type", "general")
        if example_type == target_content_type:
            score += 1.0
        elif target_content_type.startswith(example_type) or example_type.startswith(target_content_type):
            # Partial match (e.g., "health_checkup" matches "health")
            score += 0.5
        
        # 2. Audience overlap
        example_audience = set(example.get("audience", []))
        if example_audience and target_audience:
            overlap = len(example_audience & target_audience)
            max_audience = max(len(example_audience), len(target_audience))
            if max_audience > 0:
                audience_score = (overlap / max_audience) * 0.9
                score += audience_score
        
        # 3. Dialect compatibility
        example_dialect = example.get("dialect_level", "cebuano")
        
        # Dialect compatibility matrix
        if example_dialect == target_dialect:
            score += 0.2
        elif target_dialect == "cebuano":
            # Any dialect works for Cebuano mode (we'll just not use terms)
            score += 0.1
        elif target_dialect.startswith("tandaganon") and example_dialect.startswith("tandaganon"):
            # Both some form of Tandaganon
            score += 0.15
        
        # 4. Quality bonus (if available)
        quality = example.get("quality_score", 0)
        if isinstance(quality, (int, float)) and quality > 0:
            score += min(quality / 10, 0.1)  # Max 0.1 bonus for high quality
        
        return score
    
    def add_example(
        self,
        raw_input: str,
        approved_output: str,
        content_type: str,
        audience: List[str],
        dialect_level: str = "cebuano",
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Add a new example to the bank.
        
        Args:
            raw_input: Original input text
            approved_output: Human-approved refined output
            content_type: Type of announcement
            audience: List of target audiences
            dialect_level: Dialect level used
            metadata: Optional additional metadata
            
        Returns:
            ID of the added example
        """
        import uuid
        
        example_id = str(uuid.uuid4())[:8]
        
        example = {
            "id": example_id,
            "raw_input": raw_input,
            "approved_output": approved_output,
            "content_type": content_type,
            "audience": audience,
            "dialect_level": dialect_level,
            "created_at": self._get_timestamp(),
        }
        
        if metadata:
            example.update(metadata)
        
        # Append to file
        try:
            # Ensure directory exists
            self.example_bank_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(self.example_bank_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps(example, ensure_ascii=False) + '\n')
            
            # Add to in-memory cache
            self._examples.append(example)
            
            logger.info(f"Added example {example_id} to bank")
            return example_id
            
        except Exception as e:
            logger.error(f"Failed to add example: {e}")
            raise
    
    def _get_timestamp(self) -> str:
        """Get current ISO timestamp."""
        from datetime import datetime
        return datetime.now().isoformat()
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get statistics about the example bank.
        
        Returns:
            Dictionary with statistics
        """
        examples = self._load_examples()
        
        if not examples:
            return {"total": 0}
        
        # Count by content type
        content_types = {}
        dialect_levels = {}
        
        for ex in examples:
            ct = ex.get("content_type", "unknown")
            dl = ex.get("dialect_level", "unknown")
            
            content_types[ct] = content_types.get(ct, 0) + 1
            dialect_levels[dl] = dialect_levels.get(dl, 0) + 1
        
        return {
            "total": len(examples),
            "by_content_type": content_types,
            "by_dialect_level": dialect_levels,
            "file_path": str(self.example_bank_path),
        }


class SimpleExampleRetriever(ExampleRetriever):
    """
    Simplified retriever that returns static examples.
    
    Use this for testing or when no example bank is available.
    Falls back to a small set of built-in examples.
    """
    
    # Static fallback examples
    FALLBACK_EXAMPLES = [
        {
            "id": "static-001",
            "raw_input": "Miting ugma 3pm sa barangay hall bahin sa basketball.",
            "approved_output": "Tinahod kong mga kaigsuonan, gihulagway ko nga adunay miting karung umaabot Lunes alas 3:00 sa hapon sa Barangay Hall bahin sa pagpahigayon og basketball tournament.",
            "content_type": "event",
            "audience": ["Youth", "General Residents"],
            "dialect_level": "tandaganon_light",
        },
        {
            "id": "static-002",
            "raw_input": "Libreng checkup sa health center sa Miyerkules.",
            "approved_output": "Tinahod kong mga barangayanon, adunay libreng medical checkup sa atong Health Center karung umaabot nga Miyerkules. Gipahinungod kini sa tanang mga senior citizen ug mga bata.",
            "content_type": "health",
            "audience": ["Senior", "Parent", "PWD"],
            "dialect_level": "cebuano",
        },
        {
            "id": "static-003",
            "raw_input": "Ayaw kalimot sa pagdala og requirements para sa 4Ps ayuda.",
            "approved_output": "Pahinumdom alang sa tanang benepesyaryo sa 4Ps: Palihug dad-a ang inyong mga requirements sa pagdawat sa inyong ayuda. Kinahanglan ang valid ID ug 4Ps ID.",
            "content_type": "4ps",
            "audience": ["4Ps"],
            "dialect_level": "cebuano",
        },
    ]
    
    def _load_examples(self) -> List[Dict[str, Any]]:
        """Load examples, falling back to static if file not found."""
        examples = super()._load_examples()
        
        if not examples:
            logger.info("Using fallback static examples")
            return self.FALLBACK_EXAMPLES
        
        return examples


# Convenience function for simple usage
def get_examples(
    content_type: str,
    audience: List[str],
    dialect_mode: str = "cebuano",
    k: int = 2,
    example_bank_path: Optional[str] = None
) -> List[RetrievedExample]:
    """
    Convenience function to retrieve examples.
    
    Args:
        content_type: Target content type
        audience: List of target audiences  
        dialect_mode: Target dialect mode
        k: Number of examples to retrieve
        example_bank_path: Optional custom path to example bank
        
    Returns:
        List of RetrievedExample objects
    """
    path = example_bank_path or "data/example_bank.jsonl"
    retriever = SimpleExampleRetriever(path)
    return retriever.retrieve(content_type, audience, dialect_mode, k)
