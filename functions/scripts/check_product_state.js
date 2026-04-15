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
  console.log("=== PRODUCT VIEWER STATE AFTER ROLLBACK ===\n");

  for (const pid of PRODUCT_IDS) {
    const snap = await db.collection("products").doc(pid).collection("views").select("userId").get();
    console.log(`${pid}: ${snap.size} viewers`);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
