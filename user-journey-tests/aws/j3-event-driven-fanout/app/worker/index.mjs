// edf-worker — SQS-driven ingest step of the upload pipeline.
//
// Message path: S3 (incoming/*) -> SNS edf-uploads -> SQS edf-thumbnails-q
// (RawMessageDelivery: each SQS record body IS the S3 event JSON).
//
// Per object: hash + size + content type into DynamoDB, server-side copy to
// thumbnails/, and a moderation alert for anything that isn't image/*.
import { createHash } from "node:crypto";

import * as cloud from "./awsClients.mjs";

function decodeS3Key(raw) {
  // S3 event keys are URL-encoded with '+' for spaces.
  return decodeURIComponent(raw.replace(/\+/g, "%20"));
}

async function processObject(bucket, rawKey) {
  const key = decodeS3Key(rawKey);
  if (!key.startsWith("incoming/")) {
    console.log(`skip (not incoming/): ${key}`);
    return;
  }
  const { bytes, contentType } = await cloud.getObject(key);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const basename = key.slice("incoming/".length);

  await cloud.putPhoto({
    object_key: key,
    ingested_at: new Date().toISOString(),
    sha256,
    bytes: bytes.length,
    content_type: contentType,
  });
  await cloud.copyToThumbnails(key, basename);

  if (!contentType.startsWith("image/")) {
    await cloud.publishModerationAlert({
      object_key: key,
      content_type: contentType,
      reason: "upload is not an image",
    });
    console.log(`moderation alert raised for ${key} (${contentType})`);
  }
  console.log(`ingested ${key} (${bytes.length} bytes, ${contentType})`);
}

export async function handler(event) {
  for (const record of event.Records ?? []) {
    let body;
    try {
      body = JSON.parse(record.body);
    } catch {
      console.warn("skipping non-JSON SQS body");
      continue;
    }
    // S3 emits a one-off s3:TestEvent when the notification is configured.
    if (body.Event === "s3:TestEvent") {
      console.log("skipping s3:TestEvent");
      continue;
    }
    for (const s3Record of body.Records ?? []) {
      await processObject(s3Record.s3.bucket.name, s3Record.s3.object.key);
    }
  }
  return { ok: true };
}
