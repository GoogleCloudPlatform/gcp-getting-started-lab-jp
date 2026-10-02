// edf-digest — nightly EventBridge schedule (rate(1 day)).
//
// Summarises the last 24h of ingests into reports/daily-YYYY-MM-DD.json in
// the uploads bucket. Growth marketing reads these; nothing else does.
import * as cloud from "./awsClients.mjs";

export async function handler() {
  const now = new Date();
  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  const all = await cloud.scanPhotos();
  const recent = all.filter((p) => (p.ingested_at ?? "") >= since);

  const byType = {};
  let totalBytes = 0;
  for (const photo of recent) {
    byType[photo.content_type] = (byType[photo.content_type] ?? 0) + 1;
    totalBytes += Number(photo.bytes ?? 0);
  }

  const day = now.toISOString().slice(0, 10);
  const key = `reports/daily-${day}.json`;
  await cloud.putReport(key, JSON.stringify({
    generated_at: now.toISOString(),
    window_start: since,
    ingested: recent.length,
    total_bytes: totalBytes,
    by_content_type: byType,
  }, null, 2));

  console.log(`digest written: ${key} (${recent.length} objects)`);
  return { report: key, ingested: recent.length };
}
