// awsClients.mjs (GCP port) — drop-in replacement for the journey's funnel.
// Same module name and exports, so server.mjs ships byte-identical; only this
// file and package.json change in the migrated image.
//
// Mapping implemented:
//   DynamoDB ems-bookings   -> Firestore (Native), NAMED database ems-bookings
//   IRSA pod credentials    -> Workload Identity (KSA booking-api -> GSA)
//   STS GetCallerIdentity   -> GKE metadata server (SA email + project id)
import { Firestore } from "@google-cloud/firestore";

export const TABLE_NAME = process.env.TABLE_NAME || "ems-bookings";
const FIRESTORE_DB = process.env.FIRESTORE_DB || "ems-bookings";

const firestore = new Firestore({
  projectId: process.env.GCP_PROJECT || undefined,
  databaseId: FIRESTORE_DB,
});
const bookings = firestore.collection(TABLE_NAME);

// Store one booking record keyed by booking_id.
export async function putBooking(booking) {
  await bookings.doc(booking.booking_id).set(booking);
}

// Load one booking by id; returns null when absent.
export async function getBooking(bookingId) {
  const snap = await bookings.doc(bookingId).get();
  return snap.exists ? snap.data() : null;
}

// Cheap persistence health probe; "ACTIVE" keeps the health contract that
// server.mjs expects from the DynamoDB original.
export async function describeBookingsTable() {
  await bookings.limit(1).get();
  return "ACTIVE";
}

async function metadata(path) {
  const res = await fetch(`http://metadata.google.internal/computeMetadata/v1/${path}`, {
    headers: { "Metadata-Flavor": "Google" },
  });
  if (!res.ok) throw new Error(`metadata HTTP ${res.status}`);
  return res.text();
}

// Who is the pod authenticated as? Proves Workload Identity wiring, the way
// the original proved IRSA. account = project id, arn = the GSA email.
export async function callerIdentity() {
  const [email, project] = await Promise.all([
    metadata("instance/service-accounts/default/email"),
    metadata("project/project-id"),
  ]);
  return { account: project, arn: email };
}
