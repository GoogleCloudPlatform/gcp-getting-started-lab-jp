// server.mjs — booking-api: the public edge and booking service of the equipment marketplace (fictional).
//
// Owns bookings end to end and, acting as the gateway, proxies read-only
// catalog routes to catalog-api so a single load-balanced endpoint serves
// the whole marketplace API.
//
// Routes:
//   POST /bookings          {item_id, days} -> 201 with the stored booking
//   GET  /bookings/:id      stored booking or 404
//   GET  /catalog           proxied to catalog-api
//   GET  /catalog/:id       proxied to catalog-api
//   GET  /health            dependency substatus, always HTTP 200
//   GET  /admin/aws-check   pod-identity parity dashboard
import express from "express";
import { randomUUID } from "node:crypto";

import * as cloud from "./awsClients.mjs";

const app = express();
app.use(express.json());

const PORT = Number(process.env.PORT || 8080);
const CATALOG_URL = (process.env.CATALOG_URL || "http://catalog-api:8080").replace(/\/+$/, "");

// ---- gateway: catalog reads pass through this edge ---------------------------

async function proxyCatalog(res, path) {
  try {
    const upstream = await fetch(`${CATALOG_URL}${path}`);
    const body = await upstream.text();
    res.status(upstream.status).type("application/json").send(body);
  } catch (err) {
    res.status(502).json({ error: "catalog unavailable", detail: String(err?.message ?? err) });
  }
}

app.get("/catalog", (_req, res) => proxyCatalog(res, "/catalog"));
app.get("/catalog/:id", (req, res) =>
  proxyCatalog(res, `/catalog/${encodeURIComponent(req.params.id)}`));

// ---- bookings -----------------------------------------------------------------

app.post("/bookings", async (req, res) => {
  const itemId = Number(req.body?.item_id);
  const days = Number(req.body?.days);
  if (!Number.isInteger(itemId) || itemId < 1) {
    return res.status(400).json({ error: "item_id must be a positive integer" });
  }
  if (!Number.isInteger(days) || days < 1 || days > 90) {
    return res.status(400).json({ error: "days must be an integer between 1 and 90" });
  }

  // The item must exist in the catalog before we confirm a booking.
  let item;
  try {
    const upstream = await fetch(`${CATALOG_URL}/catalog/${itemId}`);
    if (upstream.status === 404) {
      return res.status(422).json({ error: `unknown item_id ${itemId}` });
    }
    if (!upstream.ok) {
      return res.status(502).json({ error: `catalog returned HTTP ${upstream.status}` });
    }
    item = await upstream.json();
  } catch (err) {
    return res.status(502).json({ error: "catalog unavailable", detail: String(err?.message ?? err) });
  }

  const booking = {
    booking_id: randomUUID(),
    item_id: itemId,
    item_name: item.name,
    days,
    total_jpy: item.daily_rate_jpy * days,
    status: "confirmed",
    created_at: new Date().toISOString(),
  };
  try {
    await cloud.putBooking(booking);
  } catch (err) {
    console.error("putBooking failed:", err);
    return res.status(500).json({ error: "failed to store booking" });
  }
  return res.status(201).json(booking);
});

app.get("/bookings/:id", async (req, res) => {
  try {
    const booking = await cloud.getBooking(req.params.id);
    if (!booking) {
      return res.status(404).json({ error: "booking not found" });
    }
    return res.json(booking);
  } catch (err) {
    console.error("getBooking failed:", err);
    return res.status(500).json({ error: "failed to load booking" });
  }
});

// ---- health + parity dashboard --------------------------------------------------

// Substatus for each hard dependency; never raises, always HTTP 200.
app.get("/health", async (_req, res) => {
  const checks = {};
  try {
    const tableStatus = await cloud.describeBookingsTable();
    checks.dynamodb = tableStatus === "ACTIVE" ? "ok" : `table status ${tableStatus}`;
  } catch (err) {
    checks.dynamodb = `error: ${err?.name ?? "unknown"}`;
  }
  try {
    const upstream = await fetch(`${CATALOG_URL}/health`);
    checks.catalog = upstream.ok ? "ok" : `HTTP ${upstream.status}`;
  } catch {
    checks.catalog = "unreachable";
  }
  const healthy = Object.values(checks).every((value) => value === "ok");
  res.status(200).json({ status: healthy ? "ok" : "degraded", service: "booking-api", checks });
});

// Ops dashboard: pings every SDK-touched service through the funnel module.
// After a re-platform the same page becomes the parity check.
app.get("/admin/aws-check", async (_req, res) => {
  const checks = {};
  let accountSuffix = null;
  try {
    const tableStatus = await cloud.describeBookingsTable();
    checks.dynamodb = tableStatus === "ACTIVE" ? "ok" : `table status ${tableStatus}`;
  } catch (err) {
    checks.dynamodb = `error: ${err?.name ?? String(err)}`;
  }
  try {
    const identity = await cloud.callerIdentity();
    checks.sts = "ok";
    accountSuffix = String(identity.account).slice(-4);
  } catch (err) {
    checks.sts = `error: ${err?.name ?? String(err)}`;
  }
  const overall = Object.values(checks).every((value) => value === "ok") ? "ok" : "fail";
  res.status(200).json({ overall, checks, account_suffix: accountSuffix });
});

app.listen(PORT, () => {
  console.log(
    `booking-api listening on :${PORT} (catalog: ${CATALOG_URL}, table: ${cloud.TABLE_NAME})`,
  );
});
