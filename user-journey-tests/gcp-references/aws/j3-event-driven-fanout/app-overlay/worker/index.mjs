// edf-worker on Cloud Run functions — CloudEvent handler for GCS
// object-finalized events (Eventarc replaces the S3→SNS→SQS chain).
// Same ingest semantics as the Lambda original; prefix filtering moves
// into code because the trigger covers the whole bucket.
import { createHash } from "node:crypto";

import functions from "@google-cloud/functions-framework";

import * as cloud from "./gcpClients.mjs";

functions.cloudEvent("handler", async (cloudEvent) => {
  const data = cloudEvent.data || {};
  const key = data.name || "";
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
});
