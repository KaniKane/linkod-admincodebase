# LINKod Admin Backend (FastAPI)

Local REST API for the LINKod Admin system with **AI text refinement** via LLM Gateway (hosted LLM with local fallback), **rule-based audience recommendation**, and **admin-triggered push notifications (FCM)**.

## Quick Start

### 1. Install Dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure Environment

Copy the example and fill in your values:

```bash
cp env_example.txt .env
```

**For hosted mode (recommended for production):**
```env
AI_PROVIDER_MODE=auto
LLM_BASE_URL=https://api.groq.com/openai/v1
LLM_API_KEY=your_groq_api_key_here
LLM_MODEL_PRIMARY=llama-3.1-8b-instant
LLM_MODEL_FALLBACK=llama-3.3-70b-versatile
```

**For local-only mode (no internet required):**
```env
AI_PROVIDER_MODE=ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.2:3b
```

### 3. Run the Server

```bash
python main.py
```

Or with auto-reload for development:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Server starts on `http://localhost:8000`

Test it's running:
```powershell
Invoke-RestMethod -Uri http://localhost:8000/health -Method GET
```

## Provider Modes

Set `AI_PROVIDER_MODE` in your `.env`:

| Mode | Behavior | Use When |
|------|----------|----------|
| `auto` | Try hosted primary → hosted fallback → local Ollama | Default, production |
| `hosted` | Hosted only (no Ollama fallback) | Fast responses, no local GPU |
| `ollama` | Local Ollama only | No internet, testing, privacy |

## Switching to Local (Ollama) Fallback

If Groq API fails or you want to run completely offline:

### 1. Install Ollama

```powershell
winget install Ollama.Ollama
```

Or download from [ollama.ai](https://ollama.ai)

### 2. Pull the Model

```bash
ollama pull llama3.2:3b
```

### 3. Switch Mode

Edit `.env`:
```env
AI_PROVIDER_MODE=ollama
```

Or for automatic fallback (keeps trying hosted first):
```env
AI_PROVIDER_MODE=auto
```

### 4. Restart Backend

```bash
# Stop current server (Ctrl+C), then:
python main.py
```

### Verify Ollama is Working

```bash
# Check Ollama is running
ollama list

# Test model directly
ollama run llama3.2:3b "test"
```

## Fallback Chain (Auto Mode)

```
User Request
    ↓
Groq Primary (llama-3.1-8b-instant)
    ↓ (fails after timeout or error)
Groq Fallback (llama-3.3-70b-versatile)
    ↓ (fails)
Local Ollama (llama3.2:3b)
    ↓ (fails)
Return error to Flutter app
```

## Architecture

```
services/ai_refinement.py (API layer)
    ↓
llm/gateway.py (orchestrator - picks provider)
    ↓
├─ llm/client.py (hosted: Groq/OpenAI)
└─ llm/fallback.py (local: Ollama)
```

**New modular structure:**
- `llm/prompt_builder.py` - Prompt templates with anti-hallucination rules
- `llm/validators.py` - Output validation (signature preservation, fact checking)
- `config/ai_settings.py` - Environment configuration

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AI_PROVIDER_MODE` | No | `auto` | `auto`, `hosted`, or `ollama` |
| `LLM_BASE_URL` | For hosted | - | API endpoint (Groq: `https://api.groq.com/openai/v1`) |
| `LLM_API_KEY` | For hosted | - | Your Groq/OpenAI API key |
| `LLM_MODEL_PRIMARY` | For hosted | - | Primary model (e.g., `llama-3.1-8b-instant`) |
| `LLM_MODEL_FALLBACK` | No | - | Fallback model (e.g., `llama-3.3-70b-versatile`) |
| `AI_TIMEOUT_SECONDS` | No | `60` | Request timeout |
| `OLLAMA_BASE_URL` | No | `http://localhost:11434` | Ollama endpoint |
| `OLLAMA_MODEL` | No | `llama3.2:3b` | Local model name |
| `GOOGLE_APPLICATION_CREDENTIALS` | For push | - | Firebase service account JSON path |

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

### Port 8000 in use
```powershell
Get-Process python | Stop-Process -Force
```

### Groq API errors (400/401/429)
- Check `LLM_API_KEY` is valid and not expired
- Verify model names are current (models get deprecated)
- Check `LLM_BASE_URL` ends with `/v1`
- 429 = rate limit; wait a moment and retry

### Model deprecated error
Groq deprecates models periodically. Update `.env`:
```env
LLM_MODEL_PRIMARY=llama-3.1-8b-instant
LLM_MODEL_FALLBACK=llama-3.3-70b-versatile
```

### Ollama not responding
```powershell
# Check if Ollama is running
ollama list

# If empty, start Ollama
ollama serve

# Pull model if missing
ollama pull llama3.2:3b
```

### Timeout errors
Increase timeout in `.env`:
```env
AI_TIMEOUT_SECONDS=120
```

### AI refinement returns 503
This means all providers failed:
1. Check Groq API key is valid
2. Check Ollama is running (if using `auto` or `ollama` mode)
3. Check model is pulled: `ollama list`

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

## Security Notes

- **Never commit `.env`** with real API keys
- The repo has `.gitignore` configured to exclude `.env`
- Store production keys in environment variables, not files
- Rotate API keys if accidentally exposed
- For production deployment, use secret management (AWS Secrets Manager, etc.)

## Files

| File | Purpose |
|------|---------|
| `main.py` | FastAPI app entry point |
| `services/ai_refinement.py` | Public API (thin wrapper) |
| `services/audience_rules.py` | Rule-based audience recommendation |
| `llm/gateway.py` | Provider routing & fallback chain |
| `llm/client.py` | Hosted LLM (Groq/OpenAI) client |
| `llm/fallback.py` | Local Ollama client |
| `llm/prompt_builder.py` | Prompt templates with anti-hallucination rules |
| `llm/validators.py` | Output validation |
| `config/ai_settings.py` | Environment configuration |
| `env_example.txt` | Environment template |

## Flutter Integration

- Call `POST http://localhost:8000/refine` with the draft text; show `original_text` and `refined_text` for review.
- Optionally call `POST http://localhost:8000/recommend-audiences` with the refined text; show `audiences` and `matched_rules` as suggestions.
- Admin edits as needed and publishes via existing Firestore flow (no backend publish).
