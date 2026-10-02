#!/usr/bin/env node

/**
 * Validates Claude Code plugin manifests in this repo:
 * - .claude-plugin/marketplace.json (repo root)
 * - features/<plugin>/.claude-plugin/plugin.json
 * - features/<plugin>/.mcp.json
 *
 * Checks: valid JSON, required fields, naming conventions, and the
 * current plugin.json schema (no legacy name-array `mcpServers` /
 * object-array `skills` fields).
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";

const repoRoot = process.cwd();
const errors = [];

function addError(msg) { errors.push(msg); }

async function readJson(filePath, label) {
  let raw;
  try {
    raw = await fs.readFile(filePath, "utf8");
  } catch {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch (e) {
    addError(`${label}: invalid JSON — ${e.message}`);
    return null;
  }
}

async function findFiles(dir, pattern) {
  const results = [];
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true, recursive: true });
    for (const entry of entries) {
      const full = path.join(entry.parentPath || dir, entry.name);
      if (entry.isFile() && entry.name === pattern) {
        results.push(full);
      }
    }
  } catch { /* dir doesn't exist */ }
  return results;
}

const namePattern = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
const userConfigTypes = new Set(["string", "number", "boolean", "directory", "file"]);

function isPathLike(value) {
  return typeof value === "string" && value.startsWith("./");
}

async function validateMarketplaceJson(filePath) {
  const rel = path.relative(repoRoot, filePath);
  const json = await readJson(filePath, rel);
  if (!json) {
    addError(`${rel}: missing or unreadable — the repo marketplace catalog is required.`);
    return;
  }

  if (!json.name || !namePattern.test(json.name)) {
    addError(`${rel}: "name" must be lowercase kebab-case.`);
  }
  if (!json.owner || typeof json.owner !== "object" || !json.owner.name) {
    addError(`${rel}: "owner" object with "name" is required.`);
  }
  if (!Array.isArray(json.plugins) || json.plugins.length === 0) {
    addError(`${rel}: "plugins" must be a non-empty array.`);
    return;
  }
  for (const [i, entry] of json.plugins.entries()) {
    if (!entry?.name || !namePattern.test(entry.name)) {
      addError(`${rel}: plugins[${i}].name must be lowercase kebab-case.`);
    }
    if (!entry?.source) {
      addError(`${rel}: plugins[${i}].source is required.`);
    } else if (typeof entry.source === "string" && !isPathLike(entry.source)) {
      addError(`${rel}: plugins[${i}].source relative paths must start with "./".`);
    }
  }
}

async function validatePluginJson(filePath) {
  const rel = path.relative(repoRoot, filePath);
  const json = await readJson(filePath, rel);
  if (!json) return;

  if (!json.name || !namePattern.test(json.name)) {
    addError(`${rel}: "name" must be lowercase kebab-case.`);
  }
  if (!json.description) {
    addError(`${rel}: "description" is required.`);
  }
  if (json.author !== undefined && (typeof json.author !== "object" || !json.author.name)) {
    addError(`${rel}: "author" must be an object with "name".`);
  }

  // Current schema: `skills` is a "./path" string or array of "./path" strings.
  if (json.skills !== undefined) {
    const values = Array.isArray(json.skills) ? json.skills : [json.skills];
    for (const v of values) {
      if (!isPathLike(v)) {
        addError(`${rel}: "skills" entries must be "./"-relative path strings (the default skills/ dir is auto-discovered — drop the field unless adding extra dirs). Got: ${JSON.stringify(v)}`);
      }
    }
  }

  // Current schema: `mcpServers` is a "./path" string, array of "./path" strings, or inline config object.
  if (json.mcpServers !== undefined) {
    const value = json.mcpServers;
    const ok = isPathLike(value)
      || (Array.isArray(value) && value.every(isPathLike))
      || (typeof value === "object" && !Array.isArray(value));
    if (!ok) {
      addError(`${rel}: "mcpServers" must be a "./"-relative config path, array of paths, or inline config object (a plugin-root .mcp.json is auto-discovered — drop the field in that case). Got: ${JSON.stringify(value)}`);
    }
  }

  if (json.userConfig !== undefined) {
    if (typeof json.userConfig !== "object" || Array.isArray(json.userConfig)) {
      addError(`${rel}: "userConfig" must be an object.`);
    } else {
      for (const [key, opt] of Object.entries(json.userConfig)) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
          addError(`${rel}: userConfig key "${key}" must be a valid identifier.`);
        }
        if (!opt?.type || !userConfigTypes.has(opt.type)) {
          addError(`${rel}: userConfig.${key}.type must be one of ${[...userConfigTypes].join(", ")}.`);
        }
        if (!opt?.title || !opt?.description) {
          addError(`${rel}: userConfig.${key} requires "title" and "description".`);
        }
      }
    }
  }
}

async function validateMcpJson(filePath) {
  const rel = path.relative(repoRoot, filePath);
  const json = await readJson(filePath, rel);
  if (!json) return;

  if (!json.mcpServers || typeof json.mcpServers !== "object") {
    addError(`${rel}: must contain "mcpServers" object.`);
    return;
  }

  for (const [name, config] of Object.entries(json.mcpServers)) {
    const type = config.type || (config.url ? "http" : "stdio");
    if (type === "stdio" && !config.command) {
      addError(`${rel}: server "${name}" is stdio but missing "command".`);
    }
    if ((type === "http" || type === "sse") && !config.url) {
      addError(`${rel}: server "${name}" is ${type} but missing "url".`);
    }
  }
}

// Claude Code rejects skill descriptions over 1024 chars at load time (CLI schema:
// description max(1024)) — a silent skill-loading break no other validator catches.
const SKILL_DESC_HARD_LIMIT = 1024;
const SKILL_DESC_WARN_AT = 950;

async function validateSkillDescriptions(featuresDir) {
  const skillFiles = await findFiles(featuresDir, "SKILL.md");
  for (const f of skillFiles) {
    const rel = path.relative(repoRoot, f);
    let raw;
    try {
      raw = await fs.readFile(f, "utf8");
    } catch {
      continue;
    }
    const fm = raw.match(/^---\n([\s\S]*?)\n---/);
    if (!fm) {
      addError(`${rel}: missing YAML frontmatter block.`);
      continue;
    }
    const desc = fm[1].match(/^description:\s*"((?:[^"\\]|\\.)*)"\s*$/m);
    if (!desc) continue; // unquoted or absent descriptions are the CLI's problem to flag
    const len = desc[1].length;
    if (len > SKILL_DESC_HARD_LIMIT) {
      addError(`${rel}: frontmatter description is ${len} chars — over the ${SKILL_DESC_HARD_LIMIT}-char limit; the skill will fail to load.`);
    } else if (len > SKILL_DESC_WARN_AT) {
      console.warn(`  warn: ${rel} description is ${len}/${SKILL_DESC_HARD_LIMIT} chars — trim before adding trigger phrases.`);
    }
  }
}

async function main() {
  console.log("Validating manifests...\n");

  await validateMarketplaceJson(path.join(repoRoot, ".claude-plugin", "marketplace.json"));

  await validateSkillDescriptions(path.join(repoRoot, "features"));

  const pluginManifests = await findFiles(path.join(repoRoot, "features"), "plugin.json");
  for (const f of pluginManifests) {
    if (f.includes(".claude-plugin")) await validatePluginJson(f);
  }

  const mcpFiles = await findFiles(path.join(repoRoot, "features"), ".mcp.json");
  for (const f of mcpFiles) {
    await validateMcpJson(f);
  }

  if (errors.length > 0) {
    console.error("Manifest validation failed:");
    for (const e of errors) console.error(`  - ${e}`);
    process.exit(1);
  }

  console.log("All manifests valid.");
}

await main();
