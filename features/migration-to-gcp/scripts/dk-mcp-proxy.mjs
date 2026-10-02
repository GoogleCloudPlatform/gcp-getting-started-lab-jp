#!/usr/bin/env node
// stdio <-> Streamable HTTP proxy for the Google Developer Knowledge MCP server.
//
// Claude Code has no built-in Google-credential auth provider for remote MCP
// servers (Google documents only the X-Goog-Api-Key method for Claude Code),
// so this proxy injects fresh gcloud ADC bearer tokens per request, falling
// back to gcloud user credentials, then to an API key (DK_API_KEY).
//
// Scope: request/response tools only (search_documents, get_documents,
// answer_query). No server-initiated requests, so no GET listening stream.

import { createInterface } from "node:readline";
import { createAuthProvider, SETUP_HELP } from "./lib/gcp-auth.mjs";

const ENDPOINT = process.env.DK_MCP_ENDPOINT || "https://developerknowledge.googleapis.com/mcp";
const auth = createAuthProvider({ apiKeyEnvVars: ["DK_API_KEY", "GOOGLE_API_KEY"] });

let sessionId = null;
let protocolVersion = null;

const log = (msg) => process.stderr.write(`[dk-mcp-proxy] ${msg}\n`);
const emit = (msg) => process.stdout.write(`${JSON.stringify(msg)}\n`);

function emitError(id, message) {
  if (id === undefined || id === null) return; // notifications get no reply
  emit({ jsonrpc: "2.0", id, error: { code: -32000, message } });
}

async function buildHeaders() {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json, text/event-stream",
    ...(await auth.headers()),
  };
  if (sessionId) headers["Mcp-Session-Id"] = sessionId;
  if (protocolVersion) headers["MCP-Protocol-Version"] = protocolVersion;
  return headers;
}

async function postOnce(message) {
  return fetch(ENDPOINT, {
    method: "POST",
    headers: await buildHeaders(),
    body: JSON.stringify(message),
  });
}

// POST with one token-refresh retry and a final API-key demotion retry on auth failures.
async function post(message) {
  let res = await postOnce(message);
  if (res.status === 401 || res.status === 403) {
    auth.invalidate();
    res = await postOnce(message);
  }
  if ((res.status === 401 || res.status === 403) && auth.mode() !== "api-key" && auth.demoteToApiKey()) {
    log("bearer auth rejected; failing over to API key");
    res = await postOnce(message);
  }
  return res;
}

function handleIncoming(message, isInitialize) {
  if (isInitialize && message?.result?.protocolVersion) {
    protocolVersion = message.result.protocolVersion;
  }
  emit(message);
}

async function readSse(body, isInitialize) {
  const decoder = new TextDecoder();
  let buffer = "";
  const dispatch = (rawEvent) => {
    const data = rawEvent
      .split(/\r?\n/)
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).trimStart())
      .join("\n");
    if (!data) return;
    try {
      handleIncoming(JSON.parse(data), isInitialize);
    } catch {
      log(`skipping unparseable SSE event: ${data.slice(0, 200)}`);
    }
  };
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    let boundary;
    while ((boundary = buffer.search(/\r?\n\r?\n/)) !== -1) {
      const rawEvent = buffer.slice(0, boundary);
      buffer = buffer.slice(boundary).replace(/^\r?\n\r?\n/, "");
      dispatch(rawEvent);
    }
  }
  if (buffer.trim()) dispatch(buffer);
}

async function handleLine(line) {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    log(`ignoring unparseable input line: ${line.slice(0, 200)}`);
    return;
  }
  const isInitialize = message?.method === "initialize";
  const id = message?.id;
  try {
    const res = await post(message);
    const newSession = res.headers.get("mcp-session-id");
    if (newSession) sessionId = newSession;

    if (res.status === 202 || res.status === 204) return;
    if (!res.ok) {
      const body = (await res.text()).slice(0, 2000);
      const detail = res.status === 404 && sessionId && !isInitialize
        ? "session expired; restart the MCP server (/mcp) to re-initialize"
        : body || res.statusText;
      emitError(id, `Developer Knowledge MCP HTTP ${res.status}: ${detail}`);
      return;
    }

    const contentType = res.headers.get("content-type") || "";
    if (contentType.includes("text/event-stream")) {
      await readSse(res.body, isInitialize);
    } else {
      const text = await res.text();
      if (!text.trim()) return;
      handleIncoming(JSON.parse(text), isInitialize);
    }
  } catch (err) {
    emitError(id, `Developer Knowledge MCP proxy error: ${err.message}`);
  }
}

async function main() {
  try {
    await auth.headers(); // preflight: fail fast with actionable guidance
    log(`auth mode: ${auth.mode()}`);
  } catch {
    process.stderr.write(`${SETUP_HELP}\n`);
    process.exit(1);
  }

  let queue = Promise.resolve();
  const rl = createInterface({ input: process.stdin, terminal: false });
  rl.on("line", (line) => {
    queue = queue.then(() => handleLine(line));
  });
  rl.on("close", () => {
    queue.finally(async () => {
      try {
        if (sessionId) {
          // Best-effort session teardown per the Streamable HTTP spec.
          await fetch(ENDPOINT, { method: "DELETE", headers: await buildHeaders() });
        }
      } catch {
        // teardown is best-effort
      }
      process.exit(0);
    });
  });
}

main();
