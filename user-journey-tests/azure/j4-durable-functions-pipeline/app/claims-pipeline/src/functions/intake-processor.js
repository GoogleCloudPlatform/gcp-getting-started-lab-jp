// intake-processor — first stop for a scanned claim.
//
// Event Grid watches the claims storage account and writes one blob-created
// notification per scan into the claim-intake queue. This function drains that
// queue, pulls the claim reference, branch and amount out of the file name the
// branch scanners produce, and hands the result to the review desk.
//
// File name contract, set by the scanners at each branch from the cover-sheet
// barcode:
//   <claim-ref>_<branch>_<amount-in-yen>.pdf
//   DFP-2026-0417_EAST_480000.pdf

const { app } = require("@azure/functions");
const clients = require("../lib/azureClients");

const CLAIM_FILE_PATTERN = /^(DFP-\d{4}-\d{4})_([A-Z]+)_(\d+)\.pdf$/i;

// Event Grid queue messages arrive as the event JSON. Older messages written
// before the 2025 storage SDK bump are base64, so try both.
function parseNotification(message) {
  if (message && typeof message === "object") {
    return message;
  }
  const text = String(message ?? "");
  try {
    return JSON.parse(text);
  } catch {
    return JSON.parse(Buffer.from(text, "base64").toString("utf8"));
  }
}

// "/blobServices/default/containers/intake/blobs/DFP-2026-0417_EAST_480000.pdf"
function blobNameFromSubject(subject) {
  const marker = "/blobs/";
  const at = String(subject ?? "").indexOf(marker);
  return at === -1 ? "" : subject.slice(at + marker.length);
}

function toClaim(event) {
  const blobName = blobNameFromSubject(event.subject);
  const fileName = blobName.split("/").pop() || "";
  const matched = CLAIM_FILE_PATTERN.exec(fileName);
  if (!matched) {
    return null;
  }
  const eventTime = event.eventTime ? new Date(event.eventTime) : new Date();
  return {
    claimRef: matched[1].toUpperCase(),
    branch: matched[2].toUpperCase(),
    amountJpy: Number(matched[3]),
    receivedDate: eventTime.toISOString().slice(0, 10),
    documentUrl: (event.data && event.data.url) || "",
    state: "received",
  };
}

app.storageQueue("intake-processor", {
  queueName: "%CLAIMS_INTAKE_QUEUE%",
  connection: "CLAIMS_STORAGE",
  handler: async (message, context) => {
    const event = parseNotification(message);
    const claim = toClaim(event);

    if (!claim) {
      // Anything the scanners did not name to the contract is left for the
      // branch to re-upload. There is no operator alert on this path.
      context.warn(`unrecognised intake file: ${event.subject ?? "(no subject)"}`);
      return;
    }

    context.log(
      `claim ${claim.claimRef} from ${claim.branch}, ${claim.amountJpy} JPY, received ${claim.receivedDate}`,
    );
    await clients.sendClaimForReview(claim);
  },
});
