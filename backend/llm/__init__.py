"""
LLM module for LINKod Admin backend.

Provides a unified interface for text generation through the hosted LLM
pipeline.

Usage:
    from llm import refine_text_via_gateway
    refined = refine_text_via_gateway(raw_text)
"""

from llm.pipeline import generate_announcement as refine_text_via_gateway
from llm.types import GenerationRequest, GenerationResult, ValidationResult

__all__ = [
    "GenerationRequest",
    "GenerationResult",
    "ValidationResult",
    "refine_text_via_gateway",
]
