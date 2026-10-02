// awsClients.mjs — the single funnel for EVERY AWS SDK call booking-api makes.
// Keep any new AWS call in this module so call sites stay grep-able.
//
// Intended GCP mapping (planning notes, per service):
//   DynamoDB table ems-bookings          -> Firestore
//   EKS cluster ems-cluster              -> GKE
//   IRSA pod credentials                 -> Workload Identity
//   ECR image registries                 -> Artifact Registry
//   NLB via Service type=LoadBalancer    -> GKE LoadBalancer Service
//
// Credentials: none are configured here on purpose. In-cluster, the pod's
// service account annotation (IRSA) injects web-identity credentials and the
// SDK's default provider chain picks them up.
import {
  DynamoDBClient,
  DescribeTableCommand,
} from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
} from "@aws-sdk/lib-dynamodb";
import { STSClient, GetCallerIdentityCommand } from "@aws-sdk/client-sts";

const REGION = process.env.AWS_REGION || "ap-northeast-1";
export const TABLE_NAME = process.env.TABLE_NAME || "ems-bookings";

const dynamodb = new DynamoDBClient({ region: REGION });
const documents = DynamoDBDocumentClient.from(dynamodb);
const sts = new STSClient({ region: REGION });

// Store one booking record keyed by booking_id.
export async function putBooking(booking) {
  await documents.send(new PutCommand({ TableName: TABLE_NAME, Item: booking }));
}

// Load one booking by id; returns null when absent.
export async function getBooking(bookingId) {
  const out = await documents.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { booking_id: bookingId } }),
  );
  return out.Item ?? null;
}

// Cheap persistence health probe; returns the table status string.
export async function describeBookingsTable() {
  const out = await dynamodb.send(
    new DescribeTableCommand({ TableName: TABLE_NAME }),
  );
  return out.Table?.TableStatus ?? "UNKNOWN";
}

// Who is the pod authenticated as? Proves the pod-identity wiring works.
export async function callerIdentity() {
  const out = await sts.send(new GetCallerIdentityCommand({}));
  return { account: out.Account, arn: out.Arn };
}
