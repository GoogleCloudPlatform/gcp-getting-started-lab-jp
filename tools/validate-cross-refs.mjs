#!/usr/bin/env node

/**
 * Validates cross-references between the Claude Code marketplace catalog
 * (.claude-plugin/marketplace.json), plugin directories, and skill markdown
 * reference links.
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";

const repoRoot = process.cwd();
const errors = [];
const warnings = [];

const pluginNamePattern = /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/;

function addError(msg) { errors.push(msg); }
function addWarning(msg) { warnings.push(msg); }

async function pathExists(p) {
  try { await fs.access(p); return true; } catch { return false; }
}

async function readJson(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch {
    return null;
  }
}

async function readText(filePath) {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch {
    return null;
  }
}

async function findFiles(dir, predicate) {
  const results = [];
  let entries;
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return results;
  }

  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...await findFiles(full, predicate));
    } else if (predicate(full, entry.name)) {
      results.push(full);
    }
  }
  return results;
}

async function findSkillDir(filePath) {
  let dir = path.dirname(filePath);
  while (dir.startsWith(repoRoot)) {
    if (await pathExists(path.join(dir, "SKILL.md"))) return dir;
    const next = path.dirname(dir);
    if (next === dir) break;
    dir = next;
  }
  return null;
}

function isSafeRelativePath(value) {
  if (typeof value !== "string" || value.length === 0) return false;
  if (path.isAbsolute(value)) return false;
  const normalized = path.posix.normalize(value.replace(/\\/g, "/"));
  return !normalized.startsWith("../") && normalized !== "..";
}

async function validateClaudeMarketplace() {
  const marketplacePath = path.join(repoRoot, ".claude-plugin", "marketplace.json");
  const marketplace = await readJson(marketplacePath);

  if (!marketplace) {
    addWarning("Claude Code: no marketplace.json found at .claude-plugin/");
    return;
  }

  console.log("\nValidating Claude Code marketplace...");

  if (!Array.isArray(marketplace.plugins) || marketplace.plugins.length === 0) {
    addError("Claude Code: marketplace \"plugins\" must be a non-empty array.");
    return;
  }

  const seenNames = new Set();
  for (const [i, entry] of marketplace.plugins.entries()) {
    const label = `Claude Code plugins[${i}]`;

    if (!entry || typeof entry !== "object") {
      addError(`${label}: must be an object.`);
      continue;
    }

    if (typeof entry.name !== "string" || !pluginNamePattern.test(entry.name)) {
      addError(`${label}: "name" must be lowercase kebab-case.`);
      continue;
    }

    if (seenNames.has(entry.name)) {
      addError(`${label}: duplicate plugin name "${entry.name}".`);
    }
    seenNames.add(entry.name);

    const source = entry.source;
    if (!source || !isSafeRelativePath(source)) {
      addError(`${label}: "source" must be a safe relative path.`);
      continue;
    }

    const pluginDir = path.resolve(repoRoot, source);
    if (!(await pathExists(pluginDir))) {
      addError(`${label}: source directory does not exist: ${source}`);
      continue;
    }

    // Validate .claude-plugin/plugin.json exists and name matches
    const pluginJsonPath = path.join(pluginDir, ".claude-plugin", "plugin.json");
    const pluginJson = await readJson(pluginJsonPath);
    if (!pluginJson) {
      addError(`${label}: missing .claude-plugin/plugin.json in ${source}`);
      continue;
    }

    if (pluginJson.name !== entry.name) {
      addError(`${label}: marketplace name "${entry.name}" does not match plugin.json name "${pluginJson.name}".`);
    }

    // Validate the plugin actually ships at least one skill
    const skillPath = path.join(pluginDir, "skills");
    if (!(await pathExists(skillPath))) {
      addError(`${label}: no skills/ directory in ${source}.`);
    }

    console.log(`  OK: ${entry.name} -> ${source}`);
  }
}

const PHASE_DIRS = ["discover", "clarify", "design", "estimate", "generate"];

function resolveMarkdownReference(skillDir, currentFile, ref) {
  const normalized = ref.replace(/\\/g, "/");
  const candidates = [];

  // Not intra-skill references: globs, placeholders, and external install
  // paths (the google/skills companion protocol reads from the user's home).
  if (normalized.includes("*")) return candidates;
  if (normalized.includes("<") || normalized.includes(">")) return candidates;
  if (normalized.startsWith("~") || normalized.startsWith(".claude/") || normalized.startsWith(".agents/")) return candidates;

  if (normalized.startsWith("references/")) {
    candidates.push(path.join(skillDir, normalized));
  } else if (
    normalized.startsWith("shared/") ||
    normalized.startsWith("phases/") ||
    normalized.startsWith("design-refs/") ||
    normalized.startsWith("clustering/")
  ) {
    candidates.push(path.join(skillDir, "references", normalized));
  } else {
    candidates.push(path.join(path.dirname(currentFile), normalized));
    candidates.push(path.join(skillDir, "references", "shared", normalized));
    candidates.push(path.join(skillDir, "references", "design-refs", normalized));
    candidates.push(path.join(skillDir, "references", "phases", normalized));
    for (const phase of PHASE_DIRS) {
      candidates.push(path.join(skillDir, "references", "phases", phase, normalized));
    }
  }

  return candidates;
}

async function validateSkillMarkdownReferences() {
  const skillsRoot = path.join(repoRoot, "features");
  const markdownFiles = await findFiles(skillsRoot, (full, name) => name.endsWith(".md"));
  const loadLinePattern = /\b(load|read)\b|>\s*load|->\s*load/i;
  const refPattern = /`([^`]+\.md)`/g;

  for (const filePath of markdownFiles) {
    const skillDir = await findSkillDir(filePath);
    if (!skillDir) continue;

    const text = await readText(filePath);
    if (!text) continue;

    const relFile = path.relative(repoRoot, filePath);
    const lines = text.split(/\r?\n/);

    for (const [index, line] of lines.entries()) {
      if (!loadLinePattern.test(line)) continue;

      for (const match of line.matchAll(refPattern)) {
        const ref = match[1];
        // Generated-artifact and external-skill file mentions, not intra-skill links
        if (ref.startsWith("terraform/") || ref === "README.md" || ref === "MIGRATION_GUIDE.md" || ref === "SKILL.md") {
          continue;
        }
        const candidates = resolveMarkdownReference(skillDir, filePath, ref);
        if (candidates.length === 0) continue;
        let found = false;
        for (const candidate of candidates) {
          if (await pathExists(candidate)) {
            found = true;
            break;
          }
        }
        if (!found) {
          addError(`${relFile}:${index + 1}: markdown reference does not exist: ${ref}`);
        }
      }
    }
  }
}

async function main() {
  await validateClaudeMarketplace();
  await validateSkillMarkdownReferences();

  if (warnings.length > 0) {
    console.log("\nWarnings:");
    for (const w of warnings) console.log(`  - ${w}`);
  }

  if (errors.length > 0) {
    console.error("\nValidation failed:");
    for (const e of errors) console.error(`  - ${e}`);
    process.exit(1);
  }

  console.log("\nAll cross-references valid.");
}

await main();
