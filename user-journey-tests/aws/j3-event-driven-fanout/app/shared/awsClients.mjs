// awsClients.mjs — the single funnel for EVERY AWS SDK call in this pipeline.
// Keep any new AWS call in this module so call sites stay grep-able.
//
// Intended GCP mapping (planning notes, per service):
//   S3 uploads bucket                  -> Cloud Storage
//   SNS + SQS fan-out                  -> Pub/Sub
//   Lambda functions                   -> Cloud Run functions
//   DynamoDB edf-photos                -> Firestore
//   EventBridge schedule (digest)      -> Cloud Scheduler
import {
  S3Client,
  GetObjectCommand,
  CopyObjectCommand,
  PutObjectCommand,
} from "@aws-sdk/client-s3";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, ScanCommand } from "@aws-sdk/lib-dynamodb";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const REGION = process.env.AWS_REGION || "ap-northeast-1";
export const TABLE_NAME = process.env.TABLE_NAME || "edf-photos";
export const BUCKET = process.env.BUCKET;

const s3 = new S3Client({ region: REGION });
const documents = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));
const sns = new SNSClient({ region: REGION });

// Download an uploaded object; returns {bytes: Buffer, contentType}.
export async function getObject(key) {
  const out = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: key }));
  const bytes = Buffer.from(await out.Body.transformToByteArray());
  return { bytes, contentType: out.ContentType || "application/octet-stream" };
}

// "Thumbnail" step: server-side copy into thumbnails/ (real resize is a
// wishlist item; the copy preserves the pipeline shape).
export async function copyToThumbnails(key, basename) {
  await s3.send(new CopyObjectCommand({
    Bucket: BUCKET,
    CopySource: `${BUCKET}/${encodeURIComponent(key)}`,
    Key: `thumbnails/${basename}`,
  }));
}

// Write the nightly digest report object.
export async function putReport(key, body) {
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: body,
    ContentType: "application/json",
  }));
}

// Store one photo metadata record.
export async function putPhoto(item) {
  await documents.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
}

// Full scan (the table stays small; digest filters in memory).
export async function scanPhotos() {
  const items = [];
  let key;
  do {
    const out = await documents.send(new ScanCommand({
      TableName: TABLE_NAME,
      ExclusiveStartKey: key,
    }));
    items.push(...(out.Items ?? []));
    key = out.LastEvaluatedKey;
  } while (key);
  return items;
}

// Flag a non-image upload for the moderation channel.
export async function publishModerationAlert(message) {
  await sns.send(new PublishCommand({
    TopicArn: process.env.MODERATION_TOPIC_ARN,
    Subject: "photo-pipeline: non-image upload",
    Message: JSON.stringify(message),
  }));
}
