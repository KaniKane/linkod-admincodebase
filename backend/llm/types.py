"""
Type definitions for the LLM gateway module.

Provides dataclasses for generation requests, results, and validation results.
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class GenerationRequest:
    """Request for text generation from an LLM."""

    prompt: str
    temperature: float = 0.0


@dataclass
class GenerationResult:
    """Result of a text generation attempt."""

    success: bool
    text: Optional[str]
    provider: str
    model: Optional[str] = None
    error: Optional[str] = None
    latency_ms: Optional[int] = None


@dataclass
class ValidationResult:
    """Result of validating generated text."""

    ok: bool
    reason: Optional[str] = None
