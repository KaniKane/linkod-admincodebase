# LINKod Admin Backend (FastAPI)

Local REST API for the LINKod Admin system: **AI-based text refinement**, **rule-based audience recommendation**, and **admin-triggered push notifications (FCM)**.

## Architecture

- **AI logic** (Ollama, llama3.2:3b): isolated in `services/ai_refinement.py`. Only refines text; does not add information or decide audience.
- **Rule-based logic**: isolated in `services/audience_rules.py`. Keyword rules loaded from `config/audience_rules.json`; no AI.
- **Human-in-the-loop**: Endpoints return data only. The Flutter admin app shows refined text and suggested audiences; the admin reviews and edits before publishing. No auto-publish.

## Requirements

- Python 3.9+
- [Ollama](https://ollama.ai) installed and running locally
- Model pulled: `ollama pull llama3.2:3b` (suitable for ~8 GB RAM)

## Install

```bash
cd backend
pip install -r requirements.txt
```

## Run

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Or: `python main.py`

## Endpoints

### POST /refine

Refines raw announcement text using local LLaMA 3.2 3B.

- **Request:** `{ "raw_text": "Adonday libre check up sa sabado..." }`
- **Response:** `{ "original_text": "...", "refined_text": "..." }`
- **Validation:** Empty `raw_text` → 400. Ollama unreachable or empty response → 503.

### POST /recommend-audiences

Rule-based audience recommendation from text (typically the refined announcement).

- **Request:** `{ "text": "Refined announcement text..." }`
- **Response:** `{ "audiences": ["Senior", "PWD"], "matched_rules": [...], "default_used": false }`
- If no rule matches: `audiences` = `["General Residents"]`, `default_used` = true.
- **Rules:** Edit `config/audience_rules.json` to add/change keyword → audience mappings.

### GET /health

Health check: `{ "status": "ok", "service": "linkod-admin-api" }`

### POST /send-announcement-push

Send a **targeted** push notification for a published/approved announcement (human-in-the-loop).

- **Called by:** Flutter Admin app after the admin confirms sending.
- **Targeting:** Queries Firestore residents by `users.categories` (array) using `array-contains-any`.
- **Tokens:** Sends ONLY to tokens stored in `users/{uid}.fcmTokens`. Users without tokens are ignored.
- **Logging:** Writes a minimal result log to Firestore `pushSendLogs` (counts + error codes; no raw tokens).

**Request:**

```json
{
  "announcement_id": "abc123",
  "title": "Water Interruption",
  "body": "Water service will be interrupted tomorrow...",
  "audiences": ["General Residents", "Senior"],
  "requested_by_user_id": "adminUid123",
  "data": { "screen": "announcements" }
}
```

**Firebase Admin SDK setup**

Provide a Firebase service account JSON (do **not** commit it to git):

- Option A (recommended): set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json`
- Option B: set `FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json`

**How push targeting works**

A user (phone) receives the push only if **all** of the following are true:

1. **Role:** `users/{uid}.role` is `"resident"` (officials/vendors are not targeted).
2. **Status:** `users/{uid}.isApproved` is `true` and `users/{uid}.isActive` is `true`.
3. **Audience match:** The announcement’s `audiences` list overlaps with the user’s **`categories`** array in Firestore.  
   - If you select **"General Residents"** (or no specific audiences), **all** residents above are eligible.  
   - If you select specific audiences (e.g. Senior, PWD), only users whose `categories` array contains **at least one** of those values are eligible.
4. **FCM token:** `users/{uid}.fcmTokens` has at least one token.  
   - The **mobile app** must have logged in with that user and run FCM registration (on startup/login/token refresh) so the token is written to Firestore.  
   - If the user has never opened the mobile app after login, or notifications are disabled, `fcmTokens` may be empty and they will **not** get the push.

**Testing both ends (admin + mobile)**

1. **Admin app:** Create or edit a **resident** user in User Management. Set **Demographic category** (e.g. Senior, Student). Save — this writes both `category` and `categories` in Firestore.
2. **Mobile app:** Log in as that resident on a real device (or emulator with Google Play Services for FCM). Ensure the app has run at least once after login so `FcmTokenService` has registered the token (check Firestore `users/{that-uid}` and confirm `fcmTokens` has an entry).
3. **Admin app:** Compose an announcement, select audiences that include that resident’s category (e.g. **Senior**), click **Post Announcement**, then choose **Post and send push**.
4. **Backend:** Must be running with `GOOGLE_APPLICATION_CREDENTIALS` (or `FIREBASE_SERVICE_ACCOUNT_PATH`) set so it can read Firestore and send via FCM.
5. **Phone:** Should receive the notification. If you see "No recipients found (no valid tokens)" or success with 0 tokens, use the Admin app’s feedback (see below) to tell whether **no users matched** or **users matched but had no tokens**, then fix accordingly.

**Troubleshooting: "No recipients found (no valid tokens)"**

The backend returns `user_count` (residents that matched the targeting rules) and `token_count` (FCM tokens collected from those users). The Admin app uses these to show a more specific message:

| What you see | Meaning | What to check |
|--------------|---------|----------------|
| **No residents matched** (0 users) | The Firestore query found no users with `role == "resident"`, `isApproved == true`, `isActive == true`, and **audience match**. | 1. **Audience match:** The backend filters by `users/{uid}.categories` (array). If you selected specific audiences (e.g. Senior, PWD), each target user must have **at least one** of those values in their `categories` array. If User Management only set the old `category` (string) and not `categories` (array), the query returns 0 users. Ensure when saving a resident you write both `category` and `categories` (the Admin app does this when you set Demographic category).<br>2. **Case:** Firestore `array-contains-any` is case-sensitive; e.g. "Senior" ≠ "senior". Keep audience names consistent (e.g. as in `audience_rules.json`).<br>3. **Role/status:** User must be resident, approved, and active. |
| **No valid tokens** (users matched but 0 tokens) | Some residents matched, but none had any FCM token in `users/{uid}.fcmTokens`. | 1. **Mobile app:** The resident must have opened the **mobile** app at least once after login so `FcmTokenService` can write the token to Firestore.<br>2. **Firestore:** In Firebase Console → Firestore → `users` → pick that user’s doc → confirm `fcmTokens` is present and non-empty.<br>3. **Notifications:** On the device, app notification permission must be granted (otherwise the mobile app may not get a token). |

So: **announcement is posted** (Firestore write) is separate from **push sent** (backend sends to tokens). "No valid token" only refers to the push step: either no users matched the targeting, or matched users had no tokens.

## Troubleshooting

### Refine text times out (POST /refine)

- **Ollama not running:** Start Ollama (e.g. `ollama serve`) and ensure the model is pulled: `ollama pull llama3.2:3b`.
- **First run or slow hardware:** The first request or a busy machine can take 60–90+ seconds. The Admin app uses a 120s timeout; the backend allows 90s for Ollama. If it still times out, try shorter text or a faster machine.
- **Wrong URL:** Refine calls `http://localhost:11434` by default. If Ollama runs elsewhere, set `OLLAMA_BASE_URL` or change `OLLAMA_BASE_URL` in `services/ai_refinement.py`.

### No push after approving an account (POST /send-account-approval)

- **No FCM tokens:** The backend looks for tokens in (1) `awaitingApproval/{requestId}.fcmTokens` (written by the **mobile app when the user submits** their application), then (2) `users/{uid}.fcmTokens` (written when the user **opens the app after approval**). If neither has tokens, no push is sent. Check the backend terminal for a log: `Account approval push: no FCM tokens for request_id=...`.
- **Fix:** (1) **Firestore rules:** The creator of an `awaitingApproval` doc must be allowed to **update** it (to add `fcmTokens`). The repo rules allow update when `resource.data.requestedByUid == request.auth.uid`. So the mobile app must set **`requestedByUid`** when creating the doc (e.g. `FirebaseAuth.instance.currentUser?.uid`). (2) When the user submits sign-up, call `FcmTokenService.addTokenToAwaitingApprovalDocument(docRef)` so the device’s FCM token is written to that doc. Then when the admin approves, the backend will find the token and send the push.

## Configuring audience rules

Edit `config/audience_rules.json`. Each rule has:

- `keywords`: list of strings; if **any** keyword appears in the text (case-insensitive), the rule matches.
- `audiences`: list of audience group names to recommend when the rule matches.

Example:

```json
{
  "keywords": ["health", "checkup", "medical"],
  "audiences": ["Senior", "PWD", "Parent"]
}
```

No AI is used for audience recommendation; logic is transparent and explainable via `matched_rules` in the response.

## Flutter integration

- Call `POST http://localhost:8000/refine` with the draft text; show `original_text` and `refined_text` for review.
- Optionally call `POST http://localhost:8000/recommend-audiences` with the refined text; show `audiences` and `matched_rules` as suggestions.
- Admin edits as needed and publishes via existing Firestore flow (no backend publish).
