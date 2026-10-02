// notifier — consumes parcel scan events and stamps the parcel document so the
// public tracking page can say when the customer was last told something.
//
// Every Azure call goes through azureClients.mjs; nothing in this file imports
// an Azure SDK directly.
//
// The loop locks ONE parcel's session at a time, drains it, releases it, and
// moves on. That is what keeps two pods from writing the same parcel document
// at once — the queue does the mutual exclusion, so this worker holds no locks
// of its own and can be scaled by adding pods.
import http from "node:http";

import {
  acceptNextParcelSession,
  close,
  completeScan,
  config,
  getParcel,
  pingCosmos,
  pingIdentity,
  receiveScans,
  rejectScan,
  upsertParcel,
} from "./azureClients.mjs";

const PORT = Number(process.env.PORT || 8080);
const IDLE_SLEEP_MS = Number(process.env.IDLE_SLEEP_MS || 2_000);
// tracking-api's in-cluster address. Not an Azure call, so it does not belong
// in the Azure funnel; it is a plain HTTP hop to the other service.
const TRACKING_API_URL = (process.env.TRACKING_API_URL || "").replace(/\/$/, "");
const MAX_BACKOFF_MS = 30_000;
// The kubelet's probes call /health on a short budget, so the checks behind it
// get a hard deadline of their own. Reporting "timed out" is useful; hanging
// gets the pod restarted.
const PING_BUDGET_MS = 2_000;

const state = {
  startedAt: new Date().toISOString(),
  lastSessionAt: null,
  sessionsHandled: 0,
  scansApplied: 0,
  scansRejected: 0,
  lastError: null,
};

let running = true;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Races a promise against a deadline. The timer is unref'd so a pending check
// never keeps the process alive on its own.
function withDeadline(promise, ms) {
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timed out after ${ms}ms`)), ms);
    timer.unref?.();
  });
  return Promise.race([promise, deadline]).finally(() => clearTimeout(timer));
}

// ---- one parcel's worth of scans -------------------------------------------

async function applyScan(parcelId, event) {
  const parcel = (await getParcel(parcelId)) ?? {
    id: parcelId,
    parcelId,
    origin: event.location ?? "unknown",
    destination: event.destination ?? "unknown",
    status: event.status ?? "accepted",
    scans: [],
  };

  parcel.scans = Array.isArray(parcel.scans) ? parcel.scans : [];
  const at = event.at ?? new Date().toISOString();
  const alreadyRecorded = parcel.scans.some(
    (scan) => scan.at === at && scan.status === event.status,
  );
  if (!alreadyRecorded) {
    parcel.scans.push({ at, location: event.location, status: event.status });
  }

  parcel.status = event.status ?? parcel.status;
  parcel.updatedAt = at;
  parcel.notifiedAt = new Date().toISOString();

  await upsertParcel(parcel);
}

async function drainSession(receiver) {
  const parcelId = receiver.sessionId;
  let handled = 0;

  for (;;) {
    const messages = await receiveScans(receiver);
    if (messages.length === 0) break;

    for (const message of messages) {
      let event;
      try {
        event = typeof message.body === "string" ? JSON.parse(message.body) : message.body;
      } catch (err) {
        await rejectScan(receiver, message, `body is not JSON: ${err.message}`);
        state.scansRejected += 1;
        continue;
      }

      if (!event || typeof event !== "object" || !event.parcelId) {
        await rejectScan(receiver, message, "event has no parcelId");
        state.scansRejected += 1;
        continue;
      }

      await applyScan(parcelId, event);
      await completeScan(receiver, message);
      state.scansApplied += 1;
      handled += 1;
    }
  }

  return handled;
}

async function loop() {
  let backoffMs = IDLE_SLEEP_MS;

  while (running) {
    let receiver = null;
    try {
      receiver = await acceptNextParcelSession();
      if (!receiver) {
        await sleep(IDLE_SLEEP_MS);
        continue;
      }

      state.lastSessionAt = new Date().toISOString();
      const handled = await drainSession(receiver);
      state.sessionsHandled += 1;
      backoffMs = IDLE_SLEEP_MS;
      console.log(
        JSON.stringify({
          event: "session.drained",
          parcelId: receiver.sessionId,
          scans: handled,
        }),
      );
    } catch (err) {
      state.lastError = `${err.code ?? err.name ?? "error"}: ${err.message}`;
      // Back off while the failure persists. Without this, an unreachable
      // namespace produces a tight retry loop and buries every other log line.
      console.error(
        JSON.stringify({ event: "session.failed", error: state.lastError, retryInMs: backoffMs }),
      );
      await sleep(backoffMs);
      backoffMs = Math.min(backoffMs * 2, MAX_BACKOFF_MS);
    } finally {
      if (receiver) {
        // A session left open is a parcel no other pod can touch until the
        // lock expires, so close it even when the drain threw.
        await receiver.close().catch(() => {});
      }
    }
  }
}

// ---- health edge -------------------------------------------------------------
// No Service points at this port. It exists for the readiness and liveness
// probes, and for anyone debugging the worker with a port-forward.

// The other half of the pipeline. If tracking-api is down, scans still get
// applied — this worker writes to Cosmos DB directly — but the tracking page
// nobody can load is the thing the depot actually phones about, so it is worth
// reporting here.
async function pingTrackingApi() {
  if (!TRACKING_API_URL) throw new Error("TRACKING_API_URL is not set");
  const response = await fetch(`${TRACKING_API_URL}/health`);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
}

async function healthBody() {
  const probe = (fn) =>
    withDeadline(fn(), PING_BUDGET_MS).then(
      () => "ok",
      (err) => `fail: ${err.message}`.slice(0, 160),
    );
  const [cosmos, identity, trackingApi] = await Promise.all([
    probe(pingCosmos),
    probe(pingIdentity),
    probe(pingTrackingApi),
  ]);
  const checks = { cosmos, identity, "tracking-api": trackingApi };
  const degraded = Object.values(checks).some((v) => v !== "ok");
  return {
    service: "notifier",
    status: degraded ? "degraded" : "ok",
    queue: config.serviceBusQueue,
    dependencies: checks,
    ...state,
  };
}

const healthServer = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    healthBody().then((body) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(body));
    });
    return;
  }
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

healthServer.listen(PORT, () => {
  console.log(
    JSON.stringify({ event: "notifier.started", port: PORT, queue: config.serviceBusQueue }),
  );
});

// ---- shutdown ----------------------------------------------------------------

async function shutdown(signal) {
  console.log(JSON.stringify({ event: "notifier.stopping", signal }));
  running = false;
  healthServer.close();
  await close().catch(() => {});
  process.exit(0);
}

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

await loop();
