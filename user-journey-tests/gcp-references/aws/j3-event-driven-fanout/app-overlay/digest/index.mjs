// edf-digest on Cloud Run functions — HTTP handler invoked nightly by
// Cloud Scheduler (OIDC), replacing the EventBridge rate(1 day) schedule.
import functions from "@google-cloud/functions-framework";

import * as cloud from "./gcpClients.mjs";

functions.http("handler", async (_req, res) => {
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
  res.json({ report: key, ingested: recent.length });
});
