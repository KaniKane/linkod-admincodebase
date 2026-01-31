# Firestore Database Schema — Shared (Admin + Mobile)

## Overview

This document is the **single source of truth** for Firestore structure for both the **LINKod Admin** panel and the **LINKod Mobile** app. All collections, field names, and data types are standardized so both systems share the same database.

**Sources merged:** `FIREBASE_DATABASE_STRUCTURE.md` (mobile/LinKod app) and the previous admin-only `FIRESTORE_SCHEMA.md`. Use this file for implementation on both sides.

---

## Naming Conventions

- **Collections:** camelCase, plural (e.g. `users`, `announcements`, `announcementDrafts`).
- **Fields:** camelCase (e.g. `fullName`, `phoneNumber`, `createdAt`).
- **Document IDs:**
  - **`users`:** **Firebase Auth UID** (so login and mobile both use `users/{uid}`).
  - **All other top-level collections:** auto-generated IDs (Firestore `.add()` or `.doc().set()`).

---

## Role Mapping (Admin ↔ Firestore)

| Admin panel display | Stored in Firestore |
|---------------------|----------------------|
| Admin               | `official`           |
| User / Resident     | `resident`           |
| Vendor              | `vendor`             |

- **Admin panel:** When reading, treat `role == 'official'` as “Admin”; when writing from admin UI, store `official` for admin and `resident` for user.
- **Mobile app:** Use `official` | `vendor` | `resident` directly.

---

## Collections (Shared)

### 1. `users`

**Path:** `users/{userId}`  
**Document ID:** Firebase Auth UID (same as `request.auth.uid`).

| Field            | Type       | Required | Description |
|------------------|------------|----------|-------------|
| `userId`         | string     | ✅       | Same as document ID (Auth UID). |
| `fullName`       | string     | ✅       | Full name. |
| `phoneNumber`    | string     | ✅       | Phone number (digits, no spaces). |
| `email`          | string     | ✅       | `{phoneNumber}@linkod.com`. |
| `role`           | string     | ✅       | `official` \| `vendor` \| `resident`. |
| `category`       | string     | Conditional | Comma-separated demographic categories (for residents). |
| `position`       | string     | Conditional | Barangay position (for officials only). |
| `profileImageUrl`| string     | Optional | Profile image URL (e.g. Storage). |
| `purok`          | number     | Optional | 1–5. |
| `createdAt`      | timestamp  | ✅       | `FieldValue.serverTimestamp()`. |
| `updatedAt`      | timestamp  | ✅       | `FieldValue.serverTimestamp()`. |
| `isActive`       | boolean    | Optional | Default `true`. |
| `isApproved`     | boolean    | Optional | Default `true` after approval. |

**Position values (officials):** Barangay Captain, Barangay Secretary, Barangay Treasurer, Barangay Councilor, SK Chairman, Barangay Health Worker, Barangay Tanod.

**Category values (residents):** Senior, Student, PWD, Youth, Farmer, Fisherman, Tricycle Driver, Small Business Owner, 4Ps, Tanod, Barangay Official, Parent.

**Indexes:** `role`, `isApproved`, `createdAt` (desc).

---

### 2. `awaitingApproval`

**Path:** `awaitingApproval/{requestId}`  
**Document ID:** Auto-generated.

| Field             | Type      | Required | Description |
|-------------------|-----------|----------|-------------|
| `requestId`       | string    | Optional | Same as document ID. |
| `userId`          | string    | Optional | Set after Auth account is created (e.g. on approval). |
| `fullName`        | string    | ✅       | Applicant full name. |
| `phoneNumber`     | string    | ✅       | Applicant phone. |
| `password`        | string    | ✅       | Temporary; remove after account creation. |
| `role`            | string    | ✅       | Requested: `admin` or `user` (map to `official`/`resident` when creating user). |
| `position`        | string    | Conditional | If role is admin. |
| `category`        | string    | Conditional | If role is user; comma-separated. |
| `createdAt`       | timestamp | ✅       | `FieldValue.serverTimestamp()`. |
| `status`          | string    | ✅       | `pending` \| `approved` \| `rejected`. |
| `reviewedBy`      | string    | Optional | Admin user ID who reviewed. |
| `reviewedAt`      | timestamp | Optional | When reviewed. |
| `rejectionReason` | string    | Optional | Shown to applicant if rejected. |

**Indexes:** `status`, `createdAt` (desc).

---

### 3. `announcements`

**Path:** `announcements/{announcementId}`  
**Document ID:** Auto-generated.

| Field             | Type           | Required | Description |
|-------------------|----------------|----------|-------------|
| `id`              | string         | Optional | Same as document ID. |
| `title`           | string         | ✅       | Title. |
| `content`         | string         | ✅       | Final body (AI-refined if used). |
| `originalContent` | string         | ✅       | Original before AI. |
| `aiRefinedContent`| string         | Optional | AI-refined version if used. |
| `audiences`       | array\<string\>| ✅       | Target demographics (same values as user `category`). |
| `postedBy`        | string         | Optional | Display name of poster. |
| `postedByUserId`  | string         | Optional | `users/{userId}`. |
| `status`          | string         | ✅       | `published` (drafts live in `announcementDrafts`). |
| `imageUrls`       | array\<string\>| Optional | Image URLs. |
| `createdAt`       | timestamp      | ✅       | `FieldValue.serverTimestamp()`. |
| `updatedAt`       | timestamp      | Optional | Last update. |
| `isActive`        | boolean        | Optional | Default `true`. |

**Indexes:** `postedByUserId`, `createdAt` (desc). For mobile: query by `audiences` (array-contains-any) and `createdAt`.

---

### 4. `announcementDrafts` (Admin only)

**Path:** `announcementDrafts/{draftId}`  
**Document ID:** Auto-generated.

| Field             | Type           | Required | Description |
|-------------------|----------------|----------|-------------|
| `title`           | string         | ✅       | Draft title. |
| `content`         | string         | ✅       | Current content. |
| `originalContent` | string         | ✅       | Original before edits. |
| `aiRefinedContent`| string         | Optional | AI-refined if used. |
| `audiences`       | array\<string\>| ✅       | Target demographics. |
| `createdAt`       | timestamp      | ✅       | `FieldValue.serverTimestamp()`. |
| `updatedAt`       | timestamp      | ✅       | `FieldValue.serverTimestamp()`. |

---

### 5. `posts`

**Path:** `posts/{postId}`  
**Description:** Community feed posts (mobile).

| Field          | Type           | Required | Description |
|----------------|----------------|----------|-------------|
| `id`           | string         | Optional | Same as document ID. |
| `userId`       | string         | ✅       | Reference to `users`. |
| `userName`     | string         | ✅       | Display name. |
| `title`        | string         | ✅       | Post title. |
| `content`      | string         | ✅       | Body. |
| `category`     | string         | ✅       | `health` \| `livelihood` \| `youthActivity`. |
| `createdAt`    | timestamp      | ✅       | |
| `imageUrls`    | array\<string\>| Optional | |
| `likesCount`   | number         | Optional | Default 0; keep in sync with `posts/{id}/likes`. |
| `commentsCount`| number         | Optional | Default 0; keep in sync with `posts/{id}/comments`. |
| `sharesCount`  | number         | Optional | Default 0. |
| `isAnnouncement`| boolean        | Optional | Default false. |
| `isActive`     | boolean        | Optional | Default true. |

**Subcollections:** `posts/{postId}/likes/{likeId}`, `posts/{postId}/comments/{commentId}` (see below).

---

### 6. `posts/{postId}/likes`

| Field     | Type     | Description |
|-----------|----------|-------------|
| `likeId`  | string   | Auto-generated. |
| `userId`  | string   | Reference to users. |
| `userName`| string   | |
| `likedAt` | timestamp| |

---

### 7. `posts/{postId}/comments`

| Field       | Type     | Description |
|-------------|----------|-------------|
| `commentId`| string   | Auto-generated. |
| `userId`   | string   | Reference to users. |
| `userName` | string   | |
| `content`   | string   | |
| `createdAt`| timestamp| |
| `updatedAt`| timestamp| |
| `isEdited` | boolean  | Default false. |
| `isDeleted`| boolean  | Default false. |

---

### 8. `products`

**Path:** `products/{productId}`  
**Description:** Marketplace (mobile).

| Field           | Type           | Required | Description |
|-----------------|----------------|----------|-------------|
| `id`            | string         | Optional | Same as document ID. |
| `sellerId`      | string         | ✅       | Reference to users. |
| `sellerName`    | string         | ✅       | |
| `title`         | string         | ✅       | |
| `description`   | string         | ✅       | |
| `price`         | number         | ✅       | |
| `imageUrls`     | array\<string\>| Optional | |
| `category`      | string         | Optional | Default `General`. |
| `createdAt`     | timestamp      | ✅       | |
| `updatedAt`     | timestamp      | Optional | |
| `isAvailable`   | boolean        | Optional | Default true. |
| `location`      | string         | Optional | |
| `contactNumber` | string         | Optional | |
| `messagesCount` | number         | Optional | Default 0; sync with subcollection. |

**Subcollection:** `products/{productId}/messages/{messageId}`.

---

### 9. `products/{productId}/messages`

| Field       | Type     | Description |
|-------------|----------|-------------|
| `messageId` | string   | Auto-generated. |
| `senderId`  | string   | Reference to users. |
| `senderName`| string   | |
| `message`   | string   | |
| `isSeller`  | boolean  | |
| `createdAt` | timestamp| |

---

### 10. `tasks`

**Path:** `tasks/{taskId}`  
**Description:** Errand/job requests (mobile).

| Field            | Type     | Required | Description |
|------------------|----------|----------|-------------|
| `id`             | string   | Optional | Same as document ID. |
| `title`          | string   | ✅       | |
| `description`    | string   | ✅       | |
| `requesterName`  | string   | ✅       | |
| `requesterId`    | string   | ✅       | Reference to users. |
| `assignedTo`     | string   | Optional | userId. |
| `assignedByName` | string   | Optional | |
| `createdAt`      | timestamp| ✅       | |
| `updatedAt`      | timestamp| Optional | |
| `dueDate`        | timestamp| Optional | |
| `status`         | string   | ✅       | `open` \| `ongoing` \| `completed`. |
| `priority`       | string   | Optional | `low` \| `medium` \| `high` \| `urgent`. |
| `contactNumber`  | string   | Optional | |
| `volunteersCount`| number   | Optional | Default 0; sync with subcollection. |
| `isActive`       | boolean  | Optional | Default true. |

**Subcollection:** `tasks/{taskId}/volunteers/{volunteerId}`.

---

### 11. `tasks/{taskId}/volunteers`

| Field         | Type     | Description |
|---------------|----------|-------------|
| `volunteerId` | string   | userId. |
| `volunteerName`| string  | |
| `volunteeredAt`| timestamp| |
| `status`      | string   | `pending` \| `accepted` \| `rejected`. |
| `acceptedAt`   | timestamp| Optional. |
| `acceptedBy`   | string   | requesterId, optional. |

---

### 12. `notifications`

**Path:** `notifications/{notificationId}`  
**Document ID:** Auto-generated.

| Field             | Type     | Required | Description |
|-------------------|----------|----------|-------------|
| `notificationId`  | string   | Optional | Same as document ID. |
| `userId`          | string   | ✅       | Target user. |
| `type`            | string   | ✅       | See list below. |
| `message`         | string   | ✅       | |
| `taskId`          | string   | Optional | Reference to tasks. |
| `productId`       | string   | Optional | Reference to products. |
| `postId`          | string   | Optional | Reference to posts. |
| `announcementId`   | string   | Optional | Reference to announcements. |
| `isRead`          | boolean  | Optional | Default false. |
| `createdAt`       | timestamp| ✅       | |

**Types:** `volunteerAccepted`, `errandJobVolunteers`, `productMessages`, `postComment`, `postLike`, `taskAssigned`, `announcement`.

---

### 13. `userAnnouncementReads`

**Path:** `userAnnouncementReads/{readId}`  
**Description:** Which user read which announcement (for “mark as read”).

| Field            | Type     | Required | Description |
|------------------|----------|----------|-------------|
| `readId`         | string   | Optional | Auto-generated. |
| `userId`        | string   | ✅       | Reference to users. |
| `announcementId` | string   | ✅       | Reference to announcements. |
| `readAt`         | timestamp| ✅       | |

**Index:** Composite unique `(userId, announcementId)`; composite `(announcementId, readAt)`.

---

## Authentication

- **Email format:** `{phoneNumber}@linkod.com` for all users (admin and mobile).
- **Linking Auth to Firestore:** Use **document ID = Auth UID**. So `users/{uid}` where `uid = FirebaseAuth.currentUser?.uid`. Admin and mobile both use `users.doc(uid)` after login.
- **Approval flow:** On approve, create Firebase Auth account (email: `phone@linkod.com`, password from request), then create `users/{newUser.uid}` with fullName, phoneNumber, role (`official` or `resident`), etc. Do **not** use phone as document ID for `users`.

---

## Data Relationships (Summary)

1. **users** → posts (userId), products (sellerId), tasks (requesterId/assignedTo), notifications (userId).
2. **tasks** → task volunteers (subcollection).
3. **posts** → likes, comments (subcollections).
4. **products** → messages (subcollection).
5. **users** ↔ announcements read (userAnnouncementReads).

---

## Alignment Plan (Admin + Mobile)

### Admin panel changes

1. **`users` document ID**
   - **Current:** Some flows use `users.doc(phone)`.
   - **Target:** Use **Firebase Auth UID** as document ID: `users/{uid}`.
   - **Actions:**
     - On **approve:** Create Auth account first (email: `phone@linkod.com`, password from request), then create `users/{userCredential.user!.uid}` with fullName, phoneNumber, role (`official` for admin, `resident` for user), position/category, createdAt, updatedAt, isActive, isApproved.
     - **List users:** Keep `collection('users').get()`; use `doc.id` as the user’s UID everywhere (edit/delete use `users.doc(doc.id)`).
     - **Create user (direct):** Either create Auth account first and then `users/{uid}`, or document that “add user” goes through approval flow.

2. **Role storage**
   - Store in Firestore: `official` | `resident` | `vendor`.
   - In admin UI: show “Admin” when `role == 'official'`, “User” when `role == 'resident'`, “Vendor” when `role == 'vendor'`. When saving from admin, map admin → `official`, user → `resident`.

3. **`awaitingApproval`**
   - Add fields: `status` (`pending` | `approved` | `rejected`), `reviewedBy`, `reviewedAt`, `rejectionReason`.
   - On approve: set status to `approved`, set reviewedBy/reviewedAt, then create Auth + user doc, then delete or keep document per product decision.
   - On decline: set status to `rejected`, set rejectionReason and reviewedAt, or delete.

4. **`announcements`**
   - Add when publishing: `postedBy` (current admin display name), `postedByUserId` (current user UID).
   - Keep: title, content, originalContent, aiRefinedContent, audiences, status, createdAt; add updatedAt, isActive, imageUrls if needed for mobile.

5. **Login**
   - Already uses `users.doc(user.uid)`; no change once all user docs use UID as document ID.

### Mobile app changes

1. **`users`**
   - Use **Auth UID** as document ID: `users/{uid}`. Ensure sign-up/approval flow creates `users/{uid}` (same as admin approval flow).
   - Add fields if missing: email, updatedAt, isActive, isApproved; position for officials.

2. **`announcements`**
   - Query by `audiences` (array-contains-any with user’s categories) and order by `createdAt`.
   - Use `content` (not `description`) for body; support `originalContent`, `aiRefinedContent`, `postedBy`, `postedByUserId`, imageUrls, isActive.

3. **`awaitingApproval`**
   - When creating sign-up request, set `status: 'pending'`. Optionally read status/rejectionReason for “pending/approved/rejected” UX.

4. **Collections**
   - Use same collection and field names as this schema (posts, products, tasks, subcollections, notifications, userAnnouncementReads) so both systems stay in sync.

---

## Security Rules (Unified Reference)

See `firestore.rules` in the repo. Ensure rules allow:

- **users:** read/write own doc by `request.auth.uid == userId`; officials can read/write as needed for admin.
- **awaitingApproval:** create by authenticated user (for sign-up); read/update/delete by officials.
- **announcements:** read by authenticated (or public if desired); write by officials only.
- **announcementDrafts:** read/write by officials only.
- **posts, products, tasks:** per-mobile rules (owner/official) as in FIREBASE_DATABASE_STRUCTURE.md.
- **notifications:** read/update by owning userId.
- **userAnnouncementReads:** read/create by owning userId.

---

## Version History

- **v2.0** – Merged admin + mobile schema; users keyed by Auth UID; role enum official|vendor|resident; announcements and awaitingApproval aligned; alignment plan added.
- **v1.0** – Admin-only schema (users by phone, announcements, drafts, awaitingApproval).

---

**End of document. Use this file as the single source of truth for both Admin and Mobile.**
