// nightly-reconcile — cross-checks claim state against the broker's overnight
// settlement file.
//
// Written in early 2025 for the reconciliation work the broker asked for after
// the Q4 close. It reads every claim state row from the last
// RECONCILE_LOOKBACK_DAYS days, groups them by branch, and reports the ones
// still sitting in an intermediate state past the service-level window.
//
// The comparison against the broker's own settlement extract is the half that
// was never written: the extract arrives as a fixed-width file on an SFTP drop
// nobody has credentials for any more.

const { app } = require("@azure/functions");
const clients = require("../lib/azureClients");

const LOOKBACK_DAYS = Number(process.env.RECONCILE_LOOKBACK_DAYS || "45");
const OPEN_STATES = new Set(["received", "awaiting-approval", "with-adjuster"]);

function lookbackDate(days) {
  const from = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  return from.toISOString().slice(0, 10);
}

app.timer("nightly-reconcile", {
  schedule: "0 30 18 * * *",
  handler: async (timer, context) => {
    const from = lookbackDate(LOOKBACK_DAYS);
    const rows = await clients.listClaimStatesFrom(from);

    const openByBranch = new Map();
    for (const row of rows) {
      if (!OPEN_STATES.has(row.state)) {
        continue;
      }
      const branch = row.branch || "UNKNOWN";
      openByBranch.set(branch, (openByBranch.get(branch) || 0) + 1);
    }

    for (const [branch, count] of [...openByBranch.entries()].sort()) {
      context.log(`${branch}: ${count} claims still open since ${from}`);
    }
    context.log(
      `reconciliation pass read ${rows.length} rows from ${from}; past due: ${timer.isPastDue}`,
    );

    await clients.closeClients();
  },
});
