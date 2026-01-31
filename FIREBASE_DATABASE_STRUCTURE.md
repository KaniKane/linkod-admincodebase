# Firebase Database Structure - LINKod App (Mobile)

> **Shared schema:** The canonical Firestore structure for **both** the mobile app and the admin panel is now defined in **`FIRESTORE_SCHEMA.md`**. Use that file as the single source of truth for collection names, document IDs, and field definitions. This document is kept for mobile-side context and historical reference; any conflicts should be resolved in favor of `FIRESTORE_SCHEMA.md`.

This document provides a complete blueprint of all data structures needed for the LINKod app Firebase database setup. Use this as a reference for both the mobile app and admin panel implementation.

---

## Table of Contents
1. [Users Collection](#users-collection)
2. [Awaiting Approval Collection](#awaiting-approval-collection)
3. [Posts Collection](#posts-collection)
4. [Announcements Collection](#announcements-collection)
5. [Products Collection](#products-collection)
6. [Tasks Collection](#tasks-collection)
7. [Task Volunteers Subcollection](#task-volunteers-subcollection)
8. [Post Likes Subcollection](#post-likes-subcollection)
9. [Post Comments Subcollection](#post-comments-subcollection)
10. [Product Messages Subcollection](#product-messages-subcollection)
11. [Notifications Collection](#notifications-collection)
12. [User Announcement Reads Collection](#user-announcement-reads-collection)

---

## Users Collection

**Path:** `users/{userId}`

**Description:** Stores user profile information and authentication details.

**Fields:**
```json
{
  "userId": "string (Firebase Auth UID)",
  "fullName": "string",
  "phoneNumber": "string",
  "email": "string (format: phoneNumber@linkod.com)",
  "role": "string (enum: 'official' | 'vendor' | 'resident')",
  "category": "string (comma-separated demographic categories)",
  "profileImageUrl": "string (optional)",
  "purok": "number (1-5, optional)",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isActive": "boolean (default: true)",
  "isApproved": "boolean (default: false)"
}
```

**Demographic Categories:**
- Senior
- Student
- PWD
- Youth
- Farmer
- Fisherman
- Tricycle Driver
- Small Business Owner
- 4Ps
- Tattoo
- Barangay Official
- Parent

**Indexes:**
- `role` (ascending)
- `isApproved` (ascending)
- `createdAt` (descending)

---

## Awaiting Approval Collection

**Path:** `awaitingApproval/{requestId}`

**Description:** Stores user signup requests pending admin approval.

**Fields:**
```json
{
  "requestId": "string (auto-generated)",
  "userId": "string (Firebase Auth UID)",
  "fullName": "string",
  "phoneNumber": "string",
  "password": "string (temporary, remove after approval)",
  "role": "string (default: 'user')",
  "category": "string (comma-separated demographic categories)",
  "createdAt": "timestamp",
  "status": "string (enum: 'pending' | 'approved' | 'rejected')",
  "reviewedBy": "string (userId of admin, optional)",
  "reviewedAt": "timestamp (optional)",
  "rejectionReason": "string (optional)"
}
```

**Indexes:**
- `status` (ascending)
- `createdAt` (descending)

---

## Posts Collection

**Path:** `posts/{postId}`

**Description:** Stores community posts/announcements that appear in the home feed.

**Fields:**
```json
{
  "id": "string",
  "userId": "string (reference to users)",
  "userName": "string",
  "title": "string",
  "content": "string",
  "category": "string (enum: 'health' | 'livelihood' | 'youthActivity')",
  "createdAt": "timestamp",
  "imageUrls": "array<string>",
  "likesCount": "number (default: 0)",
  "commentsCount": "number (default: 0)",
  "sharesCount": "number (default: 0, optional)",
  "isAnnouncement": "boolean (default: false)",
  "isActive": "boolean (default: true)"
}
```

**Post Categories:**
- `health` - Health-related posts
- `livelihood` - Livelihood-related posts
- `youthActivity` - Youth activity posts

**Indexes:**
- `userId` (ascending)
- `category` (ascending)
- `createdAt` (descending)
- `isAnnouncement` (ascending), `createdAt` (descending) - composite

---

## Announcements Collection

**Path:** `announcements/{announcementId}`

**Description:** Dedicated collection for official announcements (can also be stored as posts with isAnnouncement=true).

**Fields:**
```json
{
  "id": "string",
  "title": "string",
  "description": "string",
  "postedBy": "string (userName or 'Barangay Official')",
  "postedByUserId": "string (reference to users)",
  "date": "timestamp",
  "category": "string (enum: 'Health' | 'Livelihood' | 'Youth Activity')",
  "unreadCount": "number (default: 0)",
  "imageUrls": "array<string> (optional)",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isActive": "boolean (default: true)"
}
```

**Indexes:**
- `postedByUserId` (ascending)
- `category` (ascending)
- `date` (descending)

---

## Products Collection

**Path:** `products/{productId}`

**Description:** Stores marketplace products for sale.

**Fields:**
```json
{
  "id": "string",
  "sellerId": "string (reference to users)",
  "sellerName": "string",
  "title": "string",
  "description": "string",
  "price": "number",
  "imageUrls": "array<string>",
  "category": "string (default: 'General')",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isAvailable": "boolean (default: true)",
  "location": "string",
  "contactNumber": "string",
  "messagesCount": "number (default: 0)"
}
```

**Indexes:**
- `sellerId` (ascending)
- `category` (ascending)
- `isAvailable` (ascending), `createdAt` (descending) - composite
- `createdAt` (descending)

---

## Tasks Collection

**Path:** `tasks/{taskId}`

**Description:** Stores errand/job requests (tasks) posted by users.

**Fields:**
```json
{
  "id": "string",
  "title": "string",
  "description": "string",
  "requesterName": "string",
  "requesterId": "string (reference to users)",
  "assignedTo": "string (userId, optional)",
  "assignedByName": "string (optional)",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "dueDate": "timestamp (optional)",
  "status": "string (enum: 'open' | 'ongoing' | 'completed')",
  "priority": "string (enum: 'low' | 'medium' | 'high' | 'urgent')",
  "contactNumber": "string (optional)",
  "volunteersCount": "number (default: 0)",
  "isActive": "boolean (default: true)"
}
```

**Task Status:**
- `open` - Task is open and accepting volunteers
- `ongoing` - Task has been assigned and is in progress
- `completed` - Task has been completed

**Task Priority:**
- `low` - Low priority
- `medium` - Medium priority (default)
- `high` - High priority
- `urgent` - Urgent priority

**Indexes:**
- `requesterId` (ascending)
- `assignedTo` (ascending)
- `status` (ascending), `createdAt` (descending) - composite
- `priority` (ascending), `createdAt` (descending) - composite
- `createdAt` (descending)

---

## Task Volunteers Subcollection

**Path:** `tasks/{taskId}/volunteers/{volunteerId}`

**Description:** Stores volunteers who have volunteered for a specific task.

**Fields:**
```json
{
  "volunteerId": "string (userId)",
  "volunteerName": "string",
  "volunteeredAt": "timestamp",
  "status": "string (enum: 'pending' | 'accepted' | 'rejected')",
  "acceptedAt": "timestamp (optional)",
  "acceptedBy": "string (requesterId, optional)"
}
```

**Indexes:**
- `volunteerId` (ascending)
- `status` (ascending), `volunteeredAt` (descending) - composite

---

## Post Likes Subcollection

**Path:** `posts/{postId}/likes/{likeId}`

**Description:** Stores individual likes on posts (for tracking who liked what).

**Fields:**
```json
{
  "likeId": "string (auto-generated)",
  "userId": "string (reference to users)",
  "userName": "string",
  "likedAt": "timestamp"
}
```

**Indexes:**
- `userId` (ascending)
- `likedAt` (descending)

**Note:** The `likesCount` in the post document should be kept in sync with the number of documents in this subcollection.

---

## Post Comments Subcollection

**Path:** `posts/{postId}/comments/{commentId}`

**Description:** Stores comments on posts.

**Fields:**
```json
{
  "commentId": "string (auto-generated)",
  "userId": "string (reference to users)",
  "userName": "string",
  "content": "string",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isEdited": "boolean (default: false)",
  "isDeleted": "boolean (default: false)"
}
```

**Indexes:**
- `userId` (ascending)
- `createdAt` (descending)

**Note:** The `commentsCount` in the post document should be kept in sync with the number of non-deleted documents in this subcollection.

---

## Product Messages Subcollection

**Path:** `products/{productId}/messages/{messageId}`

**Description:** Stores messages/comments on product listings.

**Fields:**
```json
{
  "messageId": "string (auto-generated)",
  "senderId": "string (reference to users)",
  "senderName": "string",
  "message": "string",
  "isSeller": "boolean",
  "createdAt": "timestamp"
}
```

**Indexes:**
- `senderId` (ascending)
- `createdAt` (descending)

**Note:** The `messagesCount` in the product document should be kept in sync with the number of documents in this subcollection.

---

## Notifications Collection

**Path:** `notifications/{notificationId}`

**Description:** Stores user notifications for various events.

**Fields:**
```json
{
  "notificationId": "string (auto-generated)",
  "userId": "string (target user's userId)",
  "type": "string (enum: 'volunteerAccepted' | 'errandJobVolunteers' | 'productMessages' | 'postComment' | 'postLike' | 'taskAssigned' | 'announcement')",
  "message": "string",
  "taskId": "string (optional, reference to tasks)",
  "productId": "string (optional, reference to products)",
  "postId": "string (optional, reference to posts)",
  "announcementId": "string (optional, reference to announcements)",
  "isRead": "boolean (default: false)",
  "createdAt": "timestamp"
}
```

**Notification Types:**
- `volunteerAccepted` - A volunteer was accepted for your task
- `errandJobVolunteers` - People volunteered for your errand/job post
- `productMessages` - People dropped messages on your product post
- `postComment` - Someone commented on your post
- `postLike` - Someone liked your post
- `taskAssigned` - You were assigned to a task
- `announcement` - New announcement posted

**Indexes:**
- `userId` (ascending), `isRead` (ascending), `createdAt` (descending) - composite
- `userId` (ascending), `createdAt` (descending) - composite

---

## User Announcement Reads Collection

**Path:** `userAnnouncementReads/{readId}`

**Description:** Tracks which users have read which announcements (for "Mark as read" functionality).

**Fields:**
```json
{
  "readId": "string (auto-generated)",
  "userId": "string (reference to users)",
  "announcementId": "string (reference to announcements or posts)",
  "readAt": "timestamp"
}
```

**Indexes:**
- `userId` (ascending), `announcementId` (ascending) - composite (unique)
- `announcementId` (ascending), `readAt` (descending) - composite

---

## Additional Collections (Optional/Recommended)

### Chat Messages Collection (if implementing real-time chat)

**Path:** `chats/{chatId}/messages/{messageId}`

**Fields:**
```json
{
  "messageId": "string (auto-generated)",
  "senderId": "string (reference to users)",
  "senderName": "string",
  "message": "string",
  "createdAt": "timestamp",
  "isRead": "boolean (default: false)"
}
```

### Reports Collection (for admin moderation)

**Path:** `reports/{reportId}`

**Fields:**
```json
{
  "reportId": "string (auto-generated)",
  "reportedBy": "string (userId)",
  "reportType": "string (enum: 'post' | 'product' | 'task' | 'user')",
  "reportedItemId": "string",
  "reason": "string",
  "status": "string (enum: 'pending' | 'reviewed' | 'resolved' | 'dismissed')",
  "createdAt": "timestamp",
  "reviewedBy": "string (admin userId, optional)",
  "reviewedAt": "timestamp (optional)"
}
```

---

## Security Rules Recommendations

### Firestore Security Rules Structure

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId;
    }
    
    // Posts collection
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        (resource.data.userId == request.auth.uid || 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'official');
      
      // Post likes subcollection
      match /likes/{likeId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow delete: if request.auth != null && resource.data.userId == request.auth.uid;
      }
      
      // Post comments subcollection
      match /comments/{commentId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow update, delete: if request.auth != null && resource.data.userId == request.auth.uid;
      }
    }
    
    // Products collection
    match /products/{productId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && resource.data.sellerId == request.auth.uid;
      
      // Product messages subcollection
      match /messages/{messageId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow update, delete: if request.auth != null && resource.data.senderId == request.auth.uid;
      }
    }
    
    // Tasks collection
    match /tasks/{taskId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null && 
        (resource.data.requesterId == request.auth.uid || 
         resource.data.assignedTo == request.auth.uid ||
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'official');
      allow delete: if request.auth != null && resource.data.requesterId == request.auth.uid;
      
      // Task volunteers subcollection
      match /volunteers/{volunteerId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null;
        allow update: if request.auth != null && 
          (resource.data.volunteerId == request.auth.uid ||
           get(/databases/$(database)/documents/tasks/$(taskId)).data.requesterId == request.auth.uid);
        allow delete: if request.auth != null && 
          (resource.data.volunteerId == request.auth.uid ||
           get(/databases/$(database)/documents/tasks/$(taskId)).data.requesterId == request.auth.uid);
      }
    }
    
    // Announcements collection
    match /announcements/{announcementId} {
      allow read: if request.auth != null;
      allow create, update, delete: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'official';
    }
    
    // Awaiting approval collection
    match /awaitingApproval/{requestId} {
      allow read: if request.auth != null && 
        (resource.data.userId == request.auth.uid ||
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'official');
      allow create: if request.auth != null && resource.data.userId == request.auth.uid;
      allow update, delete: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'official';
    }
    
    // Notifications collection
    match /notifications/{notificationId} {
      allow read: if request.auth != null && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null;
      allow update: if request.auth != null && resource.data.userId == request.auth.uid;
    }
    
    // User announcement reads collection
    match /userAnnouncementReads/{readId} {
      allow read: if request.auth != null && resource.data.userId == request.auth.uid;
      allow create: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }
}
```

---

## Data Relationships Summary

1. **Users** → **Posts** (one-to-many via `userId`)
2. **Users** → **Products** (one-to-many via `sellerId`)
3. **Users** → **Tasks** (one-to-many via `requesterId`)
4. **Tasks** → **Task Volunteers** (one-to-many subcollection)
5. **Posts** → **Post Likes** (one-to-many subcollection)
6. **Posts** → **Post Comments** (one-to-many subcollection)
7. **Products** → **Product Messages** (one-to-many subcollection)
8. **Users** → **Notifications** (one-to-many via `userId`)
9. **Users** → **Announcement Reads** (many-to-many via `userAnnouncementReads`)

---

## Important Notes

1. **Timestamps:** All timestamp fields should use Firestore's `Timestamp` type or ISO 8601 strings. Use `FieldValue.serverTimestamp()` for creation timestamps.

2. **Counters:** Keep aggregate counters (like `likesCount`, `commentsCount`) in sync with subcollection document counts. Consider using Cloud Functions for this.

3. **Image Storage:** Store image URLs in Firestore, but upload actual images to Firebase Storage with paths like:
   - `users/{userId}/profile.jpg`
   - `posts/{postId}/{imageName}.jpg`
   - `products/{productId}/{imageName}.jpg`

4. **User Roles:** 
   - `official` - Barangay officials (can create announcements, approve users)
   - `vendor` - Vendors (can sell products)
   - `resident` - Regular residents (can create posts, tasks, volunteer)

5. **Data Validation:** Implement client-side and server-side validation for all data inputs.

6. **Indexes:** Create all composite indexes mentioned above in Firebase Console before deploying.

7. **Admin Panel:** Use the same structure for admin panel queries. Admins (role: 'official') have elevated permissions.

---

## Sample Queries

### Get all posts by category
```dart
FirebaseFirestore.instance
  .collection('posts')
  .where('category', isEqualTo: 'health')
  .orderBy('createdAt', descending: true)
  .get();
```

### Get user's notifications
```dart
FirebaseFirestore.instance
  .collection('notifications')
  .where('userId', isEqualTo: currentUserId)
  .where('isRead', isEqualTo: false)
  .orderBy('createdAt', descending: true)
  .get();
```

### Get tasks with volunteers
```dart
FirebaseFirestore.instance
  .collection('tasks')
  .where('status', isEqualTo: 'open')
  .orderBy('createdAt', descending: true)
  .get();
```

### Get products by seller
```dart
FirebaseFirestore.instance
  .collection('products')
  .where('sellerId', isEqualTo: sellerId)
  .where('isAvailable', isEqualTo: true)
  .orderBy('createdAt', descending: true)
  .get();
```

---

## Version History

- **v1.0** - Initial structure based on LINKod app codebase analysis
- Created: 2025-01-XX
- **Merged** - Final shared structure (Admin + Mobile) is in **`FIRESTORE_SCHEMA.md`**. See that file for unified collections, document ID conventions (e.g. `users/{uid}`), role mapping (`official`|`vendor`|`resident`), and the alignment plan so both systems share the same database.

---

**End of Document**
