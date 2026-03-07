# Push Notifications Implementation Plan (Revised)

**Context:** LINKod admin (Flutter Windows) + mobile (Flutter Android/iOS), Firebase (Auth, Firestore, Storage, FCM).

**Decisions:**
1. **Push only** – No in-app notification list. Do not write to a `notifications` collection for push; send FCM only.
2. **Backend on Cloud Functions** – The backend is currently run as a script (FastAPI at localhost). It will be deployed as **Firebase / Google Cloud Functions** so the admin app can call it without running a local server.

---

## 1. Current State (Brief)

- **Already sends push (via backend):** Announcement (on approve / post+push), account approval. Admin app calls FastAPI at `localhost:8000`; backend uses Firebase Admin SDK to get tokens and send FCM.
- **Today creates in-app notifications only (no push):** Like, comment, task chat message, product message. These write to Firestore `notifications` and update `unreadNotificationCount`; we will **stop** using that for push and instead send push from Cloud Functions triggered by the actual events.
- **No push today:** Product approved, task approved. Will be added via Cloud Functions (or HTTP function called by admin).

---

## 2. Target Behaviour: Push Only

| Event | Who | Push to | How |
|-------|-----|--------|-----|
| Like on post | Resident | Post owner | Firestore trigger: `posts/{postId}/likes` onCreate |
| Comment on post | Resident | Post owner | Firestore trigger: `posts/{postId}/comments` onCreate |
| Task chat message | Resident | Other participant | Firestore trigger: `tasks/{taskId}/chat_messages` onCreate |
| Product message | Resident | Seller | Firestore trigger: `products/{productId}/messages` onCreate |
| Announcement approved/posted | Admin | Audiences | HTTP function (existing logic) |
| Account approved | Admin | New user | HTTP function (existing logic) |
| Product approved | Admin | Seller | HTTP function (new) or Firestore trigger on product update |
| Task approved | Admin | Requester (and optionally volunteer) | HTTP function (new) or Firestore trigger on task update |

**In-app notification list:** Not implemented. No `notifications` collection needed for these flows; optional to remove or repurpose the existing notifications screen on mobile.

---

## 3. Backend: Run as Cloud Functions (Not Script)

Yes, the current backend **can** be deployed to Cloud Functions. Two practical options:

### Option A – FCM endpoints only as HTTP Cloud Functions (recommended first step)

- **Idea:** Deploy only the **push-related** endpoints as HTTP Cloud Functions. They are stateless, short-running, and only need Firestore + FCM.
- **Endpoints to deploy:**
  - `POST /send-announcement-push` (existing)
  - `POST /send-account-approval` (existing)
  - `POST /send-user-push` (new: for product/task approval push)
- **Refine and recommend-audiences:** Keep running **locally as a script** when needed (they use Ollama and 120s timeout; Cloud Functions have a 60s default and no Ollama). Admin app continues to call `localhost:8000` for refine/recommend only, and the **deployed function URL** for all push endpoints.
- **Flow:** Admin app uses two base URLs: e.g. `kBackendBaseUrl` (Cloud Function URL) for push, `kLocalRefineUrl` (localhost) for refine/recommend, or a single deployed URL if you later move refine to Cloud Run.

### Option B – Entire FastAPI app as one HTTP Cloud Function

- **Idea:** Wrap the full FastAPI app so one HTTP function serves all routes (refine, recommend, send-announcement-push, send-account-approval, send-user-push).
- **How:** Use **Google Cloud Functions (2nd gen)** or **Firebase HTTP functions** with a Python runtime. The function entry point receives the HTTP request and passes it to an ASGI adapter (e.g. Starlette/FastAPI’s ASGI app). Example pattern:
  - `main.py` exports an HTTP function that calls something like `requests.to_asgi(app)(request)` or a small wrapper that runs the FastAPI app for one request.
- **Limitations:** Refine has a 120s timeout; you’d need to set the function timeout to 120s (or 9 min max on 2nd gen). Ollama must be available (not typical in Cloud Functions; you’d need to call an external Ollama API or run it elsewhere). So for a backend that depends on a local Ollama, Option A is simpler.

**Recommendation:** Use **Option A**: deploy only the **FCM-related** backend as HTTP Cloud Functions. Keep refine/recommend-audiences as a local script (or later move refine to Cloud Run with a longer timeout if needed).

### Deploying the FCM backend as Cloud Functions

1. **Project layout (e.g. under `backend/` or a new `functions/` folder):**
   - Reuse existing `services/fcm_notifications.py` (and any shared code).
   - Add a **Cloud Functions entry point** that:
     - Listens for HTTP `POST` to paths like `/send-announcement-push`, `/send-account-approval`, `/send-user-push`.
     - Parses body, calls the same logic as current FastAPI (e.g. `send_announcement_push`, `send_account_approval_push`, `send_user_push`), returns JSON response.
   - **Firebase:** Use `firebase-functions` (Node) or **Google Cloud Functions (Python)** with `functions_framework`. For Python, you can have one function per endpoint or one function that dispatches by path.

2. **Python example (single HTTP function, path-based dispatch):**
   - Use **Firebase Functions (2nd gen)** with Python, or **Google Cloud Functions (2nd gen)**.
   - Entry point: one HTTP handler that checks `request.path` and `request.method`, then calls the appropriate handler (send_announcement_push, send_account_approval, send_user_push) and returns the same JSON shape as current FastAPI.
   - Dependencies: `firebase-admin`, `firebase-functions` (or `functions-framework`), same as current backend for FCM/Firestore.

3. **Credentials:** In Cloud Functions, use the **default service account** (no local JSON path). Grant that service account: Firestore read, FCM (messaging). No need for `GOOGLE_APPLICATION_CREDENTIALS` in production.

4. **Admin app:** Change `kAnnouncementBackendBaseUrl` (or introduce a separate `kPushBackendBaseUrl`) to the deployed HTTP function URL (e.g. `https://<region>-<project>.cloudfunctions.net/<functionName>` or Firebase HTTP URL). Use that for all push calls; keep local URL only for refine/recommend if you use Option A.

---

## 4. Push-Only Implementation (No In-App Notifications)

### 4.1 Event-driven push (Firestore triggers)

Trigger **only** on the source collections. Do **not** use a `notifications` collection for sending push.

| Trigger | Path | Logic |
|--------|------|--------|
| Like | `posts/{postId}/likes` onCreate | Read `posts/{postId}` → get `userId` (owner). Get FCM tokens for owner. Send FCM: title “Like”, body “X liked your post”, data `type=like`, `postId`. Skip if liker `userId` == owner. |
| Comment | `posts/{postId}/comments` onCreate | Read `posts/{postId}` → get `userId` (owner). Get tokens for owner. Send FCM: title “Comment”, body “X commented on your post”, data `type=comment`, `postId`, `commentId`. Skip if commenter == owner. |
| Task chat | `tasks/{taskId}/chat_messages` onCreate | Read `tasks/{taskId}` → get `requesterId`, `assignedTo`. Other participant = senderId == requesterId ? assignedTo : requesterId. Get tokens for that user. Send FCM: `type=task_chat_message`, `taskId`, body “X sent you a message in your errand chat”. |
| Product message | `products/{productId}/messages` onCreate | Read `products/{productId}` → get `sellerId`. If senderId == sellerId skip. Get tokens for sellerId. Send FCM: `type=product_message`, `productId`, body “X sent you a message about your product”. |

Implement as **one Cloud Function per trigger** (e.g. `onPostLikeCreated`, `onPostCommentCreated`, `onTaskMessageCreated`, `onProductMessageCreated`) or a **single function** with a shared path pattern (e.g. trigger on multiple paths). Use Firebase Admin SDK (Node or Python) to read Firestore and send FCM. Reuse the same token resolution as your current backend: `users/{uid}/devices` and `users/{uid}.fcmTokens`.

### 4.2 Admin-triggered push (HTTP Cloud Functions)

- **Announcement push / account approval:** Same as today; backend logic moved into HTTP Cloud Functions (see section 3).
- **New: send-user-push**
  - Add in backend (and in HTTP function): `get_tokens_for_user(user_id)`, `send_user_push(user_id, title, body, data)`.
  - New endpoint: `POST /send-user-push` with body `user_id`, `title`, `body`, `data` (e.g. `type`, `productId`, `taskId`).
  - **Admin app:** When approving a **product**, get `sellerId` from the product doc, call `POST /send-user-push` with title “Listing approved”, body “Your marketplace listing was approved”, `data: { type: "product_approved", productId: id }`.
  - **Admin app:** When approving a **task**, get `requesterId` (and optionally `assignedTo`), call `POST /send-user-push` for requester with `data: { type: "task_approved", taskId: id }` (and optionally for volunteer).

### 4.3 Mobile app changes (push only)

- **Stop writing** to the `notifications` collection for like, comment, task chat, product message (and optionally remove or simplify the in-app notifications screen).
- **Keep** FCM handling as-is: `PushNotificationHandler` and tap handling (post, comment, like, task, product, announcement, account_approved). Add handling for `product_approved` and `task_approved` so tap opens product/task screen.
- **Optional:** Remove or repurpose `NotificationsService`, unread badge from notifications collection, and any UI that lists “in-app notifications”. If you keep a screen, it could show “recent activity” from Firestore (e.g. reads from posts/tasks/products) without a dedicated notifications collection.

---

## 5. Summary Checklist

- [ ] **Backend (FCM part) on Cloud Functions:** Deploy HTTP function(s) for `send-announcement-push`, `send-account-approval`, and `send-user-push` (reuse existing logic; add `get_tokens_for_user` + `send_user_push`).
- [ ] **Admin app:** Point push base URL to the deployed Cloud Function URL; keep refine/recommend on local script (or separate URL) if using Option A.
- [ ] **Admin app:** On product approve → call `send-user-push` for seller with `type: product_approved`, `productId`.
- [ ] **Admin app:** On task approve → call `send-user-push` for requester (and optionally volunteer) with `type: task_approved`, `taskId`.
- [ ] **Cloud Function (Firestore):** `posts/{postId}/likes` onCreate → get post owner, send FCM (like).
- [ ] **Cloud Function (Firestore):** `posts/{postId}/comments` onCreate → get post owner, send FCM (comment).
- [ ] **Cloud Function (Firestore):** `tasks/{taskId}/chat_messages` onCreate → get other participant, send FCM (task_chat_message).
- [ ] **Cloud Function (Firestore):** `products/{productId}/messages` onCreate → get seller, send FCM (product_message).
- [ ] **Mobile:** Remove (or stop using) writes to `notifications` for like, comment, task chat, product message. Handle `product_approved` and `task_approved` in FCM tap/initial message. Optionally remove in-app notification list UI.

Result: **push only**, no in-app notification list; backend runs as **Cloud Functions** (at least for FCM); refine/recommend can stay as a local script.

---

## 6. Deployed API base URL (Option A)

After deploying: `firebase deploy --only functions`

- The HTTP API is exposed as a single function `api`. Its URL is:
  - `https://<region>-<project>.cloudfunctions.net/api`
- Use that as `kAnnouncementBackendBaseUrl` in the admin app for **push** (send-announcement-push, send-account-approval, send-user-push). Keep a separate base URL for refine/recommend if they still run locally.
- Red indicators (unread badge) stay: mobile continues to write to the `notifications` collection and update `unreadNotificationCount` for like, comment, task chat, product message; only the **sending** of push is done by Cloud Functions (event-driven on the source collections).
