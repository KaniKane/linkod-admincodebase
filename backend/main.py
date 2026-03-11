"""
LINKod Admin Backend - AI Service with OpenAI + Ollama fallback.

Provides:
1. AI-based text refinement (OpenAI primary, Ollama fallback) - refine only; no new info, no audience.
2. Rule-based audience recommendation - keyword rules from config; transparent, no AI.

Provider switching is controlled exclusively through AI_PROVIDER env variable:
- AI_PROVIDER=ollama: Local Llama only (thesis defense/offline mode)
- AI_PROVIDER=openai: OpenAI only (deployment mode)
- AI_PROVIDER=auto: OpenAI first, Ollama fallback (recommended)

No code changes required for switching between demo and deployment.

Human-in-the-loop: Admin reviews and edits AI output before publishing.
No auto-publish; Flutter app calls these endpoints then publishes via Firestore.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional

from services.refinement_service import refine_with_fallback
from services.audience_rules import recommend_audiences, DEFAULT_AUDIENCE
from providers import get_provider_router
from config.settings import get_settings

app = FastAPI(
    title="LINKod Admin AI Service",
    description="AI text refinement and rule-based audience recommendation. "
                "Push notifications are handled by Firebase Cloud Functions.",
    version="1.1.0",
)

# Allow Flutter (Windows) app to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Request/Response models (AI only) ---


class RefineRequest(BaseModel):
    """Raw announcement text to refine. AI only clarifies; does not add info or choose audience."""

    raw_text: str = Field(..., min_length=1, description="Raw announcement text")


class RefineResponse(BaseModel):
    """Enhanced response with provider metadata and fallback information."""
    
    original_text: str
    refined_text: str
    provider_used: str = Field(
        ..., 
        description="Provider that generated the refinement (openai or ollama)"
    )
    fallback_used: bool = Field(
        default=False, 
        description="True if fallback provider was used"
    )
    warning: Optional[str] = Field(
        default=None, 
        description="User-friendly warning if fallback or issues occurred"
    )


class RecommendAudiencesRequest(BaseModel):
    """Text to run through rule-based audience recommendation (typically refined announcement)."""

    text: str = Field(..., min_length=1, description="Announcement text to match against rules")


class MatchedRule(BaseModel):
    """One rule that matched; for transparency and explainability."""

    keywords: list[str]
    audiences: list[str]


class RecommendAudiencesResponse(BaseModel):
    """Recommended audiences and which rules matched. Default 'General Residents' if no match."""

    audiences: list[str]
    matched_rules: list[MatchedRule] = Field(
        default_factory=list,
        description="Rules that matched (transparent, explainable)",
    )
    default_used: bool = Field(
        default=False,
        description="True if no rule matched and default_audience was returned",
    )


# --- Endpoints (AI only) ---


@app.post("/refine", response_model=RefineResponse)
def post_refine(request: RefineRequest) -> RefineResponse:
    """
    Refine announcement text using OpenAI (primary) with Ollama fallback.
    Provider selection controlled by AI_PROVIDER env variable.
    AI only makes text formal, clear, concise. Does not add information.
    Returns both original and refined text for human review.
    """
    raw = request.raw_text.strip()
    if not raw:
        raise HTTPException(status_code=400, detail="raw_text cannot be empty")
    
    try:
        result = refine_with_fallback(raw)
        
        # Combine all warnings into a single user-friendly message
        all_warnings = result.validation_warnings + result.warnings
        warning_msg = "; ".join(all_warnings) if all_warnings else None
        
        return RefineResponse(
            original_text=result.original_text,
            refined_text=result.refined_text,
            provider_used=result.provider_used,
            fallback_used=result.fallback_used,
            warning=warning_msg,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Text refinement failed: {str(e)}",
        )


@app.post("/recommend-audiences", response_model=RecommendAudiencesResponse)
def post_recommend_audiences(request: RecommendAudiencesRequest) -> RecommendAudiencesResponse:
    """
    Rule-based audience recommendation. No AI.
    Matches text against configurable keyword rules; returns corresponding audience groups.
    If no rule matches, returns default 'General Residents'.
    Matched rules are returned for transparency.
    """
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="text cannot be empty")

    audiences, matched_rules = recommend_audiences(text)

    return RecommendAudiencesResponse(
        audiences=audiences,
        matched_rules=[MatchedRule(keywords=r["keywords"], audiences=r["audiences"]) for r in matched_rules],
        default_used=audiences == [DEFAULT_AUDIENCE] and not matched_rules,
    )


@app.get("/health")
def health() -> dict:
    """Simple health check for deployment."""
    return {"status": "ok", "service": "linkod-admin-ai-service"}


@app.get("/health/ai")
def health_ai() -> dict:
    """
    Health check for AI providers.
    Lightweight checks - no full model calls.
    """
    settings = get_settings()
    router = get_provider_router()
    health = router.health_check()
    
    return {
        "status": "ok" if any(h.is_healthy for h in health.values()) else "degraded",
        "mode": settings.AI_PROVIDER,
        "openai_available": health["openai"].is_healthy,
        "ollama_available": health["ollama"].is_healthy,
        "fallback_enabled": settings.FALLBACK_TO_OLLAMA,
        "default_model": settings.OPENAI_MODEL if settings.AI_PROVIDER != "ollama" else settings.OLLAMA_MODEL,
        "openai_message": health["openai"].message,
        "ollama_message": health["ollama"].message,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
