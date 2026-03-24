"""
LLM Gateway module for LINKod Admin backend.

Provides a unified interface for text generation with fallback support:
- Hosted LLM primary and fallback models
- Local Ollama fallback

Usage:
    from llm.gateway import refine_text_via_gateway
    refined = refine_text_via_gateway(raw_text)
"""

from llm.types import GenerationRequest, GenerationResult, ValidationResult
from llm.gateway import refine_text_via_gateway

__all__ = [
    "GenerationRequest",
    "GenerationResult",
    "ValidationResult",
    "refine_text_via_gateway",
]
