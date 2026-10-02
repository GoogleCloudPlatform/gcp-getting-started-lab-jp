#!/usr/bin/env node
// uploader.mjs — shoot uploader for the media-licensing operator (fictional).
//
// Run on the ingest workstation in the edit bay after a card dump. It walks a
// shoot folder and pushes every frame into the intake container; the proxy
// generator picks the writes up from there. There is no server: the studio has
// never had one, and this is the only thing anybody at the studio runs by hand.
//
//   smp-upload upload ./2026-07-31-sakura --shoot 2026-07-31-sakura
//   smp-upload health
//   smp-upload azure-check
//
// Configuration is environment only:
//   SMP_MEDIA_ACCOUNT      storage account holding the library (required)
//   SMP_INTAKE_CONTAINER   default: intake
//   SMP_MASTERS_CONTAINER  default: masters
//   SMP_PROXY_QUEUE        default: proxy-jobs
import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import {
  checkServices,
  config,
  configErrors,
  contentTypeFor,
  proxyQueueDepth,
  uploadShootFile,
} from "./azureClients.mjs";

const SHOOTABLE = new Set([".arw", ".cr3", ".dng", ".jpg", ".jpeg", ".mov", ".mp4", ".tif", ".tiff"]);

function usage() {
  console.error("usage: smp-upload <upload <dir> --shoot <id> | health | azure-check>");
}

async function shootFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  return entries
    .filter((e) => e.isFile() && SHOOTABLE.has(path.extname(e.name).toLowerCase()))
    .map((e) => path.join(dir, e.name))
    .sort();
}

async function cmdUpload(args) {
  const dir = args[0];
  const shootIdx = args.indexOf("--shoot");
  const shootId = shootIdx === -1 ? null : args[shootIdx + 1];

  if (!dir || !shootId) {
    usage();
    return 2;
  }
  if (!(await stat(dir)).isDirectory()) {
    console.error(`${dir} is not a directory`);
    return 2;
  }

  const files = await shootFiles(dir);
  if (files.length === 0) {
    console.error(`no shootable files in ${dir}`);
    return 1;
  }

  let bytes = 0;
  for (const file of files) {
    const result = await uploadShootFile(shootId, file);
    bytes += result.bytes;
    console.log(`${result.blobName}  ${result.bytes}  ${contentTypeFor(file)}`);
  }

  console.log(`uploaded ${files.length} file(s), ${bytes} bytes, into ${config.intakeContainer}/${shootId}/`);
  return 0;
}

// Same contract the studio's web-facing services would expose at GET /health:
// one line per hard dependency, and it never raises.
async function cmdHealth() {
  const report = {
    status: "ok",
    account: config.mediaAccount || null,
    intakeContainer: config.intakeContainer,
    checks: {},
  };

  if (configErrors.length > 0) {
    report.status = "degraded";
    report.checks.config = { ok: false, error: configErrors.join("; ") };
  } else {
    report.checks.config = { ok: true };
  }

  try {
    report.checks.proxyQueue = { ok: true, depth: await proxyQueueDepth() };
  } catch (err) {
    report.status = "degraded";
    report.checks.proxyQueue = { ok: false, error: String(err?.message ?? err).slice(0, 300) };
  }

  console.log(JSON.stringify(report, null, 2));
  return report.status === "ok" ? 0 : 1;
}

// Same contract as GET /admin/azure-check: every Azure service the uploader
// touches, one ok/fail each. After a migration this is the parity page.
async function cmdAzureCheck() {
  const services = await checkServices();
  const ok = Object.values(services).every((s) => s.ok);
  console.log(JSON.stringify({ status: ok ? "ok" : "degraded", services }, null, 2));
  return ok ? 0 : 1;
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  switch (command) {
    case "upload":
      return cmdUpload(args);
    case "health":
      return cmdHealth();
    case "azure-check":
      return cmdAzureCheck();
    default:
      usage();
      return 2;
  }
}

process.exitCode = await main();
