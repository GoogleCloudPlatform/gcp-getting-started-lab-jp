// gcpClients.mjs — the migrated counterpart of awsClients.mjs.
//
// Mapping implemented (mirrors the funnel header in the AWS app):
//   S3 uploads bucket           -> Cloud Storage
//   SNS + SQS fan-out           -> Eventarc (GCS finalized) + Pub/Sub
//   Lambda functions            -> Cloud Run functions (nodejs22)
//   DynamoDB edf-photos         -> Firestore (Native), NAMED database edf-photos
//   EventBridge schedule        -> Cloud Scheduler
//
// Firestore doc ids cannot contain '/', so the raw object key is stored as a
// field and the doc id is encodeURIComponent(object_key).
import { Storage } from "@google-cloud/storage";
import { Firestore } from "@google-cloud/firestore";
import { PubSub } from "@google-cloud/pubsub";

export const TABLE_NAME = process.env.TABLE_NAME || "edf-photos";
export const BUCKET = process.env.BUCKET;
const FIRESTORE_DB = process.env.FIRESTORE_DB || "edf-photos";
const MODERATION_TOPIC = process.env.MODERATION_TOPIC || "edf-moderation-alerts";

const storage = new Storage();
const firestore = new Firestore({ databaseId: FIRESTORE_DB });
const pubsub = new PubSub();
const photos = firestore.collection(TABLE_NAME);

export async function getObject(key) {
  const file = storage.bucket(BUCKET).file(key);
  const [meta] = await file.getMetadata();
  const [bytes] = await file.download();
  return { bytes, contentType: meta.contentType || "application/octet-stream" };
}

export async function copyToThumbnails(key, basename) {
  await storage.bucket(BUCKET).file(key)
    .copy(storage.bucket(BUCKET).file(`thumbnails/${basename}`));
}

export async function putReport(key, body) {
  await storage.bucket(BUCKET).file(key)
    .save(body, { contentType: "application/json" });
}

export async function putPhoto(item) {
  await photos.doc(encodeURIComponent(item.object_key)).set(item);
}

export async function scanPhotos() {
  const snap = await photos.get();
  return snap.docs.map((d) => d.data());
}

export async function publishModerationAlert(message) {
  await pubsub.topic(MODERATION_TOPIC)
    .publishMessage({ json: message, attributes: { subject: "photo-pipeline: non-image upload" } });
}
