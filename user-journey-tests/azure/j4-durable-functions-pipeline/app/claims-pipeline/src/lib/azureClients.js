// azureClients.js — the single funnel for EVERY Azure SDK call the claims
// pipeline makes. Keep any new Azure call in this module so call sites stay
// grep-able from one place.
//
// Intended GCP mapping (planning notes from the 2026 estimate, per service):
//   Blob container intake               -> Cloud Storage
//   Event Grid system topic             -> Eventarc
//   Service Bus queue claims-review     -> open; depends on what we do about
//                                          delivery ordering and the DLQ
//   Storage queue claim-intake          -> open; same call as claims-review
//   Table Storage table claimstate      -> open; nothing over there is a
//                                          like-for-like, see the key scheme
//
// Credentials: nothing is read from a file and nothing lives in this
// repository. The Functions host resolves CLAIMS_STORAGE and SERVICE_BUS from
// app settings, which the template populates from the deployed resources.

const { TableClient } = require("@azure/data-tables");
const { ServiceBusClient } = require("@azure/service-bus");

const CLAIM_STATE_TABLE = process.env.CLAIM_STATE_TABLE || "claimstate";
const CLAIMS_REVIEW_QUEUE = process.env.CLAIMS_REVIEW_QUEUE || "claims-review";

// Clients are built on first use rather than at module load, so requiring this
// file in a shell with no app settings does not throw.
let tableClient = null;
let serviceBusClient = null;
let reviewSender = null;

function storageConnectionString() {
  const value = process.env.CLAIMS_STORAGE;
  if (!value) {
    throw new Error("CLAIMS_STORAGE app setting is not populated");
  }
  return value;
}

function serviceBusConnectionString() {
  const value = process.env.SERVICE_BUS;
  if (!value) {
    throw new Error("SERVICE_BUS app setting is not populated");
  }
  return value;
}

function claimStateTable() {
  if (!tableClient) {
    tableClient = TableClient.fromConnectionString(
      storageConnectionString(),
      CLAIM_STATE_TABLE,
      { allowInsecureConnection: false },
    );
  }
  return tableClient;
}

function reviewQueueSender() {
  if (!reviewSender) {
    serviceBusClient = new ServiceBusClient(serviceBusConnectionString());
    reviewSender = serviceBusClient.createSender(CLAIMS_REVIEW_QUEUE);
  }
  return reviewSender;
}

// Hand a parsed claim to the review desk. One message per claim; the review
// router is the only consumer.
async function sendClaimForReview(claim) {
  await reviewQueueSender().sendMessages({
    contentType: "application/json",
    messageId: claim.claimRef,
    body: claim,
  });
}

// Claim state is one row per claim per state change. PartitionKey is the
// receipt date so a day reads back as a single partition scan. RowKey is the
// claim reference, which the branch scanners guarantee is unique; the approval
// steps hang off it as `<claim-ref>#<step>` so each sign-off keeps its own row
// instead of overwriting the one before it.
async function putClaimState(row) {
  const entity = {
    partitionKey: row.receivedDate,
    rowKey: row.stateKey ? `${row.claimRef}#${row.stateKey}` : row.claimRef,
    claimRef: row.claimRef,
    branch: row.branch,
    amountJpy: row.amountJpy,
    state: row.state,
    updatedAt: new Date().toISOString(),
  };
  // Merge would otherwise blank the document URL on rows that do not carry one.
  if (row.documentUrl) {
    entity.documentUrl = row.documentUrl;
  }
  await claimStateTable().upsertEntity(entity, "Merge");
}

// Every row touched on or after the given receipt date, oldest partition first.
async function listClaimStatesFrom(receivedDate) {
  const rows = [];
  const results = claimStateTable().listEntities({
    queryOptions: { filter: `PartitionKey ge '${receivedDate}'` },
  });
  for await (const row of results) {
    rows.push(row);
  }
  return rows;
}

// Called from the reconciliation pass, which runs to completion rather than
// staying warm.
async function closeClients() {
  if (reviewSender) {
    await reviewSender.close();
    reviewSender = null;
  }
  if (serviceBusClient) {
    await serviceBusClient.close();
    serviceBusClient = null;
  }
}

module.exports = {
  CLAIM_STATE_TABLE,
  CLAIMS_REVIEW_QUEUE,
  sendClaimForReview,
  putClaimState,
  listClaimStatesFrom,
  closeClients,
};
