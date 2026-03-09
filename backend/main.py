"""
LINKod Admin Backend - Local AI Service Only.

Provides:
1. AI-based text refinement (Ollama, llama3.2:3b) — refine only; no new info, no audience.
2. Rule-based audience recommendation — keyword rules from config; transparent, no AI.

Note: Push notification functionality has been moved to Firebase Cloud Functions.
This backend is now AI-only. Do not add push notification code here.

Human-in-the-loop: Admin reviews and edits AI output and audience suggestions before publishing.
No auto-publish; Flutter app calls these endpoints then publishes via Firestore when admin confirms.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional

from services.ai_refinement import refine_text
from services.audience_rules import recommend_audiences, DEFAULT_AUDIENCE

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
    """Original and refined text. Admin can review and edit before publishing."""

    original_text: str
    refined_text: str


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
    Refine announcement text using local Ollama (llama3.2:3b).
    AI only makes text formal, clear, concise. Does not add information or decide audience.
    Returns both original and refined text for human review.
    """
    raw = request.raw_text.strip()
    if not raw:
        raise HTTPException(status_code=400, detail="raw_text cannot be empty")

    refined = refine_text(raw)
    if refined is None:
        raise HTTPException(
            status_code=503,
            detail="Text refinement failed. Check that Ollama is running and model llama3.2:3b is available.",
        )

    return RefineResponse(original_text=raw, refined_text=refined)


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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
