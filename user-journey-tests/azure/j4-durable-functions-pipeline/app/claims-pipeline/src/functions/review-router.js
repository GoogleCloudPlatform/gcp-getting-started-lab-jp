// review-router — turns a parsed claim into a claim state row, and decides
// whether the desk can settle it or the approval chain has to run.
//
// Anything under CLAIM_ESCALATION_THRESHOLD_JPY is routed straight to the desk
// queue that adjusters work from. At or above it, the approval chain starts and
// the row is parked in `awaiting-approval` until the chain writes its own rows.

const { app } = require("@azure/functions");
const df = require("durable-functions");
const clients = require("../lib/azureClients");

const durableClient = df.input.durableClient();

const ESCALATION_THRESHOLD_JPY = Number(
  process.env.CLAIM_ESCALATION_THRESHOLD_JPY || "500000",
);

function parseClaim(message) {
  if (message && typeof message === "object") {
    return message;
  }
  return JSON.parse(String(message ?? ""));
}

app.serviceBusQueue("review-router", {
  queueName: "%CLAIMS_REVIEW_QUEUE%",
  connection: "SERVICE_BUS",
  extraInputs: [durableClient],
  handler: async (message, context) => {
    const claim = parseClaim(message);
    const escalate = Number(claim.amountJpy) >= ESCALATION_THRESHOLD_JPY;

    await clients.putClaimState({
      receivedDate: claim.receivedDate,
      claimRef: claim.claimRef,
      branch: claim.branch,
      amountJpy: Number(claim.amountJpy),
      documentUrl: claim.documentUrl,
      state: escalate ? "awaiting-approval" : "with-adjuster",
    });

    if (!escalate) {
      context.log(`claim ${claim.claimRef} routed to the adjuster desk`);
      return;
    }

    const durable = df.getClient(context);
    const instanceId = await durable.startNew("approvalOrchestrator", {
      instanceId: `approval-${claim.claimRef}`,
      input: {
        claimRef: claim.claimRef,
        receivedDate: claim.receivedDate,
        branch: claim.branch,
        amountJpy: Number(claim.amountJpy),
      },
    });
    context.log(
      `claim ${claim.claimRef} is over the threshold — approval chain ${instanceId} started`,
    );
  },
});
