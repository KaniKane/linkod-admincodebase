const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();
const MAX_TOKENS_PER_BATCH = 500;
const OTP_TTL_MINUTES = 5;

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function generateOtpCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashOtp(email, otp) {
  return crypto.createHash('sha256').update(`${normalizeEmail(email)}:${otp}`).digest('hex');
}

function getMailTransport() {
  const host = process.env.SMTP_HOST || functions.config()?.smtp?.host;
  const portRaw = process.env.SMTP_PORT || functions.config()?.smtp?.port || '587';
  const secureRaw = process.env.SMTP_SECURE || functions.config()?.smtp?.secure || 'false';
  const user = process.env.SMTP_USER || functions.config()?.smtp?.user;
  const pass = process.env.SMTP_PASS || functions.config()?.smtp?.pass;

  if (!host || !user || !pass) {
    throw new Error('SMTP is not configured. Set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS.');
  }

  return nodemailer.createTransport({
    host,
    port: Number(portRaw),
    secure: String(secureRaw).toLowerCase() === 'true',
    auth: { user, pass },
  });
}

async function sendOtpEmail(email, otp) {
  const fromAddress =
    process.env.SMTP_FROM ||
    functions.config()?.smtp?.from ||
    'Linkod Admin <no-reply@linkod.local>';
  const transport = getMailTransport();
  await transport.sendMail({
    from: fromAddress,
    to: email,
    subject: 'Your Linkod verification code',
    text: `Your OTP is ${otp}. It expires in ${OTP_TTL_MINUTES} minutes.`,
    html: `<p>Your OTP is <b>${otp}</b>.</p><p>This code expires in ${OTP_TTL_MINUTES} minutes.</p>`,
  });
}

function inferUserTypeByRole(role) {
  const normalizedRole = String(role || '').toLowerCase();
  if (normalizedRole === 'admin' || normalizedRole === 'super_admin') {
    return 'admin';
  }
  return 'resident';
}

function normalizeUserType(value, roleHint) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'admin' || normalized === 'resident') {
    return normalized;
  }
  return inferUserTypeByRole(roleHint);
}

function mapHttpsErrorToStatus(code) {
  switch (String(code || '')) {
    case 'invalid-argument':
      return 400;
    case 'unauthenticated':
      return 401;
    case 'permission-denied':
      return 403;
    case 'not-found':
      return 404;
    case 'already-exists':
      return 409;
    case 'failed-precondition':
      return 412;
    case 'deadline-exceeded':
      return 408;
    default:
      return 500;
  }
}

async function performSendEmailOtp(payload) {
  const email = normalizeEmail(payload?.email);
  if (!validateEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'Valid email is required.');
  }

  try {
    const existing = await admin.auth().getUserByEmail(email);
    if (existing) {
      throw new functions.https.HttpsError('already-exists', 'Email is already registered.');
    }
  } catch (e) {
    if (e.code !== 'auth/user-not-found') {
      throw e;
    }
  }

  const pendingExisting = await db
    .collection('awaitingApproval')
    .where('email', '==', email)
    .where('status', '==', 'pending')
    .limit(1)
    .get();
  if (!pendingExisting.empty) {
    throw new functions.https.HttpsError(
      'already-exists',
      'A pending request already exists for this email.',
    );
  }

  const otp = generateOtpCode();
  const nowMs = Date.now();
  const expiresAtMs = nowMs + OTP_TTL_MINUTES * 60 * 1000;

  await db.collection('emailOtpRequests').doc(email).set({
    email,
    otpHash: hashOtp(email, otp),
    createdAtMs: nowMs,
    expiresAtMs,
    verified: false,
    consumed: false,
    attempts: 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await sendOtpEmail(email, otp);

  return {
    ok: true,
    expiresInSeconds: OTP_TTL_MINUTES * 60,
  };
}

async function performVerifyEmailOtp(payload) {
  const email = normalizeEmail(payload?.email);
  const otp = String(payload?.otp || '').trim();
  if (!validateEmail(email) || otp.length != 6) {
    throw new functions.https.HttpsError('invalid-argument', 'Email and 6-digit OTP are required.');
  }

  const ref = db.collection('emailOtpRequests').doc(email);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'OTP request not found.');
  }

  const dataDoc = snap.data() || {};
  const expiresAtMs = Number(dataDoc.expiresAtMs || 0);
  const expectedHash = String(dataDoc.otpHash || '');
  const consumed = dataDoc.consumed === true;
  const nowMs = Date.now();

  if (consumed) {
    throw new functions.https.HttpsError('failed-precondition', 'OTP is already used.');
  }
  if (expiresAtMs <= nowMs) {
    throw new functions.https.HttpsError('deadline-exceeded', 'OTP has expired.');
  }

  const providedHash = hashOtp(email, otp);
  const attempts = Number(dataDoc.attempts || 0) + 1;
  if (providedHash !== expectedHash) {
    await ref.update({ attempts, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    throw new functions.https.HttpsError('permission-denied', 'Invalid OTP code.');
  }

  await ref.update({
    verified: true,
    verifiedAtMs: nowMs,
    attempts,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { ok: true };
}

async function performCreatePendingSignup(payload) {
  const email = normalizeEmail(payload?.email);
  const password = String(payload?.password || '');
  const firstName = String(payload?.firstName || '').trim();
  const middleName = String(payload?.middleName || '').trim();
  const lastName = String(payload?.lastName || '').trim();
  const position = String(payload?.position || '').trim();
  const requestedRole = String(payload?.requestedRole || 'admin').toLowerCase();
  const userType = normalizeUserType(payload?.userType, requestedRole);

  if (!validateEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'Valid email is required.');
  }
  if (password.length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
  }
  if (!firstName || !lastName) {
    throw new functions.https.HttpsError('invalid-argument', 'First name and last name are required.');
  }

  const otpRef = db.collection('emailOtpRequests').doc(email);
  const otpSnap = await otpRef.get();
  if (!otpSnap.exists) {
    throw new functions.https.HttpsError('failed-precondition', 'Email must be verified first.');
  }
  const otpData = otpSnap.data() || {};
  const verified = otpData.verified === true;
  const consumed = otpData.consumed === true;
  const verifiedAtMs = Number(otpData.verifiedAtMs || 0);
  const nowMs = Date.now();
  if (!verified || consumed || nowMs - verifiedAtMs > 15 * 60 * 1000) {
    throw new functions.https.HttpsError('failed-precondition', 'Email verification is missing or expired.');
  }

  try {
    const existing = await admin.auth().getUserByEmail(email);
    if (existing) {
      throw new functions.https.HttpsError('already-exists', 'Email is already registered.');
    }
  } catch (e) {
    if (e.code !== 'auth/user-not-found') {
      throw e;
    }
  }

  const pendingExisting = await db
    .collection('awaitingApproval')
    .where('email', '==', email)
    .where('status', '==', 'pending')
    .limit(1)
    .get();
  if (!pendingExisting.empty) {
    throw new functions.https.HttpsError(
      'already-exists',
      'A pending request already exists for this email.',
    );
  }

  const userRecord = await admin.auth().createUser({
    email,
    password,
    displayName: [firstName, middleName, lastName].filter(Boolean).join(' '),
    emailVerified: false,
  });

  const now = admin.firestore.FieldValue.serverTimestamp();
  const fullName = [firstName, middleName, lastName].filter(Boolean).join(' ');
  await db.collection('awaitingApproval').doc(userRecord.uid).set({
    uid: userRecord.uid,
    userType,
    firstName,
    middleName,
    lastName,
    fullName,
    email,
    requestedRole: userType === 'admin' ? (requestedRole === 'super_admin' ? 'super_admin' : 'admin') : 'resident',
    role: userType === 'resident' ? 'resident' : 'admin',
    position: userType === 'admin' ? (position || 'Admin') : '',
    status: 'pending',
    accountStatus: 'pending',
    isApproved: false,
    createdAt: now,
    updatedAt: now,
  });

  await otpRef.update({
    consumed: true,
    consumedAtMs: nowMs,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    ok: true,
    uid: userRecord.uid,
    message: 'Waiting for admin approval.',
  };
}

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

  // Keep category matching backward-compatible across renamed demographics.
  const audienceAliases = {
    'public utility drivers': ['tricycle driver'],
    'tricycle driver': ['public utility drivers'],
  };

  const expanded = new Set();
  filterAudiences.forEach((a) => {
    const lower = String(a || '').toLowerCase().trim();
    if (!lower) return;
    expanded.add(lower);
    (audienceAliases[lower] || []).forEach((alias) => expanded.add(alias));
  });

  const filterLower = [...expanded];
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

app.post('/seed-default-super-admin', async (req, res) => {
  try {
    const providedSeedKey = req.headers['x-seed-key'] || req.body?.seedKey;
    const configuredSeedKey = process.env.SEED_KEY || functions.config()?.app?.seed_key;
    if (!configuredSeedKey || providedSeedKey !== configuredSeedKey) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const email = normalizeEmail(req.body?.email || process.env.DEFAULT_SUPER_ADMIN_EMAIL || 'dev@system.com');
    const password = String(req.body?.password || process.env.DEFAULT_SUPER_ADMIN_PASSWORD || '').trim();
    const fullName = String(req.body?.fullName || 'System Developer').trim();

    if (!validateEmail(email)) {
      return res.status(400).json({ error: 'Valid email is required.' });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        userRecord = await admin.auth().createUser({
          email,
          password,
          displayName: fullName,
          emailVerified: true,
        });
      } else {
        throw e;
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection('users').doc(userRecord.uid).set(
      {
        userId: userRecord.uid,
        fullName,
        email,
        role: 'super_admin',
        userType: 'admin',
        status: 'approved',
        accountStatus: 'active',
        isApproved: true,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

    return res.status(200).json({ ok: true, uid: userRecord.uid, email });
  } catch (e) {
    console.error('seed-default-super-admin error:', e);
    return res.status(503).json({ error: String(e.message || e) });
  }
});

app.post('/promote-user-super-admin', async (req, res) => {
  try {
    const providedSeedKey = req.headers['x-seed-key'] || req.body?.seedKey;
    const configuredSeedKey = process.env.SEED_KEY || functions.config()?.app?.seed_key;
    if (!configuredSeedKey || providedSeedKey !== configuredSeedKey) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    const email = normalizeEmail(req.body?.email);
    if (!validateEmail(email)) {
      return res.status(400).json({ error: 'Valid email is required.' });
    }

    const userRecord = await admin.auth().getUserByEmail(email);
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection('users').doc(userRecord.uid).set(
      {
        userId: userRecord.uid,
        email,
        role: 'super_admin',
        userType: 'admin',
        status: 'approved',
        accountStatus: 'active',
        isApproved: true,
        isActive: true,
        updatedAt: now,
      },
      { merge: true },
    );

    return res.status(200).json({ ok: true, uid: userRecord.uid, email });
  } catch (e) {
    console.error('promote-user-super-admin error:', e);
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

app.post('/auth/send-email-otp', async (req, res) => {
  try {
    const result = await performSendEmailOtp(req.body || {});
    return res.status(200).json(result);
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      return res.status(mapHttpsErrorToStatus(e.code)).json({
        error: e.message,
        code: e.code,
      });
    }
    console.error('auth/send-email-otp error:', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

app.post('/auth/verify-email-otp', async (req, res) => {
  try {
    const result = await performVerifyEmailOtp(req.body || {});
    return res.status(200).json(result);
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      return res.status(mapHttpsErrorToStatus(e.code)).json({
        error: e.message,
        code: e.code,
      });
    }
    console.error('auth/verify-email-otp error:', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

app.post('/auth/create-pending-signup', async (req, res) => {
  try {
    const result = await performCreatePendingSignup(req.body || {});
    return res.status(200).json(result);
  } catch (e) {
    if (e instanceof functions.https.HttpsError) {
      return res.status(mapHttpsErrorToStatus(e.code)).json({
        error: e.message,
        code: e.code,
      });
    }
    console.error('auth/create-pending-signup error:', e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'linkod-admin-api' });
});

exports.api = functions.https.onRequest(app);

exports.sendEmailOtp = functions.https.onCall(async (data) => performSendEmailOtp(data));

exports.verifyEmailOtp = functions.https.onCall(async (data) => performVerifyEmailOtp(data));

exports.createPendingSignup = functions.https.onCall(async (payload) => performCreatePendingSignup(payload));

// --- Firestore triggers: send push on like, comment, task chat, product message (red indicators stay in app) ---

async function sendPushToUser(userId, title, body, data) {
  if (!userId) return;
  const tokens = await getTokensForUser(userId);
  if (tokens.length === 0) return;
  await sendMulticast(tokens, title, body, data);
}

function isPendingValue(value) {
  return String(value || '').trim().toLowerCase() === 'pending';
}

async function getApprovalsSettings() {
  try {
    const settingsSnap = await db.collection('publicSettings').doc('approvals').get();
    const data = settingsSnap.exists ? settingsSnap.data() || {} : {};
    return {
      autoApproveProducts: data.autoApproveProducts === true,
      autoApproveTasks: data.autoApproveTasks === true,
    };
  } catch (e) {
    console.error('Failed to load publicSettings/approvals:', e);
    return {
      autoApproveProducts: false,
      autoApproveTasks: false,
    };
  }
}

exports.onProductCreatedAutoApprove = functions.firestore
  .document('products/{productId}')
  .onCreate(async (snap, context) => {
    const { productId } = context.params;
    const product = snap.data() || {};
    if (!isPendingValue(product.status)) return;

    const { autoApproveProducts } = await getApprovalsSettings();
    if (!autoApproveProducts) return;

    try {
      await snap.ref.update({
        status: 'Approved',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error(`Auto-approve product failed for ${productId}:`, e);
    }
  });

exports.onTaskCreatedAutoApprove = functions.firestore
  .document('tasks/{taskId}')
  .onCreate(async (snap, context) => {
    const { taskId } = context.params;
    const task = snap.data() || {};
    const currentApproval = task.approvalStatus || task.status;
    if (!isPendingValue(currentApproval)) return;

    const { autoApproveTasks } = await getApprovalsSettings();
    if (!autoApproveTasks) return;

    try {
      await snap.ref.update({
        approvalStatus: 'Approved',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error(`Auto-approve task failed for ${taskId}:`, e);
    }
  });

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

// --- Firestore triggers: send admin notification on new awaitingApproval document ---

async function getAdminTokens() {
  const tokens = [];
  const seen = new Set();
  const seenUserIds = new Set();
  const snapshots = await Promise.all([
    db.collection('users').where('role', 'in', ['super_admin', 'admin', 'official', 'staff']).get(),
    db.collection('users').where('userType', '==', 'admin').get(),
  ]);

  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (seenUserIds.has(doc.id)) {
        continue;
      }
      seenUserIds.add(doc.id);

    const data = doc.data() || {};
    const isActiveByFlag = data.isActive === true;
    const accountStatus = String(data.accountStatus || '').toLowerCase();
    const isApproved = data.isApproved === true;

    // Support both old and new account-state conventions.
    const isActiveAccount = isActiveByFlag || accountStatus === 'active' || isApproved;
    if (!isActiveAccount) {
      continue;
    }

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
  }
  return tokens;
}

exports.onAwaitingApprovalCreated = functions.firestore
  .document('awaitingApproval/{requestId}')
  .onCreate(async (snap, context) => {
    const { requestId } = context.params;
    const data = snap.data() || {};

    const fullName = data.fullName || 'Someone';
    const isResubmission = (data.reapplicationCount || 0) > 0;

    const title = isResubmission ? 'Account Resubmission' : 'New Account Request';
    const body = isResubmission
      ? `${fullName} resubmitted their application`
      : `${fullName} requested a new account`;

    try {
      const tokens = await getAdminTokens();
      if (tokens.length === 0) {
        console.log(`No admin tokens found for ${requestId}`);
        return;
      }

      const { successCount, failureCount } = await sendMulticast(tokens, title, body, {
        type: 'new_account_request',
        requestId,
        userType: data.userType || 'admin',
      });

      console.log(`Admin notification sent for ${requestId}: ${successCount} success, ${failureCount} failure`);
    } catch (e) {
      console.error(`Failed to send admin notification for ${requestId}:`, e);
    }
  });


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
