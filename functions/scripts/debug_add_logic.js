/**
 * Debug script to trace through the add logic and find where it failed
 * This will show us what SHOULD happen vs what actually happened
 */

const path = require("path");
const admin = require("firebase-admin");

const SERVICE_ACCOUNT_KEY_PATH = "../../backend/linkod-db-firebase-adminsdk-fbsvc-db4270d732.json";
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

const serviceAccount = require(path.resolve(__dirname, SERVICE_ACCOUNT_KEY_PATH));
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function main() {
  console.log("=== DETAILED ANALYSIS OF WHAT HAPPENED ===\n");

  // Simulate what the script should have done
  console.log("Step 1: Querying existing viewers across all products...");
  const existingByProduct = new Map();
  const existingUnion = new Set();

  for (const productId of PRODUCT_IDS) {
    const snap = await db
      .collection("products")
      .doc(productId)
      .collection("views")
      .select("userId")
      .get();
    const ids = new Set();
    for (const doc of snap.docs) {
      const uid = String((doc.data() || {}).userId || "").trim();
      if (uid) ids.add(uid);
    }
    existingByProduct.set(productId, ids);
    for (const uid of ids) existingUnion.add(uid);

    console.log(`  ${productId}: ${ids.size} existing viewers`);
  }

  console.log(`\nUnion of all existing viewers: ${existingUnion.size} total unique users`);

  // Get all auth users
  console.log("\nStep 2: Fetching all auth users...");
  const auth = admin.auth();
  const ids = [];
  let pageToken;
  do {
    const result = await auth.listUsers(1000, pageToken);
    for (const userRecord of result.users) {
      if (!userRecord.disabled) ids.push(userRecord.uid);
    }
    pageToken = result.pageToken;
  } while (pageToken);

  console.log(`  Total active auth users: ${ids.length}`);

  // Find shared candidates
  console.log("\nStep 3: Finding shared candidates (users not in ANY product) ...");
  const sharedCandidates = ids.filter((uid) => !existingUnion.has(uid));
  console.log(`  Shared eligible candidates: ${sharedCandidates.length}`);

  if (sharedCandidates.length < 23) {
    console.log(`  ERROR: Not enough shared candidates! Need 23, have ${sharedCandidates.length}`);
    return;
  }

  const selectedUserIds = sharedCandidates.slice(0, 23);
  console.log(`  Selected 23 users for adding`);

  // Now let's analyze what SHOULD have happened vs what DID happen
  console.log("\n=== WHAT SHOULD HAVE HAPPENED ===");
  for (const productId of PRODUCT_IDS) {
    const existing = existingByProduct.get(productId);
    const missingFromThis = selectedUserIds.filter((uid) => !existing.has(uid));
    console.log(`${productId}:`);
    console.log(`  - Existing before: ${existing.size}`);
    console.log(`  - Should add: ${missingFromThis.length}`);
    console.log(`  - Expected total: ${existing.size + missingFromThis.length}`);
  }

  // Now let's see what actually happened (current state)
  console.log("\n=== WHAT ACTUALLY HAPPENED (CURRENT STATE) ===");
  for (const productId of PRODUCT_IDS) {
    const snap = await db
      .collection("products")
      .doc(productId)
      .collection("views")
      .select("userId")
      .get();
    const existingNow = new Set();
    for (const doc of snap.docs) {
      const uid = String((doc.data() || {}).userId || "").trim();
      if (uid) existingNow.add(uid);
    }

    const wasAdded = 23; // What we tried to add in rollback
    const isNow = existingNow.size;
    const baseline = existingByProduct.get(productId).size;

    console.log(`${productId}:`);
    console.log(`  - Baseline (from union): ${baseline}`);
    console.log(`  - Deleted in rollback: ${wasAdded}`);
    console.log(`  - Actually now: ${isNow}`);
    if (baseline - isNow > wasAdded) {
      console.log(`  ⚠️  OOPS: Deleted ${baseline - isNow} but tried to delete only ${wasAdded}`);
    }
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
