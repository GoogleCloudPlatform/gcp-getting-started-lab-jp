// azureClients.mjs — the single funnel for EVERY Azure SDK call the uploader
// makes. Keep any new Azure call in this module so the call sites stay in one
// place.
//
// Where each of these is expected to land on Google Cloud, per service:
//   Blob container intake/ (shoot upload)   -> Cloud Storage
//   Blob container masters/ (library read)  -> Cloud Storage
//   Storage queue proxy-jobs (depth read)   -> Cloud Tasks
//   Entra sign-in for the operator          -> Application Default Credentials
//
// Credentials: none are configured here and none are stored anywhere. The
// operator signs in once with `az login` on the ingest workstation and
// DefaultAzureCredential picks that session up. Data-plane calls therefore need
// the signed-in operator to hold a Storage Blob Data role on the account —
// control-plane Contributor is not enough, which is why `azure-check` reports
// each service separately instead of failing the whole run.
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { DefaultAzureCredential } from "@azure/identity";
import { BlobServiceClient } from "@azure/storage-blob";
import { QueueServiceClient } from "@azure/storage-queue";

export const config = {
  mediaAccount: process.env.SMP_MEDIA_ACCOUNT ?? "",
  intakeContainer: process.env.SMP_INTAKE_CONTAINER || "intake",
  mastersContainer: process.env.SMP_MASTERS_CONTAINER || "masters",
  proxyQueue: process.env.SMP_PROXY_QUEUE || "proxy-jobs",
};

// Collected rather than thrown: `health` has to answer even when the
// workstation has never been configured.
export const configErrors = [];
if (!config.mediaAccount) {
  configErrors.push("SMP_MEDIA_ACCOUNT is not set");
}

const credential = new DefaultAzureCredential();

const blobEndpoint = `https://${config.mediaAccount}.blob.core.windows.net`;
const queueEndpoint = `https://${config.mediaAccount}.queue.core.windows.net`;

const blobs = config.mediaAccount
  ? new BlobServiceClient(blobEndpoint, credential)
  : null;
const queues = config.mediaAccount
  ? new QueueServiceClient(queueEndpoint, credential)
  : null;

function requireClients() {
  if (!blobs || !queues) {
    throw new Error(configErrors.join("; ") || "uploader is not configured");
  }
}

// Content types the studio shoots. Anything else goes up as a plain stream —
// the proxy generator sniffs the header itself and does not trust this.
const CONTENT_TYPES = {
  ".arw": "image/x-sony-arw",
  ".cr3": "image/x-canon-cr3",
  ".dng": "image/x-adobe-dng",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".mov": "video/quicktime",
  ".mp4": "video/mp4",
  ".tif": "image/tiff",
  ".tiff": "image/tiff",
};

export function contentTypeFor(filePath) {
  return CONTENT_TYPES[path.extname(filePath).toLowerCase()] ?? "application/octet-stream";
}

// One shoot file into intake/<shootId>/<basename>. Event Grid turns the write
// into a proxy job; nothing else here has to know about that.
export async function uploadShootFile(shootId, filePath) {
  requireClients();
  const blobName = `${shootId}/${path.basename(filePath)}`;
  const container = blobs.getContainerClient(config.intakeContainer);
  const block = container.getBlockBlobClient(blobName);
  const body = await readFile(filePath);
  const { size } = await stat(filePath);

  await block.uploadData(body, {
    blobHTTPHeaders: { blobContentType: contentTypeFor(filePath) },
    metadata: { shoot: shootId },
  });

  return { blobName, bytes: size };
}

// Cheapest call that proves the blob endpoint answers and the operator holds a
// data role on it. Reads one page and stops.
export async function pingContainer(containerName) {
  requireClients();
  const container = blobs.getContainerClient(containerName);
  const page = await container
    .listBlobsFlat()
    .byPage({ maxPageSize: 1 })
    .next();
  return { blobs: page.value?.segment?.blobItems?.length ?? 0 };
}

// Backlog the proxy generator has not drained yet. Approximate by design —
// the queue service does not promise an exact count.
export async function proxyQueueDepth() {
  requireClients();
  const queue = queues.getQueueClient(config.proxyQueue);
  const props = await queue.getProperties();
  return props.approximateMessagesCount ?? 0;
}

// Proves the operator's sign-in is being accepted by Entra ID, independently of
// any particular resource role.
export async function pingIdentity() {
  const token = await credential.getToken("https://storage.azure.com/.default");
  if (!token?.token) throw new Error("no token returned");
}

// Per-service ok/fail, one entry per Azure service this module touches. Never
// raises: a caller renders whatever comes back.
export async function checkServices() {
  const checks = {
    identity: () => pingIdentity(),
    "blob:intake": () => pingContainer(config.intakeContainer),
    "blob:masters": () => pingContainer(config.mastersContainer),
    "queue:proxy-jobs": () => proxyQueueDepth(),
  };

  const results = {};
  for (const [name, run] of Object.entries(checks)) {
    try {
      const detail = await run();
      results[name] = { ok: true, detail: detail ?? null };
    } catch (err) {
      results[name] = { ok: false, error: String(err?.message ?? err).slice(0, 300) };
    }
  }
  return results;
}
