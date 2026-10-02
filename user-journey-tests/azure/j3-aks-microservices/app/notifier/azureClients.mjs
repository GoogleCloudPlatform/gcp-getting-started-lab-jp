// azureClients.mjs — the single funnel for EVERY Azure SDK call notifier makes.
// Keep any new Azure call in this module so the call sites stay in one place.
//
// Where each of these is expected to land on Google Cloud, per service:
//   Cosmos DB (SQL API) tracking/parcels    -> Firestore
//   Service Bus queue parcel-events         -> Pub/Sub
//   Entra federated pod credential          -> Workload Identity Federation for GKE
//
// Credentials: none are configured here, and none exist in the container. The
// pod's service account is federated to a user-assigned identity in Entra ID,
// and DefaultAzureCredential picks that up from the projected token without
// being told about it.
import { DefaultAzureCredential } from "@azure/identity";
import { ServiceBusClient } from "@azure/service-bus";
import { CosmosClient } from "@azure/cosmos";

export const config = {
  cosmosEndpoint: process.env.COSMOS_ENDPOINT ?? "",
  cosmosDatabase: process.env.COSMOS_DATABASE || "tracking",
  cosmosContainer: process.env.COSMOS_CONTAINER || "parcels",
  serviceBusNamespace: process.env.SERVICEBUS_NAMESPACE ?? "",
  serviceBusQueue: process.env.SERVICEBUS_QUEUE || "parcel-events",
};

if (!config.cosmosEndpoint) throw new Error("COSMOS_ENDPOINT is not set");
if (!config.serviceBusNamespace) throw new Error("SERVICEBUS_NAMESPACE is not set");

const credential = new DefaultAzureCredential();

const serviceBus = new ServiceBusClient(config.serviceBusNamespace, credential);

const cosmos = new CosmosClient({
  endpoint: config.cosmosEndpoint,
  aadCredentials: credential,
});
const parcels = cosmos
  .database(config.cosmosDatabase)
  .container(config.cosmosContainer);

// Lock the next parcel that has unread scans. Returns a session receiver, or
// null when no session is available right now — which is the ordinary state
// overnight, not an error.
export async function acceptNextParcelSession({ lockRenewalMs = 120_000 } = {}) {
  try {
    return await serviceBus.acceptNextSession(config.serviceBusQueue, {
      maxAutoLockRenewalDurationInMs: lockRenewalMs,
    });
  } catch (err) {
    if (err?.code === "ServiceTimeout" || err?.code === "SessionCannotBeLocked") {
      return null;
    }
    throw err;
  }
}

// Read a batch from the locked session. All of these belong to one parcel.
export async function receiveScans(sessionReceiver, max = 10, waitMs = 5_000) {
  return sessionReceiver.receiveMessages(max, { maxWaitTimeInMs: waitMs });
}

export async function completeScan(sessionReceiver, message) {
  await sessionReceiver.completeMessage(message);
}

// Five delivery attempts are configured on the queue; a message this worker
// cannot parse would burn all five and land here anyway, so send it straight
// across with a reason attached.
export async function rejectScan(sessionReceiver, message, reason) {
  await sessionReceiver.deadLetterMessage(message, {
    deadLetterReason: "UnprocessableScan",
    deadLetterErrorDescription: String(reason).slice(0, 400),
  });
}

export async function getParcel(parcelId) {
  try {
    const { resource } = await parcels.item(parcelId, parcelId).read();
    return resource ?? null;
  } catch (err) {
    if (err?.code === 404) return null;
    throw err;
  }
}

export async function upsertParcel(parcel) {
  await parcels.items.upsert(parcel);
}

// Cheapest call that proves both the endpoint and the data-plane role work.
export async function pingCosmos() {
  await parcels.read();
}

// Proves the pod's federated credential is being accepted by Entra ID,
// independently of any particular resource role.
export async function pingIdentity() {
  const token = await credential.getToken("https://management.azure.com/.default");
  if (!token?.token) throw new Error("no token returned");
}

export async function close() {
  await serviceBus.close();
}
