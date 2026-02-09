"""
FCM push notification sending (Firebase Admin SDK).

Design goals:
- Human-in-the-loop: called explicitly by the Admin app after approval/publish.
- Targeted delivery: backend queries Firestore for matching users, then sends ONLY to their FCM tokens.
- Incremental & thesis-defensible: stores only FCM tokens (device identifiers) and minimal metadata in logs.
- OTP-friendly: tokens remain linked to Firebase Auth UID; OTP can be added later without redesign.

Required env setup (development/deployment are identical):
- Provide a Firebase service account for Admin SDK.
  Option A (recommended): set GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
  Option B: set FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json
"""

from __future__ import annotations

import logging
import os
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import firebase_admin
from firebase_admin import credentials, firestore, messaging
from google.cloud.firestore_v1.base_query import And, FieldFilter


DEFAULT_GENERAL_AUDIENCE = "General Residents"
MAX_TOKENS_PER_BATCH = 500  # FCM multicast limit


class FirebaseNotConfiguredError(Exception):
    """Raised when Firebase Admin credentials are not configured or invalid."""


def _init_firebase_admin() -> None:
    """Initialize Firebase Admin once (idempotent)."""
    if firebase_admin._apps:  # pylint: disable=protected-access
        return

    sa_path = (
        os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH") or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    )
    if not sa_path or not sa_path.strip():
        raise FirebaseNotConfiguredError(
            "Firebase service account not configured. Set FIREBASE_SERVICE_ACCOUNT_PATH or "
            "GOOGLE_APPLICATION_CREDENTIALS to the path of your service account JSON file."
        )
    sa_path = sa_path.strip()
    if not os.path.isfile(sa_path):
        raise FirebaseNotConfiguredError(
            f"Firebase service account file not found: {sa_path}"
        )
    cred = credentials.Certificate(sa_path)
    firebase_admin.initialize_app(cred)


def _firestore_client():
    _init_firebase_admin()
    return firestore.client()


@dataclass(frozen=True)
class SendResult:
    user_count: int
    token_count: int
    success_count: int
    failure_count: int
    error_counts: Dict[str, int]


@dataclass(frozen=True)
class ApprovalSendResult:
    """Result of sending account-approval push to a single user's tokens."""

    token_count: int
    success_count: int
    failure_count: int
    error_counts: Dict[str, int]


def _chunked(seq: List[str], size: int) -> Iterable[List[str]]:
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def _normalize_audiences(audiences: List[str]) -> List[str]:
    cleaned: List[str] = []
    seen: Set[str] = set()
    for a in audiences or []:
        s = (a or "").strip()
        if not s:
            continue
        if s not in seen:
            seen.add(s)
            cleaned.append(s)
    return cleaned


def _query_target_users(audiences: List[str]) -> List[firestore.DocumentSnapshot]:
    """
    Query Firestore users using existing audience attributes.
    Only residents whose categories match the selected demographics receive the push.
    - Empty audiences -> no one (do not send to all).
    - Only "General Residents" -> all approved/active residents.
    - Specific demographics (with or without "General Residents") -> only users whose
      categories array contains at least one of those demographics (case-insensitive).
    
    Note: Firestore queries are case-sensitive, so we fetch all matching residents and
    then filter in-memory for case-insensitive matching to ensure accurate targeting.
    """
    db = _firestore_client()
    base_filter = And([
        FieldFilter("role", "==", "resident"),
        FieldFilter("isApproved", "==", True),
        FieldFilter("isActive", "==", True),
    ])
    users = db.collection("users").where(filter=base_filter)

    audiences = _normalize_audiences(audiences)
    if not audiences:
        return []

    # Get specific audiences (excluding "General Residents")
    filter_audiences = [a for a in audiences if a != DEFAULT_GENERAL_AUDIENCE]
    
    # If only "General Residents" is selected, send to all residents
    if not filter_audiences:
        return list(users.stream())
    
    # Normalize filter audiences to lowercase for case-insensitive matching
    filter_audiences_lower = [a.lower().strip() for a in filter_audiences if a.strip()]
    if not filter_audiences_lower:
        # If all audiences were invalid after normalization, return empty
        return []
    
    # Fetch all residents and filter in-memory for case-insensitive matching
    # This is necessary because Firestore queries are case-sensitive
    all_residents = list(users.stream())
    matching_docs: Dict[str, firestore.DocumentSnapshot] = {}
    
    for doc in all_residents:
        data = doc.to_dict() or {}
        user_categories = data.get("categories") or []
        
        # Skip if categories is not a list
        if not isinstance(user_categories, list):
            continue
        
        # Normalize user categories to lowercase for comparison
        user_categories_lower = [
            str(cat).lower().strip() 
            for cat in user_categories 
            if cat and str(cat).strip()
        ]
        
        # Check if any user category (case-insensitive) matches any filter audience
        # Only include users whose categories match the specific audiences
        # (Even if "General Residents" is also selected, we only send to specific demographics)
        has_match = any(
            user_cat in filter_audiences_lower 
            for user_cat in user_categories_lower
        )
        
        if has_match:
            matching_docs[doc.id] = doc
    
    return list(matching_docs.values())


def _collect_tokens(
    user_docs: List[firestore.DocumentSnapshot],
) -> Tuple[List[str], Dict[str, Set[str]]]:
    """
    Collects FCM tokens from users. Supports both storage formats:
    - Desktop/Admin: users/{uid}.fcmTokens (array field)
    - Mobile: users/{uid}/devices/{tokenId} (subcollection)
    
    Returns:
    - tokens: unique token list
    - token_to_uids: token -> set(userIds) for cleanup (invalid token pruning)
    """
    tokens: List[str] = []
    seen: Set[str] = set()
    token_to_uids: Dict[str, Set[str]] = {}
    db = _firestore_client()

    for doc in user_docs:
        data = doc.to_dict() or {}
        uid = doc.id
        
        # Collect from fcmTokens array (desktop/admin app format)
        raw_tokens = data.get("fcmTokens") or []
        if isinstance(raw_tokens, list):
            for t in raw_tokens:
                if not isinstance(t, str):
                    continue
                token = t.strip()
                if not token:
                    continue
                token_to_uids.setdefault(token, set()).add(uid)
                if token not in seen:
                    seen.add(token)
                    tokens.append(token)
        
        # Collect from devices subcollection (mobile app format)
        try:
            devices_ref = db.collection("users").document(uid).collection("devices")
            # Use get() instead of stream() to ensure we get all documents
            devices_docs = devices_ref.get()
            device_count = 0
            for device_doc in devices_docs:
                if not device_doc.exists:
                    continue
                device_data = device_doc.to_dict() or {}
                token = device_data.get("fcmToken")
                if isinstance(token, str):
                    token = token.strip()
                    if token:
                        device_count += 1
                        token_to_uids.setdefault(token, set()).add(uid)
                        if token not in seen:
                            seen.add(token)
                            tokens.append(token)
            if device_count > 0:
                logging.info(f"Collected {device_count} token(s) from devices subcollection for user {uid}")
            elif len(devices_docs) == 0:
                # No devices found - this is normal if user hasn't logged in on mobile yet
                logging.debug(f"No devices found in subcollection for user {uid}")
        except Exception as e:
            # Log with warning level so it's visible - this shouldn't normally fail
            logging.warning(
                f"Error reading devices subcollection for user {uid}: {type(e).__name__}: {e}",
                exc_info=True
            )

    return tokens, token_to_uids


def _prune_invalid_tokens(token_to_uids: Dict[str, Set[str]], invalid_tokens: Set[str]) -> None:
    """
    Remove invalid/expired tokens from both storage formats:
    - Desktop/Admin: users/{uid}.fcmTokens (arrayRemove)
    - Mobile: users/{uid}/devices/{tokenId} (delete document)
    """
    if not invalid_tokens:
        return
    db = _firestore_client()
    batch = db.batch()
    op_count = 0

    for token in invalid_tokens:
        for uid in token_to_uids.get(token, set()):
            # Remove from fcmTokens array (desktop/admin format)
            ref = db.collection("users").document(uid)
            batch.update(ref, {"fcmTokens": firestore.ArrayRemove([token])})
            op_count += 1
            
            # Remove from devices subcollection (mobile format)
            # Mobile app uses: token.hashCode.abs().toRadixString(16)
            # Python equivalent: abs(hash(token)) converted to hex
            token_id = format(abs(hash(token)), 'x')  # Convert to hex (matches mobile's toRadixString(16))
            device_ref = ref.collection("devices").document(token_id)
            batch.delete(device_ref)
            op_count += 1
            
            if op_count >= 450:  # keep under typical batch limits comfortably
                batch.commit()
                batch = db.batch()
                op_count = 0

    if op_count:
        batch.commit()


def _normalize_token_list(raw: Any) -> List[str]:
    """Extract non-empty string tokens from a list (from Firestore)."""
    if not isinstance(raw, list):
        return []
    tokens: List[str] = []
    for t in raw:
        if isinstance(t, str):
            token = t.strip()
            if token:
                tokens.append(token)
    return tokens


def get_approval_fcm_tokens(request_id: str) -> List[str]:
    """
    Fetch fcmTokens from awaitingApproval/{request_id}.
    Returns empty list if doc missing or fcmTokens not set (do not crash).
    """
    if not request_id or not request_id.strip():
        return []
    db = _firestore_client()
    doc = db.collection("awaitingApproval").document(request_id.strip()).get()
    if not doc.exists:
        return []
    data = doc.to_dict() or {}
    raw = data.get("fcmTokens") or []
    return _normalize_token_list(raw)


def get_approval_fcm_tokens_with_fallback(request_id: str, user_id: str) -> List[str]:
    """
    Get FCM tokens for account-approval push.
    First tries awaitingApproval/{request_id}.fcmTokens (set by mobile when user applies).
    If none, falls back to users/{user_id}.fcmTokens (set by mobile after first login).
    Logs when no tokens found so admins see the cause in the terminal.
    """
    tokens: List[str] = []
    seen: Set[str] = set()
    db = _firestore_client()

    if request_id and request_id.strip():
        doc = db.collection("awaitingApproval").document(request_id.strip()).get()
        if doc.exists:
            data = doc.to_dict() or {}
            for t in _normalize_token_list(data.get("fcmTokens") or []):
                if t not in seen:
                    seen.add(t)
                    tokens.append(t)

    if not tokens and user_id and user_id.strip():
        user_doc = db.collection("users").document(user_id.strip()).get()
        if user_doc.exists:
            data = user_doc.to_dict() or {}
            for t in _normalize_token_list(data.get("fcmTokens") or []):
                if t not in seen:
                    seen.add(t)
                    tokens.append(t)

    if not tokens:
        logging.warning(
            "Account approval push: no FCM tokens for request_id=%s user_id=%s. "
            "To get push on approve: (1) Mobile app must write fcmTokens to awaitingApproval when user applies, "
            "or (2) user must have opened the app after approval so users/{uid}.fcmTokens is set.",
            request_id,
            user_id,
        )
    return tokens


def send_account_approval_push(
    *,
    user_id: str,
    fcm_tokens: List[str],
    title: str,
    body: str,
) -> ApprovalSendResult:
    """
    Send account-approved notification to a single user's devices (single-user, not group).
    Payload matches mobile handler: data.type = "account_approved", data.userId = user_id.
    """
    _init_firebase_admin()

    if not fcm_tokens:
        return ApprovalSendResult(
            token_count=0,
            success_count=0,
            failure_count=0,
            error_counts={},
        )

    base_data: Dict[str, str] = {
        "type": "account_approved",
        "userId": user_id,
    }
    total_success = 0
    total_failure = 0
    error_counter: Counter[str] = Counter()

    for token_batch in _chunked(fcm_tokens, MAX_TOKENS_PER_BATCH):
        message = messaging.MulticastMessage(
            tokens=token_batch,
            notification=messaging.Notification(title=title, body=body),
            data=base_data,
        )
        batch_response = messaging.send_each_for_multicast(message)
        total_success += batch_response.success_count
        total_failure += batch_response.failure_count
        for idx, resp in enumerate(batch_response.responses):
            if resp.success:
                continue
            exc = resp.exception
            code = type(exc).__name__ if exc is not None else "UnknownError"
            error_counter[code] += 1

    return ApprovalSendResult(
        token_count=len(fcm_tokens),
        success_count=total_success,
        failure_count=total_failure,
        error_counts=dict(error_counter),
    )


def _log_send(
    *,
    announcement_id: str,
    audiences: List[str],
    requested_by: Optional[str],
    result: SendResult,
) -> None:
    """Write a minimal send log for evaluation (no raw tokens stored)."""
    db = _firestore_client()
    db.collection("pushSendLogs").add(
        {
            "type": "announcement",
            "announcementId": announcement_id,
            "audiences": audiences,
            "requestedByUserId": requested_by,
            "userCount": result.user_count,
            "tokenCount": result.token_count,
            "successCount": result.success_count,
            "failureCount": result.failure_count,
            "errorCounts": result.error_counts,
            "createdAt": firestore.SERVER_TIMESTAMP,
            # For offline export/evaluation convenience:
            "createdAtIso": datetime.now(timezone.utc).isoformat(),
        }
    )


def send_announcement_push(
    *,
    announcement_id: str,
    title: str,
    body: str,
    audiences: List[str],
    requested_by: Optional[str] = None,
    data: Optional[Dict[str, str]] = None,
) -> SendResult:
    """
    Send an announcement notification to targeted users.

    - Queries Firestore for matching residents (case-insensitive demographic matching).
    - Collects FCM tokens from both `users/{uid}.fcmTokens` (desktop) and 
      `users/{uid}/devices/{tokenId}` (mobile).
    - Sends via FCM in chunks.
    - Prunes invalid tokens (best-effort).
    - Logs results (counts + error codes only).
    """
    _init_firebase_admin()

    audiences_norm = _normalize_audiences(audiences)
    user_docs = _query_target_users(audiences_norm)
    
    # Log for debugging
    logging.info(
        f"Announcement push: announcement_id={announcement_id}, "
        f"audiences={audiences_norm}, matched_users={len(user_docs)}"
    )
    
    tokens, token_to_uids = _collect_tokens(user_docs)
    
    # Log token collection for debugging
    logging.info(
        f"Announcement push: collected {len(tokens)} tokens from {len(user_docs)} users. "
        f"User IDs: {[doc.id for doc in user_docs[:5]]}"  # Log first 5 user IDs for debugging
    )
    
    # If no tokens found but users matched, log detailed info
    if len(tokens) == 0 and len(user_docs) > 0:
        logging.warning(
            f"Announcement push: {len(user_docs)} user(s) matched but 0 tokens collected. "
            f"Checking token storage for first user: {user_docs[0].id}"
        )
        # Check first user's token storage for debugging
        first_user = user_docs[0]
        first_user_data = first_user.to_dict() or {}
        fcm_tokens_array = first_user_data.get("fcmTokens", [])
        logging.warning(
            f"First user {first_user.id}: fcmTokens array has {len(fcm_tokens_array) if isinstance(fcm_tokens_array, list) else 0} token(s)"
        )
        # Try to check devices subcollection
        try:
            db = _firestore_client()
            devices_ref = db.collection("users").document(first_user.id).collection("devices")
            devices_docs = list(devices_ref.stream())
            logging.warning(f"First user {first_user.id}: devices subcollection has {len(devices_docs)} device(s)")
            for device_doc in devices_docs[:3]:  # Check first 3 devices
                device_data = device_doc.to_dict() or {}
                logging.warning(f"  Device {device_doc.id}: fcmToken={device_data.get('fcmToken', 'NOT FOUND')[:50]}...")
        except Exception as e:
            logging.warning(f"Could not check devices subcollection for user {first_user.id}: {type(e).__name__}: {e}")

    if not tokens:
        result = SendResult(
            user_count=len(user_docs),
            token_count=0,
            success_count=0,
            failure_count=0,
            error_counts={},
        )
        _log_send(
            announcement_id=announcement_id,
            audiences=audiences_norm,
            requested_by=requested_by,
            result=result,
        )
        return result

    base_data = {
        "type": "announcement",
        "announcementId": announcement_id,
    }
    if data:
        # FCM data must be string:string
        base_data.update({str(k): str(v) for k, v in data.items()})

    total_success = 0
    total_failure = 0
    error_counter: Counter[str] = Counter()
    invalid_tokens: Set[str] = set()

    for token_batch in _chunked(tokens, MAX_TOKENS_PER_BATCH):
        message = messaging.MulticastMessage(
            tokens=token_batch,
            notification=messaging.Notification(title=title, body=body),
            data=base_data,
        )

        # send_each_for_multicast returns a BatchResponse with per-token responses
        batch_response = messaging.send_each_for_multicast(message)
        total_success += batch_response.success_count
        total_failure += batch_response.failure_count

        for idx, resp in enumerate(batch_response.responses):
            if resp.success:
                continue
            token = token_batch[idx]
            exc = resp.exception
            code = type(exc).__name__ if exc is not None else "UnknownError"
            error_counter[code] += 1

            # Prune definitely-invalid tokens so we don't keep retrying forever.
            # Note: firebase_admin.messaging has UnregisteredError, SenderIdMismatchError,
            # QuotaExceededError, ThirdPartyAuthError; no InvalidArgumentError in Python SDK.
            if isinstance(
                exc,
                (
                    messaging.UnregisteredError,
                    messaging.SenderIdMismatchError,
                ),
            ):
                invalid_tokens.add(token)

    # Best-effort cleanup of invalid tokens.
    _prune_invalid_tokens(token_to_uids, invalid_tokens)

    result = SendResult(
        user_count=len(user_docs),
        token_count=len(tokens),
        success_count=total_success,
        failure_count=total_failure,
        error_counts=dict(error_counter),
    )
    _log_send(
        announcement_id=announcement_id,
        audiences=audiences_norm,
        requested_by=requested_by,
        result=result,
    )
    return result

