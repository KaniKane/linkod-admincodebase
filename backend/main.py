"""
LINKod Admin Backend - Local REST API.

Provides:
1. AI-based text refinement (Ollama, llama3.2:3b) — refine only; no new info, no audience.
2. Rule-based audience recommendation — keyword rules from config; transparent, no AI.

Human-in-the-loop: Admin reviews and edits AI output and audience suggestions before publishing.
No auto-publish; Flutter app calls these endpoints then publishes via Firestore when admin confirms.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google.auth.exceptions import DefaultCredentialsError
from pydantic import BaseModel, Field
from typing import Optional

from services.ai_refinement import refine_text
from services.audience_rules import recommend_audiences, DEFAULT_AUDIENCE
from services.fcm_notifications import (
    FirebaseNotConfiguredError,
    get_approval_fcm_tokens_with_fallback,
    send_account_approval_push,
    send_announcement_push,
)

app = FastAPI(
    title="LINKod Admin API",
    description="AI text refinement and rule-based audience recommendation for announcements.",
    version="1.0.0",
)

# Allow Flutter (Windows) app to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Request/Response models ---


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


class SendAnnouncementPushRequest(BaseModel):
    """Admin-triggered push send (human-in-the-loop)."""

    announcement_id: str = Field(..., min_length=1, description="Firestore announcements/{id}")
    title: str = Field(..., min_length=1, description="Notification title")
    body: str = Field(..., min_length=1, description="Notification body")
    audiences: list[str] = Field(default_factory=list, description="Audience group names")
    requested_by_user_id: Optional[str] = Field(
        default=None, description="Optional admin user id for evaluation logs"
    )
    data: Optional[dict[str, str]] = Field(
        default=None, description="Optional extra FCM data payload (string:string)"
    )


class SendAnnouncementPushResponse(BaseModel):
    user_count: int
    token_count: int
    success_count: int
    failure_count: int
    error_counts: dict[str, int]


class SendAccountApprovalRequest(BaseModel):
    """Admin-triggered account approval push (single user)."""

    request_id: str = Field(..., min_length=1, description="awaitingApproval doc id to fetch fcmTokens from")
    user_id: str = Field(..., min_length=1, description="Firebase Auth UID of the approved user")
    title: str = Field(..., min_length=1, description="Notification title")
    body: str = Field(..., min_length=1, description="Notification body")


class SendAccountApprovalResponse(BaseModel):
    token_count: int
    success_count: int
    failure_count: int
    error_counts: dict[str, int]


# --- Endpoints ---


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


@app.post("/send-announcement-push", response_model=SendAnnouncementPushResponse)
def post_send_announcement_push(request: SendAnnouncementPushRequest) -> SendAnnouncementPushResponse:
    """
    Send a push notification for an approved/published announcement.

    - Human-in-the-loop: called by the Admin app only after admin confirmation.
    - Targeted: queries Firestore residents based on audience categories.
    - Sends ONLY to collected FCM tokens.
    - Logs results for evaluation (counts + error codes).
    """
    try:
        result = send_announcement_push(
            announcement_id=request.announcement_id,
            title=request.title,
            body=request.body,
            audiences=request.audiences,
            requested_by=request.requested_by_user_id,
            data=request.data,
        )
    except FirebaseNotConfiguredError as e:
        raise HTTPException(
            status_code=503,
            detail=str(e) + " See backend README for setup.",
        ) from e
    except DefaultCredentialsError as e:
        raise HTTPException(
            status_code=503,
            detail="Firebase credentials not found. Set FIREBASE_SERVICE_ACCOUNT_PATH or "
            "GOOGLE_APPLICATION_CREDENTIALS to your service account JSON path. See backend README.",
        ) from e

    return SendAnnouncementPushResponse(
        user_count=result.user_count,
        token_count=result.token_count,
        success_count=result.success_count,
        failure_count=result.failure_count,
        error_counts=result.error_counts,
    )


@app.post("/send-account-approval", response_model=SendAccountApprovalResponse)
def post_send_account_approval(request: SendAccountApprovalRequest) -> SendAccountApprovalResponse:
    """
    Send account-approved push to the approved user's devices.
    Fetches fcmTokens from awaitingApproval/{request_id}; sends only to those tokens.
    Does not crash if no tokens (returns 0 counts).
    """
    try:
        tokens = get_approval_fcm_tokens_with_fallback(
            request.request_id, request.user_id
        )
        result = send_account_approval_push(
            user_id=request.user_id,
            fcm_tokens=tokens,
            title=request.title,
            body=request.body,
        )
    except FirebaseNotConfiguredError as e:
        raise HTTPException(
            status_code=503,
            detail=str(e) + " See backend README for setup.",
        ) from e
    except DefaultCredentialsError as e:
        raise HTTPException(
            status_code=503,
            detail="Firebase credentials not found. Set FIREBASE_SERVICE_ACCOUNT_PATH or "
            "GOOGLE_APPLICATION_CREDENTIALS to your service account JSON path. See backend README.",
        ) from e

    return SendAccountApprovalResponse(
        token_count=result.token_count,
        success_count=result.success_count,
        failure_count=result.failure_count,
        error_counts=result.error_counts,
    )


@app.get("/health")
def health() -> dict:
    """Simple health check for deployment."""
    return {"status": "ok", "service": "linkod-admin-api"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
