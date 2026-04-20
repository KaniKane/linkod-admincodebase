"""
LINKod Admin Backend - Hosted AI Service Only.

Provides:
1. AI-based text refinement via the hosted LLM pipeline — refine only; no new info, no audience.
2. Rule-based audience recommendation — keyword rules from config; transparent, no AI.

Note: Push notification functionality has been moved to Firebase Cloud Functions.
This backend is AI-only. Do not add push notification code here.

Human-in-the-loop: Admin reviews and edits AI output and audience suggestions before publishing.
No auto-publish; Flutter app calls these endpoints then publishes via Firestore when admin confirms.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional
import os
import firebase_admin
from firebase_admin import credentials, firestore, messaging

from services.ai_refinement import refine_text, suggest_announcement_title
from services.audience_rules import recommend_audiences, DEFAULT_AUDIENCE

# Initialize Firebase Admin SDK
db = None


def _initialize_firebase() -> None:
    """Initialize Firebase Admin once and prepare Firestore client."""
    global db
    try:
        try:
            app = firebase_admin.get_app()
        except ValueError:
            # Prefer explicit service-account path; fallback to default credentials.
            local_cred_path = os.path.join(
                os.path.dirname(__file__),
                'linkod-db-firebase-adminsdk-fbsvc-db4270d732.json',
            )
            env_cred_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', '').strip()

            if env_cred_path and os.path.exists(env_cred_path):
                app = firebase_admin.initialize_app(
                    credentials.Certificate(env_cred_path),
                )
            elif os.path.exists(local_cred_path):
                app = firebase_admin.initialize_app(
                    credentials.Certificate(local_cred_path),
                )
            else:
                app = firebase_admin.initialize_app()

        db = firestore.client(app=app)
        print('Firebase initialized successfully')
    except Exception as e:
        db = None
        print(f'Warning: Could not initialize Firebase: {e}')


_initialize_firebase()

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
    suggested_title: Optional[str] = None


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


# --- Push Notification Models ---


class SendAccountApprovalRequest(BaseModel):
    """Request to send account approval push notification."""
    request_id: str = Field(..., description="Document ID in awaitingApproval collection")
    user_id: str = Field(..., description="User UID to send push to")
    title: str = Field(..., description="Push notification title")
    body: str = Field(..., description="Push notification body")


class SendAccountApprovalResponse(BaseModel):
    """Response from account approval push endpoint."""
    token_count: int = 0
    success_count: int = 0
    failure_count: int = 0
    error_counts: dict = Field(default_factory=dict)


# --- Endpoints (AI only) ---


@app.post("/refine", response_model=RefineResponse)
def post_refine(request: RefineRequest) -> RefineResponse:
    """
    Refine announcement text using the hosted LLM pipeline.
    AI only makes text formal, clear, concise. Does not add information or decide audience.
    Returns both original and refined text for human review.
    """
    raw = request.raw_text.strip()

    refined = refine_text(raw)
    if refined is None:
        raise HTTPException(
            status_code=503,
            detail="Text refinement failed. Check the backend AI provider and logs.",
        )

    suggested_title = suggest_announcement_title(refined)

    return RefineResponse(
        original_text=raw,
        refined_text=refined,
        suggested_title=suggested_title,
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


@app.post("/send-account-approval", response_model=SendAccountApprovalResponse)
def post_send_account_approval(request: SendAccountApprovalRequest) -> SendAccountApprovalResponse:
    """
    Send account approval push notification.
    Fetches FCM tokens from awaitingApproval doc, then sends push via Firebase Cloud Messaging.
    """
    if not db:
        raise HTTPException(status_code=503, detail="Firebase not initialized")
    
    tokens = []
    
    # Try to get tokens from awaitingApproval first
    if request.request_id.strip():
        try:
            doc = db.collection('awaitingApproval').document(request.request_id.strip()).get()
            if doc.exists:
                raw_tokens = doc.get('fcmTokens') or []
                if isinstance(raw_tokens, list):
                    tokens.extend([t for t in raw_tokens if isinstance(t, str) and t.strip()])
        except Exception as e:
            print(f"Error fetching tokens from awaitingApproval: {e}")
    
    # If no tokens in awaitingApproval, try users collection
    if not tokens and request.user_id.strip():
        try:
            user_ref = db.collection('users').document(request.user_id.strip())
            doc = user_ref.get()
            if doc.exists:
                raw_tokens = doc.get('fcmTokens') or []
                if isinstance(raw_tokens, list):
                    tokens.extend([t for t in raw_tokens if isinstance(t, str) and t.strip()])

                # Also support token storage in users/{uid}/devices documents.
                devices_snap = user_ref.collection('devices').stream()
                for device_doc in devices_snap:
                    token = (device_doc.to_dict() or {}).get('fcmToken')
                    if isinstance(token, str) and token.strip():
                        tokens.append(token.strip())
        except Exception as e:
            print(f"Error fetching tokens from users: {e}")
    
    # Remove duplicates and empty strings
    tokens = list(set(t.strip() for t in tokens if t and t.strip()))
    
    if not tokens:
        return SendAccountApprovalResponse(
            token_count=0,
            success_count=0,
            failure_count=0,
        )
    
    # Send push notifications
    success_count = 0
    failure_count = 0
    error_counts = {}
    
    for token in tokens:
        try:
            message = messaging.Message(
                token=token,
                notification=messaging.Notification(
                    title=request.title,
                    body=request.body,
                ),
                data={
                    'type': 'account_approved',
                    'userId': request.user_id,
                }
            )
            messaging.send(message)
            success_count += 1
        except Exception as e:
            failure_count += 1
            error_name = type(e).__name__
            error_counts[error_name] = error_counts.get(error_name, 0) + 1
            print(f"Error sending push to token: {e}")
    
    return SendAccountApprovalResponse(
        token_count=len(tokens),
        success_count=success_count,
        failure_count=failure_count,
        error_counts=error_counts,
    )


@app.get("/health")
def health() -> dict:
    """Simple health check for deployment."""
    return {"status": "ok", "service": "linkod-admin-ai-service"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
