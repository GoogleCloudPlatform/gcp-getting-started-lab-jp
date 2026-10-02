#!/usr/bin/env node
// GCP pricing lookup against the Cloud Billing Catalog API (live data, no cache).
// Auth priority: gcloud ADC -> gcloud user credentials -> API key.
// Zero dependencies; requires Node >= 18.
//
// Usage:
//   gcp-pricing services [--filter <regex>]
//   gcp-pricing skus --service <serviceId|displayName> [--region <region>]
//                    [--filter <regex>] [--currency <ISO4217>] [--limit <N>]

import { createAuthProvider, SETUP_HELP } from "./lib/gcp-auth.mjs";

const API_BASE = "https://cloudbilling.googleapis.com/v1";
const SERVICE_ID_RE = /^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/i;
const MAX_PAGES = 25; // 5000 items/page; hard stop against runaway pagination

const USAGE = `Usage:
  gcp-pricing services [--filter <regex>]
      List Cloud Billing Catalog services (serviceId + displayName).

  gcp-pricing skus --service <serviceId|displayName> [options]
      List SKUs with live unit prices for one service.
      --region <region>     only SKUs whose serviceRegions contain <region>
                            (multi-region/global SKUs use e.g. "global", "us", "europe")
      --filter <regex>      case-insensitive regex on the SKU description
      --currency <ISO4217>  currency for prices (default USD)
      --limit <N>           max SKUs to print (default 50; 0 = no limit)

Output is JSON on stdout (includes retrieved_at, auth_mode, and source_url for
pricing provenance). Auth: gcloud ADC first, then gcloud user credentials, then
an API key from GCP_PRICING_API_KEY / DK_API_KEY / GOOGLE_API_KEY.`;

const auth = createAuthProvider({
  apiKeyEnvVars: ["GCP_PRICING_API_KEY", "DK_API_KEY", "GOOGLE_API_KEY"],
});

function fail(message, code = 1) {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (command === "--help" || command === "-h") return { command: "help" };
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (arg === "--help" || arg === "-h") return { command: "help" };
    if (!arg.startsWith("--")) fail(`Unexpected argument: ${arg}\n\n${USAGE}`, 2);
    const key = arg.slice(2);
    const value = rest[++i];
    if (value === undefined) fail(`Missing value for --${key}\n\n${USAGE}`, 2);
    opts[key] = value;
  }
  return { command, opts };
}

async function apiGet(url) {
  let res = await fetch(url, { headers: await auth.headers() });
  if (res.status === 401 || res.status === 403) {
    auth.invalidate();
    res = await fetch(url, { headers: await auth.headers() });
  }
  if ((res.status === 401 || res.status === 403) && auth.mode() !== "api-key" && auth.demoteToApiKey()) {
    res = await fetch(url, { headers: await auth.headers() });
  }
  if (!res.ok) {
    const body = await res.text();
    let detail = body.slice(0, 2000);
    try {
      detail = JSON.stringify(JSON.parse(body).error, null, 2);
    } catch {
      // keep raw body
    }
    fail(`Cloud Billing Catalog API error (HTTP ${res.status}) for ${url}:\n${detail}`);
  }
  return res.json();
}

async function fetchAllPages(path, params, itemsKey) {
  const items = [];
  let pageToken = null;
  let firstUrl = null;
  for (let page = 0; page < MAX_PAGES; page++) {
    const url = new URL(`${API_BASE}${path}`);
    url.searchParams.set("pageSize", "5000");
    for (const [key, value] of Object.entries(params)) {
      if (value) url.searchParams.set(key, value);
    }
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    firstUrl ??= url.toString();
    const data = await apiGet(url.toString());
    items.push(...(data[itemsKey] ?? []));
    pageToken = data.nextPageToken;
    if (!pageToken) return { items, sourceUrl: firstUrl };
  }
  fail(`Aborted: more than ${MAX_PAGES} pages from ${API_BASE}${path}; narrow the query.`);
}

// Money proto: int64 units (a string in REST JSON) + int32 nanos.
function moneyToDecimal(money = {}) {
  const units = BigInt(money.units ?? 0);
  const nanos = money.nanos ?? 0;
  const negative = units < 0n || nanos < 0;
  const absUnits = units < 0n ? -units : units;
  const frac = String(Math.abs(nanos)).padStart(9, "0").replace(/0+$/, "");
  return `${negative ? "-" : ""}${absUnits}${frac ? `.${frac}` : ""}`;
}

function compileRegex(pattern) {
  try {
    return new RegExp(pattern, "i");
  } catch (err) {
    fail(`Invalid --filter regex: ${err.message}`, 2);
  }
}

async function listServices(filter) {
  const { items, sourceUrl } = await fetchAllPages("/services", {}, "services");
  let services = items.map((s) => ({ serviceId: s.serviceId, displayName: s.displayName }));
  if (filter) {
    const re = compileRegex(filter);
    services = services.filter((s) => re.test(s.displayName) || re.test(s.serviceId));
  }
  services.sort((a, b) => a.displayName.localeCompare(b.displayName));
  return { services, sourceUrl };
}

async function resolveService(input) {
  if (SERVICE_ID_RE.test(input)) {
    return { serviceId: input.toUpperCase(), displayName: null };
  }
  const { services } = await listServices(null);
  const lower = input.toLowerCase();
  const exact = services.filter((s) => s.displayName.toLowerCase() === lower);
  if (exact.length === 1) return exact[0];
  const partial = services.filter((s) => s.displayName.toLowerCase().includes(lower));
  if (partial.length === 1) return partial[0];
  if (partial.length > 1) {
    const candidates = partial.slice(0, 10).map((s) => `  ${s.serviceId}  ${s.displayName}`).join("\n");
    fail(`Ambiguous service "${input}"; candidates:\n${candidates}\nRe-run with an exact serviceId.`, 2);
  }
  fail(`No Cloud Billing service matches "${input}". Run: gcp-pricing services --filter "${input}"`, 2);
}

function formatSku(sku) {
  const info = sku.pricingInfo?.[0] ?? {};
  const expr = info.pricingExpression ?? {};
  return {
    skuId: sku.skuId,
    description: sku.description,
    category: sku.category,
    serviceRegions: sku.serviceRegions,
    usageUnit: expr.usageUnit,
    usageUnitDescription: expr.usageUnitDescription,
    pricingEffectiveTime: info.effectiveTime,
    tieredRates: (expr.tieredRates ?? []).map((rate) => ({
      startUsageAmount: rate.startUsageAmount,
      unitPrice: moneyToDecimal(rate.unitPrice),
      currencyCode: rate.unitPrice?.currencyCode,
    })),
    ...(info.aggregationInfo ? { aggregationInfo: info.aggregationInfo } : {}),
  };
}

async function main() {
  const { command, opts = {} } = parseArgs(process.argv.slice(2));
  const retrievedAt = new Date().toISOString();

  if (command === "help" || command === undefined) {
    process.stdout.write(`${USAGE}\n`);
    process.exit(command === "help" ? 0 : 2);
  }

  if (command === "services") {
    const { services, sourceUrl } = await listServices(opts.filter);
    process.stdout.write(`${JSON.stringify({
      retrieved_at: retrievedAt,
      auth_mode: auth.mode(),
      source_url: sourceUrl,
      count: services.length,
      services,
    }, null, 2)}\n`);
    return;
  }

  if (command === "skus") {
    if (!opts.service) fail(`--service is required for skus\n\n${USAGE}`, 2);
    const limit = opts.limit === undefined ? 50 : Number(opts.limit);
    if (!Number.isInteger(limit) || limit < 0) fail("--limit must be a non-negative integer", 2);
    const service = await resolveService(opts.service);
    const { items, sourceUrl } = await fetchAllPages(
      `/services/${service.serviceId}/skus`,
      { currencyCode: opts.currency },
      "skus",
    );
    let matched = items;
    if (opts.region) {
      matched = matched.filter((sku) => (sku.serviceRegions ?? []).includes(opts.region));
    }
    if (opts.filter) {
      const re = compileRegex(opts.filter);
      matched = matched.filter((sku) => re.test(sku.description ?? ""));
    }
    const returned = limit === 0 ? matched : matched.slice(0, limit);
    process.stdout.write(`${JSON.stringify({
      retrieved_at: retrievedAt,
      auth_mode: auth.mode(),
      currency: opts.currency ?? "USD",
      service: {
        serviceId: service.serviceId,
        displayName: service.displayName ?? items[0]?.category?.serviceDisplayName ?? null,
      },
      source_url: sourceUrl,
      total_fetched: items.length,
      total_matched: matched.length,
      returned: returned.length,
      skus: returned.map(formatSku),
    }, null, 2)}\n`);
    return;
  }

  fail(`Unknown command: ${command}\n\n${USAGE}`, 2);
}

main().catch((err) => {
  fail(err.message === SETUP_HELP ? SETUP_HELP : `gcp-pricing failed: ${err.stack ?? err.message}`);
});
