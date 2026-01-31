# Alignment Fix – After Implementation (Admin + Mobile)

This document describes the **approve-flow fix** (permission error and auth switch) and what each side must do.

---

## What was fixed (Admin)

### 1. Permission error when approving a resident account

- **Cause:** After creating the new user with `createUserWithEmailAndPassword`, the app was signed in as the **new user**. The code then tried to **update/delete** the `awaitingApproval` doc **as that user**. Firestore rules only allowed officials to write `awaitingApproval`, so the resident got a permission error.
- **Fix:** Reorder operations so **only the admin** touches `awaitingApproval`:
  1. **As admin:** Update `awaitingApproval` with `status: 'approved'`, `reviewedBy`, `reviewedAt`.
  2. Sign out admin → create Auth user (app is now signed in as new user).
  3. Create `users/{uid}` (new user can write their own doc).
  4. **As new user:** Delete the `awaitingApproval` doc (allowed by rule: applicant can delete when `phoneNumber + '@linkod.com' == auth.email`).
  5. Sign out new user → navigate to Login.

### 2. Auth switching to the new account

- **Cause:** `createUserWithEmailAndPassword` signs the app in as the new user. That is expected; the admin session is lost for that flow.
- **Fix:** Added a **confirmation dialog** before Approve: *“This will create the user’s account and sign you out. You will need to log in again after approval. Continue?”* so the admin knows they must log in again.

### 3. Firestore rules

- **`firestore.rules`** was updated so that:
  - **`awaitingApproval`:** Officials can read/update/delete. **In addition**, any authenticated user can **delete** a document where `resource.data.phoneNumber + '@linkod.com' == request.auth.token.email` (so the **applicant** can delete their own request after their account is created).
  - **`users`:** User can read/write their own doc (`request.auth.uid == userId`); officials can read all (admin panel).
  - Other collections (announcements, drafts, posts, products, tasks, notifications, userAnnouncementReads) have rules aligned with the shared schema.

**Deploy rules:**  
`firebase deploy --only firestore:rules`  
so the admin and mobile apps use the same rules.

---

## Admin prompt (in-app)

- Before approving: **“This will create the user’s account and sign you out. You will need to log in again after approval. Continue?”** → Cancel / Approve.
- After approval: snackbar **“Account created. Please log in again.”** and redirect to Login.

---

## Mobile – What to keep in mind

1. **Users doc by UID**  
   Admin now creates `users/{uid}` on approve (Auth UID). Mobile should use **Auth UID** as the document ID and the same fields (`userId`, `fullName`, `phoneNumber`, `email`, `role`, `isApproved`, etc.).

2. **Login**  
   - Use `users.doc(FirebaseAuth.instance.currentUser?.uid)` (or equivalent) and enforce **`isApproved`** if you use it (e.g. block unapproved users).

3. **Sign-up request**  
   - When creating an `awaitingApproval` doc, set **`status: 'pending'`** so admin and rules align.

4. **Firestore rules**  
   - Deploy the same **`firestore.rules`** from this repo so that:
     - Residents can create/read/update their own `users/{uid}`.
     - Applicants can delete their own `awaitingApproval` doc after approval (rule: `phoneNumber + '@linkod.com' == request.auth.token.email`).
     - Officials/admins have the access defined in the rules (e.g. read all users, write awaitingApproval, announcements, etc.).

5. **No code change required on mobile for this fix**  
   The permission fix and auth behavior are handled in the **admin** flow and in **Firestore rules**. Mobile only needs to:
   - Use UID-based `users` and the same schema.
   - Rely on the deployed rules so that the new user (resident) can delete their own `awaitingApproval` doc when the admin app runs step 4 above.

---

## Summary

| Issue | Fix |
|-------|-----|
| Permission error on approve (resident) | Admin updates `awaitingApproval` first; new user only deletes their own doc (rule allows by email match). |
| Auth switches to new account | Expected; added confirmation dialog and “Please log in again” message. |
| Rules | Updated `firestore.rules`; deploy with `firebase deploy --only firestore:rules`. |
| Mobile | Use UID-based users, `status: 'pending'` on sign-up, deploy same rules; no extra code change for this fix. |
