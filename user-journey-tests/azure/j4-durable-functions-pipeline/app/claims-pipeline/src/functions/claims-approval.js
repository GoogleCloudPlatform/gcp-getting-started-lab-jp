// claims-approval — the sign-off chain for a claim over the escalation
// threshold.
//
// Two steps, in order, because the policy wording requires a desk review before
// a senior adjuster can sign: an internal desk review, then senior sign-off.
// Each step writes its own claim state row, so the table is the audit trail the
// 2024 compliance response promised.
//
// The chain is short today. It was written to grow — the original design had a
// fraud-screening step and a broker-notification step after sign-off — and the
// state machine is what makes adding them cheap.

const df = require("durable-functions");
const clients = require("../lib/azureClients");

const APPROVAL_STEPS = ["desk-review", "senior-sign-off"];

df.app.orchestration("approvalOrchestrator", function* (context) {
  const claim = context.df.getInput();
  const completed = [];

  for (const step of APPROVAL_STEPS) {
    const result = yield context.df.callActivity("recordApprovalStep", {
      receivedDate: claim.receivedDate,
      claimRef: claim.claimRef,
      branch: claim.branch,
      amountJpy: claim.amountJpy,
      step,
    });
    completed.push(result);
  }

  return {
    claimRef: claim.claimRef,
    completed,
  };
});

df.app.activity("recordApprovalStep", {
  handler: async (input, context) => {
    await clients.putClaimState({
      receivedDate: input.receivedDate,
      claimRef: input.claimRef,
      branch: input.branch,
      amountJpy: input.amountJpy,
      stateKey: input.step,
      state: `approval:${input.step}`,
    });
    context.log(`claim ${input.claimRef} completed approval step ${input.step}`);
    return input.step;
  },
});
