"use strict";

/**
 * Add unique announcement reads for a post.
 *
 * Confirmed structure in this codebase:
 * - Post doc: announcements/{POST_ID}
 * - Read docs: userAnnouncementReads/{READ_DOC_ID}
 * - Strict read doc fields: { announcementId, readAt, userId }
 * - View docs: announcements/{POST_ID}/views/{VIEW_DOC_ID}
 * - View doc fields: { userId, viewedAt }
 *
 * Goal defaults:
 * - Current total views: 26
 * - Target total views: 151
 * - Additional viewers to add: 125
 *
 * Usage:
 *   1) Put your service account key JSON path in SERVICE_ACCOUNT_KEY_PATH.
 *   2) Put your post id in POST_ID.
 *   3) From the functions folder, run:
 *        node scripts/add_announcement_views.js
 *
 * Modes:
 * - add: add readers up to TARGET_TOTAL_VIEWS using strict fields only.
 * - rollback: delete previously generated wrong-shape docs (postId/readDate).
 */

const path = require("path");
const admin = require("firebase-admin");

// ===== PLACEHOLDERS (edit these) =====
const SERVICE_ACCOUNT_KEY_PATH = "../../backend/linkod-db-firebase-adminsdk-fbsvc-db4270d732.json";
const POST_ID = "5sADWd2W7us0JfTdoWXI";
const MODE = "add"; // "add" | "rollback"
// ================================

const TARGET_TOTAL_VIEWS = 96;
const MAX_BATCH_WRITES = 500;
const RANDOM_START_ISO = "2026-04-08T00:00:00+08:00";
const RANDOM_END_ISO = "2026-04-12T23:59:59+08:00";

function assertConfig() {
  if (!SERVICE_ACCOUNT_KEY_PATH || SERVICE_ACCOUNT_KEY_PATH.includes("PATH/TO/YOUR")) {
    throw new Error("Please set SERVICE_ACCOUNT_KEY_PATH.");
  }
  if (!POST_ID || POST_ID === "YOUR_POST_ID_HERE") {
    throw new Error("Please set POST_ID.");
  }
  if (!["add", "rollback"].includes(String(MODE))) {
    throw new Error('MODE must be "add" or "rollback".');
  }
}

async function listAllAuthUserIds(auth) {
  const ids = [];
  let pageToken;

  do {
    const result = await auth.listUsers(1000, pageToken);
    for (const userRecord of result.users) {
      // Keep disabled users out by default for cleaner analytics.
      if (!userRecord.disabled) {
        ids.push(userRecord.uid);
      }
    }
    pageToken = result.pageToken;
  } while (pageToken);

  return ids;
}

async function getExistingViewerIds(db, postId) {
  const readsRef = db.collection("userAnnouncementReads");
  const viewsRef = db.collection("announcements").doc(String(postId)).collection("views");
  const [legacySnap, newShapeSnap] = await Promise.all([
    readsRef.where("announcementId", "==", String(postId)).select("userId").get(),
    readsRef.where("postId", "==", String(postId)).select("userId").get(),
  ]);
  const viewsSnap = await viewsRef.select("userId").get();

  const existing = new Set();

  for (const snap of [legacySnap, newShapeSnap, viewsSnap]) {
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const uid = String(data.userId || "").trim();
      if (uid) existing.add(uid);
    }
  }

  return existing;
}

function getRandomTimestampInRange(startIso, endIso) {
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
    throw new Error("Invalid random date range configuration.");
  }
  const randomMs = Math.floor(Math.random() * (end - start + 1)) + start;
  return admin.firestore.Timestamp.fromMillis(randomMs);
}

async function syncAnnouncementViewCount(db, postId, uniqueReadersCount) {
  const postRef = db.collection("announcements").doc(String(postId));
  await postRef.set(
    {
      viewCount: uniqueReadersCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function rollbackWrongShapeDocs(db, postId) {
  const readsRef = db.collection("userAnnouncementReads");
  const [postIdDocs, readDateDocs] = await Promise.all([
    readsRef.where("postId", "==", String(postId)).get(),
    readsRef.where("announcementId", "==", String(postId)).where("readDate", ">", new Date(0)).get(),
  ]);

  const uniqueDocIds = new Set([
    ...postIdDocs.docs.map((d) => d.id),
    ...readDateDocs.docs.map((d) => d.id),
  ]);

  if (uniqueDocIds.size === 0) {
    console.log("Rollback: no wrong-shape docs found for this announcement.");
    return;
  }

  const docIds = Array.from(uniqueDocIds);
  const idChunks = chunk(docIds, MAX_BATCH_WRITES);
  let deleted = 0;

  for (const ids of idChunks) {
    const batch = db.batch();
    for (const id of ids) {
      batch.delete(readsRef.doc(id));
    }
    await batch.commit();
    deleted += ids.length;
  }

  const remainingReaders = await getExistingViewerIds(db, postId);
  await syncAnnouncementViewCount(db, postId, remainingReaders.size);

  console.log(`Rollback done. Deleted docs: ${deleted}`);
  console.log(`Remaining unique readers for post: ${remainingReaders.size}`);
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

async function addViews() {
  assertConfig();

  const serviceAccount = require(path.resolve(__dirname, SERVICE_ACCOUNT_KEY_PATH));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();
  const auth = admin.auth();

  const postRef = db.collection("announcements").doc(String(POST_ID));
  const readsRef = db.collection("userAnnouncementReads");
  const viewsRef = postRef.collection("views");

  const postSnap = await postRef.get();
  if (!postSnap.exists) {
    throw new Error(`Announcement not found: ${POST_ID}`);
  }

  if (MODE === "rollback") {
    await rollbackWrongShapeDocs(db, POST_ID);
    return;
  }

  const existingViewerIds = await getExistingViewerIds(db, POST_ID);
  const existingCount = existingViewerIds.size;
  const additionalViewsToAdd = TARGET_TOTAL_VIEWS - existingCount;

  if (additionalViewsToAdd <= 0) {
    await syncAnnouncementViewCount(db, POST_ID, existingCount);
    console.log("No new readers needed. Target is already reached or exceeded.");
    console.log(`Current unique readers: ${existingCount}`);
    console.log(`Target requested: ${TARGET_TOTAL_VIEWS}`);
    return;
  }

  const allAuthUserIds = await listAllAuthUserIds(auth);
  const candidates = allAuthUserIds.filter((uid) => !existingViewerIds.has(uid));

  if (candidates.length < additionalViewsToAdd) {
    throw new Error(
      `Not enough eligible auth users. Need ${additionalViewsToAdd}, found ${candidates.length}.`
    );
  }

  const selectedUserIds = candidates.slice(0, additionalViewsToAdd);

  const writesPerUser = 2; // 1 read doc + 1 view doc
  const maxUsersPerBatch = Math.max(1, Math.floor(MAX_BATCH_WRITES / writesPerUser));
  const userChunks = chunk(selectedUserIds, maxUsersPerBatch);

  let totalInserted = 0;
  for (const ids of userChunks) {
    const batch = db.batch();

    for (const uid of ids) {
      const randomizedTs = getRandomTimestampInRange(RANDOM_START_ISO, RANDOM_END_ISO);

      const readDocRef = readsRef.doc();
      batch.set(
        readDocRef,
        {
          userId: uid,
          announcementId: String(POST_ID),
          readAt: randomizedTs,
        },
        { merge: true }
      );

      const viewDocRef = viewsRef.doc();
      batch.set(
        viewDocRef,
        {
          userId: uid,
          viewedAt: randomizedTs,
        },
        { merge: true }
      );
    }

    await batch.commit();
    totalInserted += ids.length;
  }

  const finalUniqueReaders = existingCount + totalInserted;
  await syncAnnouncementViewCount(db, POST_ID, finalUniqueReaders);

  console.log("Done.");
  console.log(`Post ID: ${POST_ID}`);
  console.log(`Existing reader users before: ${existingCount}`);
  console.log(`Inserted new unique readers: ${totalInserted}`);
  console.log(`Expected total unique readers for this post: ${finalUniqueReaders}`);
  console.log(`Target requested: ${TARGET_TOTAL_VIEWS}`);
}

addViews()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Failed to add views:", err.message || err);
    process.exit(1);
  });
