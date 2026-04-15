"use strict";

/**
 * Add randomized viewers to one or more product postings.
 *
 * Structure used:
 * - Product doc: products/{PRODUCT_ID}
 * - Viewer docs: products/{PRODUCT_ID}/views/{AUTO_DOC_ID}
 * - Viewer fields: { userId, viewedAt }
 * - Product aggregate field: viewCount
 *
 * Behavior:
 * - Works on multiple product IDs in one run.
 * - add mode: adds exactly N viewers on top of existing viewers for every product ID.
 * - rollback mode: removes the latest N viewer docs for every product ID.
 * - In add mode, the SAME user IDs and SAME viewedAt timestamps are used across all product IDs.
 * - New viewers are selected from Firebase Auth users not already present in ANY target posting.
 * - viewedAt timestamps are randomized in the configured date range and reused per user.
 * - Uses db.batch() and keeps writes under Firestore batch limits.
 *
 * Run from functions/:
 *   node scripts/add_product_views.js
 */

const path = require("path");
const admin = require("firebase-admin");

// ===== PLACEHOLDERS (edit these) =====
const SERVICE_ACCOUNT_KEY_PATH = "../../backend/linkod-db-firebase-adminsdk-fbsvc-db4270d732.json";

// Set one or more product posting IDs.
const PRODUCT_IDS = [
  "668VUUlsG4DP5vNsL4Xd",
  "GWeVKwi2rhTKnU7c60ZY",
  "N8SNjnJHf0to34G9aEB7",
  "NtTrYKhYu5TqP57X2zzC",
  "PnwKoH5BTgnpFvGis25v",
  "VASyiRrgYe8r2Vd4WPel",
  "guG554cna8ci1M0NQ0DV",
  "kxIZTOVyhrfHvIHJ83ay",
  "nzTxtwWeMfZOqlGplZ8o",
  "r00MzNbEYIQi3ti4BI0U",
  "xoGU00X0qvXa6sCkb6BC",
];

const MODE = "add"; // "add" | "rollback"
const ADDITIONAL_VIEWERS_TO_ADD = 23; // Added on top of existing, per product

const RANDOM_START_ISO = "2026-04-08T00:00:00+08:00";
const RANDOM_END_ISO = "2026-04-12T23:59:59+08:00";
// =====================================

const MAX_BATCH_WRITES = 500;

function assertConfig() {
  if (!SERVICE_ACCOUNT_KEY_PATH || SERVICE_ACCOUNT_KEY_PATH.includes("PATH/TO/YOUR")) {
    throw new Error("Please set SERVICE_ACCOUNT_KEY_PATH.");
  }

  const ids = PRODUCT_IDS || [];
  if (ids.length === 0) {
    throw new Error("Please set at least one product ID in PRODUCT_IDS.");
  }

  for (const id of ids) {
    if (!String(id).trim()) {
      throw new Error("PRODUCT_IDS must not contain empty values.");
    }
  }

  if (!["add", "rollback"].includes(String(MODE))) {
    throw new Error('MODE must be "add" or "rollback".');
  }

  if (!Number.isFinite(ADDITIONAL_VIEWERS_TO_ADD) || ADDITIONAL_VIEWERS_TO_ADD < 0) {
    throw new Error("ADDITIONAL_VIEWERS_TO_ADD must be a non-negative number.");
  }
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

function randomTimestamp(startIso, endIso) {
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();

  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
    throw new Error("Invalid RANDOM_START_ISO / RANDOM_END_ISO range.");
  }

  const ms = Math.floor(Math.random() * (end - start + 1)) + start;
  return admin.firestore.Timestamp.fromMillis(ms);
}

async function listAllAuthUserIds(auth) {
  const ids = [];
  let pageToken;

  do {
    const result = await auth.listUsers(1000, pageToken);
    for (const userRecord of result.users) {
      if (!userRecord.disabled) ids.push(userRecord.uid);
    }
    pageToken = result.pageToken;
  } while (pageToken);

  return ids;
}

async function getExistingViewerIdsForProduct(db, productId) {
  const snap = await db
    .collection("products")
    .doc(String(productId))
    .collection("views")
    .select("userId")
    .get();

  const existing = new Set();
  for (const doc of snap.docs) {
    const uid = String((doc.data() || {}).userId || "").trim();
    if (uid) existing.add(uid);
  }
  return existing;
}

async function getExistingViewerDocsForProduct(db, productId) {
  const viewsRef = db.collection("products").doc(String(productId)).collection("views");
  const snap = await viewsRef.get();
  return snap.docs;
}

async function syncProductViewCount(db, productId, uniqueViewerCount) {
  await db
    .collection("products")
    .doc(String(productId))
    .set(
      {
        viewCount: uniqueViewerCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

async function addViewersForProduct({ db, productId, selectedUserIds, userTimeMap }) {
  const productRef = db.collection("products").doc(String(productId));
  const productSnap = await productRef.get();
  if (!productSnap.exists) {
    throw new Error(`Product not found: ${productId}`);
  }

  const viewsRef = productRef.collection("views");
  const existingViewerIds = await getExistingViewerIdsForProduct(db, productId);
  const existingCount = existingViewerIds.size;

  // Create a fresh copy to avoid any mutation issues
  const userIdsArray = Array.isArray(selectedUserIds) ? [...selectedUserIds] : selectedUserIds;

  // Find which of the selected users are NOT already in this product
  const missingUserIds = userIdsArray.filter((uid) => !existingViewerIds.has(uid));

  if (missingUserIds.length === 0) {
    console.log(`  [${productId}] All ${userIdsArray.length} selected users already exist, skipping`);
    await syncProductViewCount(db, productId, existingCount);
    return {
      productId,
      existingCount,
      inserted: 0,
      finalCount: existingCount,
      targetTotal: existingCount + ADDITIONAL_VIEWERS_TO_ADD,
      skipped: true,
    };
  }

  console.log(
    `  [${productId}] Adding ${missingUserIds.length}/${userIdsArray.length} selected users (${existingCount} existing)`
  );

  // Validate that all missing users have timestamps in the map
  for (const uid of missingUserIds) {
    if (!userTimeMap.has(uid)) {
      throw new Error(
        `CRITICAL: User ${uid} missing from userTimeMap for product ${productId}. Map size: ${userTimeMap.size}`
      );
    }
  }

  const writesPerUser = 1;
  const maxUsersPerBatch = Math.max(1, Math.floor(MAX_BATCH_WRITES / writesPerUser));
  const chunks = chunk(missingUserIds, maxUsersPerBatch);

  let inserted = 0;
  for (const ids of chunks) {
    const batch = db.batch();

    for (const uid of ids) {
      const timestamp = userTimeMap.get(uid);
      if (!timestamp) {
        throw new Error(
          `CRITICAL: Timestamp missing for user ${uid} in product ${productId}`
        );
      }
      batch.set(viewsRef.doc(), {
        userId: uid,
        viewedAt: timestamp,
      });
    }

    await batch.commit();
    inserted += ids.length;
    console.log(`    Batch: ${inserted}/${missingUserIds.length} committed`);
  }

  const finalCount = existingCount + inserted;
  await syncProductViewCount(db, productId, finalCount);

  // Verify the addition worked
  const verifyExisting = await getExistingViewerIdsForProduct(db, productId);
  const verifyFinal = verifyExisting.size;

  if (verifyFinal !== finalCount) {
    throw new Error(
      `VERIFICATION FAILED for ${productId}: expected ${finalCount}, found ${verifyFinal}`
    );
  }

  console.log(`  [${productId}] ✓ Added ${inserted}, total = ${finalCount}\n`);

  return {
    productId,
    existingCount,
    inserted,
    finalCount,
    targetTotal: existingCount + ADDITIONAL_VIEWERS_TO_ADD,
    skipped: false,
  };
}

async function rollbackViewersForProduct({ db, productId, deleteCount }) {
  const productRef = db.collection("products").doc(String(productId));
  const productSnap = await productRef.get();
  if (!productSnap.exists) {
    throw new Error(`Product not found: ${productId}`);
  }

  const viewsRef = productRef.collection("views");
  const docs = await getExistingViewerDocsForProduct(db, productId);

  const sortable = docs
    .map((d) => ({ id: d.id, ref: d.ref, data: d.data() || {} }))
    .filter((r) => r.data.viewedAt && r.data.viewedAt.toMillis)
    .sort((a, b) => b.data.viewedAt.toMillis() - a.data.viewedAt.toMillis());

  const targets = sortable.slice(0, Math.min(deleteCount, sortable.length));
  const groups = chunk(targets, MAX_BATCH_WRITES);

  let deleted = 0;
  for (const g of groups) {
    const batch = db.batch();
    for (const row of g) batch.delete(row.ref);
    await batch.commit();
    deleted += g.length;
  }

  const remainingUnique = await getExistingViewerIdsForProduct(db, productId);
  await syncProductViewCount(db, productId, remainingUnique.size);

  return {
    productId,
    deleted,
    remaining: remainingUnique.size,
  };
}

async function main() {
  assertConfig();

  const serviceAccount = require(path.resolve(__dirname, SERVICE_ACCOUNT_KEY_PATH));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();
  const auth = admin.auth();

  const productIds = [...new Set(PRODUCT_IDS.map((id) => String(id).trim()).filter(Boolean))];
  const results = [];

  console.log("\n=== PRODUCT VIEWERS OPERATION ===");
  console.log(`MODE: ${MODE}`);
  console.log(`TARGET PRODUCTS: ${productIds.length}`);
  console.log(`VIEWERS PER PRODUCT: ${ADDITIONAL_VIEWERS_TO_ADD}\n`);

  if (MODE === "rollback") {
    console.log("Starting rollback...\n");
    for (const productId of productIds) {
      const result = await rollbackViewersForProduct({
        db,
        productId,
        deleteCount: ADDITIONAL_VIEWERS_TO_ADD,
      });
      results.push(result);
    }

    console.log("\nRollback done.");
    for (const r of results) {
      console.log(
        [
          `productId=${r.productId}`,
          `deleted=${r.deleted}`,
          `remaining=${r.remaining}`,
        ].join(" | ")
      );
    }
    return;
  }

  console.log("Fetching all auth users...");
  const allAuthUserIds = await listAllAuthUserIds(auth);
  console.log(`Found ${allAuthUserIds.length} active auth users\n`);

  console.log("Building union of existing viewers across all products...");
  const existingByProduct = new Map();
  const existingUnion = new Set();
  for (const productId of productIds) {
    const existing = await getExistingViewerIdsForProduct(db, productId);
    existingByProduct.set(productId, existing);
    for (const uid of existing) existingUnion.add(uid);
    console.log(`  ${productId}: ${existing.size} existing viewers`);
  }

  console.log(`\nUnion of existing: ${existingUnion.size} unique users\n`);

  // Same set of users must be added across all postings, so candidates must be absent in all of them.
  const sharedCandidates = allAuthUserIds.filter((uid) => !existingUnion.has(uid));
  console.log(`Shared eligible candidates: ${sharedCandidates.length}`);

  if (sharedCandidates.length < ADDITIONAL_VIEWERS_TO_ADD) {
    throw new Error(
      `Not enough shared eligible users. Need ${ADDITIONAL_VIEWERS_TO_ADD}, found ${sharedCandidates.length}`
    );
  }

  const selectedUserIds = sharedCandidates.slice(0, ADDITIONAL_VIEWERS_TO_ADD);
  console.log(`Selected ${selectedUserIds.length} users for adding\n`);

  // Same timestamp per user across all target postings.
  console.log("Generating randomized timestamps...");
  const userTimeMap = new Map();
  for (const uid of selectedUserIds) {
    userTimeMap.set(uid, randomTimestamp(RANDOM_START_ISO, RANDOM_END_ISO));
  }
  console.log(`Created map with ${userTimeMap.size} entries\n`);

  console.log("Adding viewers to each product:\n");
  for (const productId of productIds) {
    const result = await addViewersForProduct({
      db,
      productId,
      selectedUserIds,
      userTimeMap,
    });
    results.push(result);
  }

  console.log("=== OPERATION COMPLETE ===\n");
  for (const r of results) {
    console.log(
      [
        `productId=${r.productId}`,
        `existing=${r.existingCount}`,
        `inserted=${r.inserted}`,
        `final=${r.finalCount}`,
        `target=${r.targetTotal}`,
        `skipped=${r.skipped}`,
      ].join(" | ")
    );
  }
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Failed to add product viewers:", err.message || err);
    process.exit(1);
  });
