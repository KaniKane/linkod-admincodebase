const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const bodyParser = require('body-parser');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();
const MAX_TOKENS_PER_BATCH = 500;

// --- FCM helpers (match backend logic) ---

function normalizeTokenList(arr) {
  if (!Array.isArray(arr)) return [];
  return arr.filter((t) => typeof t === 'string' && t.trim()).map((t) => t.trim());
}

async function getTokensForUser(uid) {
  if (!uid || !uid.trim()) return [];
  const userRef = db.collection('users').doc(uid.trim());
  const userDoc = await userRef.get();
  if (!userDoc.exists) return [];
  const tokens = [];
  const seen = new Set();
  const data = userDoc.data() || {};
  for (const t of normalizeTokenList(data.fcmTokens || [])) {
    if (!seen.has(t)) {
      seen.add(t);
      tokens.push(t);
    }
  }
  const devicesSnap = await userRef.collection('devices').get();
  devicesSnap.docs.forEach((d) => {
    const token = d.data().fcmToken;
    if (typeof token === 'string' && token.trim() && !seen.has(token.trim())) {
      seen.add(token.trim());
      tokens.push(token.trim());
    }
  });
  return tokens;
}

async function getApprovalTokens(requestId, userId) {
  const tokens = [];
  const seen = new Set();
  if (requestId && requestId.trim()) {
    const approvalDoc = await db.collection('awaitingApproval').doc(requestId.trim()).get();
    if (approvalDoc.exists) {
      const raw = (approvalDoc.data() || {}).fcmTokens || [];
      normalizeTokenList(raw).forEach((t) => {
        if (!seen.has(t)) {
          seen.add(t);
          tokens.push(t);
        }
      });
    }
  }
  if (tokens.length === 0 && userId && userId.trim()) {
    const fromUser = await getTokensForUser(userId.trim());
    fromUser.forEach((t) => {
      if (!seen.has(t)) {
        seen.add(t);
        tokens.push(t);
      }
    });
  }
  return tokens;
}

async function collectTokensFromUserDocs(userDocs) {
  const tokens = [];
  const seen = new Set();
  for (const doc of userDocs) {
    const data = doc.data() || {};
    const uid = doc.id;
    normalizeTokenList(data.fcmTokens || []).forEach((t) => {
      if (!seen.has(t)) {
        seen.add(t);
        tokens.push(t);
      }
    });
    const devicesSnap = await db.collection('users').doc(uid).collection('devices').get();
    devicesSnap.docs.forEach((d) => {
      const token = d.data().fcmToken;
      if (typeof token === 'string' && token.trim() && !seen.has(token.trim())) {
        seen.add(token.trim());
        tokens.push(token.trim());
      }
    });
  }
  return tokens;
}

async function queryTargetUsers(audiences) {
  const normalized = [...new Set((audiences || []).map((a) => (a || '').trim()).filter(Boolean))];
  if (normalized.length === 0) return [];
  const GENERAL = 'General Residents';
  const filterAudiences = normalized.filter((a) => a !== GENERAL);
  const snapshot = await db.collection('users')
    .where('role', '==', 'resident')
    .where('isApproved', '==', true)
    .where('isActive', '==', true)
    .get();
  if (filterAudiences.length === 0) return snapshot.docs;
  const filterLower = filterAudiences.map((a) => a.toLowerCase());
  return snapshot.docs.filter((doc) => {
    const categories = doc.data().categories || [];
    const userLower = categories.map((c) => String(c).toLowerCase().trim()).filter(Boolean);
    return userLower.some((uc) => filterLower.includes(uc));
  });
}

async function sendMulticast(tokens, title, body, data) {
  let success = 0;
  let failure = 0;
  const dataStr = {};
  Object.keys(data || {}).forEach((k) => {
    dataStr[k] = String(data[k]);
  });
  for (let i = 0; i < tokens.length; i += MAX_TOKENS_PER_BATCH) {
    const batch = tokens.slice(i, i + MAX_TOKENS_PER_BATCH);
    const result = await messaging.sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      data: dataStr,
    });
    success += result.successCount;
    failure += result.failureCount;
  }
  return { successCount: success, failureCount: failure };
}

// --- HTTP API (FCM endpoints for admin app; Option A) ---
// Note: Cloud Functions strips the function name (\"api\") from the path,
// so when the admin app calls https://...cloudfunctions.net/api/send-user-push
// the Express app sees req.path === \"/send-user-push\".

const app = express();
app.use(bodyParser.json());

app.post('/send-user-push', async (req, res) => {
  try {
    const { user_id: userId, title, body, data } = req.body || {};
    if (!userId || !title || !body) {
      return res.status(400).json({ error: 'user_id, title, body required' });
    }
    const tokens = await getTokensForUser(userId);
    if (tokens.length === 0) {
      return res.status(200).json({
        token_count: 0,
        success_count: 0,
        failure_count: 0,
        error_counts: {},
      });
    }
    const payload = { type: (data && data.type) || 'notification', userId, ...(data || {}) };
    const { successCount, failureCount } = await sendMulticast(tokens, title, body, payload);
    return res.status(200).json({
      token_count: tokens.length,
      success_count: successCount,
      failure_count: failureCount,
      error_counts: {},
    });
  } catch (e) {
    console.error('send-user-push error:', e);
    return res.status(503).json({ error: String(e.message || e) });
  }
});

app.post('/send-account-approval', async (req, res) => {
  try {
    const { request_id: requestId, user_id: userId, title, body } = req.body || {};
    if (!requestId || !userId || !title || !body) {
      return res.status(400).json({ error: 'request_id, user_id, title, body required' });
    }
    const tokens = await getApprovalTokens(requestId, userId);
    if (tokens.length === 0) {
      return res.status(200).json({
        token_count: 0,
        success_count: 0,
        failure_count: 0,
        error_counts: {},
      });
    }
    const { successCount, failureCount } = await sendMulticast(tokens, title, body, {
      type: 'account_approved',
      userId,
    });
    return res.status(200).json({
      token_count: tokens.length,
      success_count: successCount,
      failure_count: failureCount,
      error_counts: {},
    });
  } catch (e) {
    console.error('send-account-approval error:', e);
    return res.status(503).json({ error: String(e.message || e) });
  }
});

app.post('/send-announcement-push', async (req, res) => {
  try {
    const { announcement_id: announcementId, title, body, audiences = [], requested_by_user_id: requestedBy } = req.body || {};
    if (!announcementId || !title || !body) {
      return res.status(400).json({ error: 'announcement_id, title, body required' });
    }
    const userDocs = await queryTargetUsers(audiences);
    const tokens = await collectTokensFromUserDocs(userDocs);
    if (tokens.length === 0) {
      return res.status(200).json({
        user_count: userDocs.length,
        token_count: 0,
        success_count: 0,
        failure_count: 0,
        error_counts: {},
      });
    }
    const data = { type: 'announcement', announcementId };
    if (requestedBy) data.requestedByUserId = requestedBy;
    const { successCount, failureCount } = await sendMulticast(tokens, title, body, data);
    return res.status(200).json({
      user_count: userDocs.length,
      token_count: tokens.length,
      success_count: successCount,
      failure_count: failureCount,
      error_counts: {},
    });
  } catch (e) {
    console.error('send-announcement-push error:', e);
    return res.status(503).json({ error: String(e.message || e) });
  }
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'linkod-admin-api' });
});

exports.api = functions.https.onRequest(app);

// --- Firestore triggers: send push on like, comment, task chat, product message (red indicators stay in app) ---

async function sendPushToUser(userId, title, body, data) {
  if (!userId) return;
  const tokens = await getTokensForUser(userId);
  if (tokens.length === 0) return;
  await sendMulticast(tokens, title, body, data);
}

exports.onPostLikeCreated = functions.firestore
  .document('posts/{postId}/likes/{likeId}')
  .onCreate(async (snap, context) => {
    const { postId } = context.params;
    const likeData = snap.data() || {};
    const likerId = likeData.userId;
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;
    const ownerId = (postSnap.data() || {}).userId;
    if (!ownerId || ownerId === likerId) return;
    const userName = likeData.userName || 'Someone';
    await sendPushToUser(ownerId, 'Like', `${userName} liked your post`, {
      type: 'like',
      postId,
    });
  });

exports.onPostCommentCreated = functions.firestore
  .document('posts/{postId}/comments/{commentId}')
  .onCreate(async (snap, context) => {
    const { postId, commentId } = context.params;
    const commentData = snap.data() || {};
    const commenterId = commentData.userId;
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;
    const ownerId = (postSnap.data() || {}).userId;
    if (!ownerId || ownerId === commenterId) return;
    const userName = commentData.userName || 'Someone';
    await sendPushToUser(ownerId, 'Comment', `${userName} commented on your post`, {
      type: 'comment',
      postId,
      commentId,
    });
  });

exports.onTaskMessageCreated = functions.firestore
  .document('tasks/{taskId}/chat_messages/{messageId}')
  .onCreate(async (snap, context) => {
    const { taskId } = context.params;
    const msgData = snap.data() || {};
    const senderId = msgData.senderId;
    const taskSnap = await db.collection('tasks').doc(taskId).get();
    if (!taskSnap.exists) return;
    const task = taskSnap.data() || {};
    const requesterId = task.requesterId;
    const assignedTo = task.assignedTo;
    const receiverId = senderId === requesterId ? assignedTo : requesterId;
    if (!receiverId || receiverId === senderId) return;
    const senderName = msgData.senderName || 'Someone';
    await sendPushToUser(receiverId, 'Errand message', `${senderName} sent you a message in your errand chat`, {
      type: 'task_chat_message',
      taskId,
    });
  });

exports.onProductMessageCreated = functions.firestore
  .document('products/{productId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const { productId } = context.params;
    const msgData = snap.data() || {};
    const senderId = msgData.senderId;
    const productSnap = await db.collection('products').doc(productId).get();
    if (!productSnap.exists) return;
    const sellerId = (productSnap.data() || {}).sellerId;
    if (!sellerId || sellerId === senderId) return;
    const senderName = msgData.senderName || 'Someone';
    await sendPushToUser(sellerId, 'Product message', `${senderName} sent you a message about your product`, {
      type: 'product_message',
      productId,
    });
  });

exports.onProductReplyCreated = functions.firestore
  .document('products/{productId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const { productId, messageId } = context.params;
    const msgData = snap.data() || {};
    const senderId = msgData.senderId;
    const parentId = msgData.parentId;
    // Only process replies (messages with parentId)
    if (!parentId) return;
    // Fetch parent message to get its sender
    const parentSnap = await db.collection('products').doc(productId).collection('messages').doc(parentId).get();
    if (!parentSnap.exists) return;
    const parentSenderId = (parentSnap.data() || {}).senderId;
    // Don't notify if parent sender is the same as reply sender
    if (!parentSenderId || parentSenderId === senderId) return;
    const senderName = msgData.senderName || 'Someone';
    await sendPushToUser(parentSenderId, 'Reply', `${senderName} replied to your message`, {
      type: 'reply',
      productId,
      parentMessageId: parentId,
      messageId,
    });
  });

// --- Firestore triggers: task volunteer and volunteer acceptance (Phase 1 fix) ---

exports.onTaskVolunteerCreated = functions.firestore
  .document('tasks/{taskId}/volunteers/{volunteerId}')
  .onCreate(async (snap, context) => {
    const { taskId } = context.params;
    const volunteerData = snap.data() || {};
    const volunteerId = volunteerData.volunteerId;
    const taskSnap = await db.collection('tasks').doc(taskId).get();
    if (!taskSnap.exists) return;
    const task = taskSnap.data() || {};
    const requesterId = task.requesterId;
    if (!requesterId || requesterId === volunteerId) return;
    const volunteerName = volunteerData.volunteerName || 'Someone';
    await sendPushToUser(requesterId, 'New volunteer', `${volunteerName} volunteered for your errand`, {
      type: 'task_volunteer',
      taskId,
    });
  });

exports.onVolunteerAccepted = functions.firestore
  .document('tasks/{taskId}/volunteers/{volunteerDocId}')
  .onUpdate(async (change, context) => {
    const { taskId } = context.params;
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const beforeStatus = beforeData.status;
    const afterStatus = afterData.status;
    // Only trigger when status changes to 'accepted'
    if (beforeStatus === 'accepted' || afterStatus !== 'accepted') return;
    const volunteerId = afterData.volunteerId;
    if (!volunteerId) return;
    const taskSnap = await db.collection('tasks').doc(taskId).get();
    if (!taskSnap.exists) return;
    await sendPushToUser(volunteerId, 'Volunteer accepted', 'You were accepted as volunteer for an errand', {
      type: 'volunteer_accepted',
      taskId,
    });
  });

// --- Callable: deleteAuthUser (unchanged) ---

/**
 * Callable: deleteAuthUser
 * Deletes a Firebase Auth user by uid. Used when admin declines a request that had
 * an Auth account (e.g. legacy flow) so the phone number can be used again.
 * Caller must be an admin (super_admin, admin, official, or staff).
 */
exports.deleteAuthUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }
  const callerUid = context.auth.uid;
  const toDeleteUid = data && typeof data.uid === 'string' ? data.uid.trim() : null;
  if (!toDeleteUid) {
    throw new functions.https.HttpsError('invalid-argument', 'uid required');
  }

  const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
  const role = callerDoc.exists && callerDoc.data() ? callerDoc.data().role : null;
  const allowed = ['super_admin', 'admin', 'official', 'staff'].includes(role);
  if (!allowed) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }

  await admin.auth().deleteUser(toDeleteUid);
  return { success: true };
});
