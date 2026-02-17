const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

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
