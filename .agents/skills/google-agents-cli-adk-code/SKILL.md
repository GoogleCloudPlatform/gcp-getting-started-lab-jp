---
name: google-agents-cli-adk-code
description: >
  This skill should be used when the user wants to "write agent code",
  "build an agent with ADK", "add a tool", "create a callback", "define an agent",
  "use state management", or needs ADK (Agent Development Kit) Python API patterns
  and code examples. Part of the Google ADK skills suite.
  It provides a quick reference for agent types, tool definitions, orchestration
  patterns, callbacks, state management, and reference recipes to study.
  Do NOT use for scaffolding (use google-agents-cli-scaffold) or deployment
  (use google-agents-cli-deploy).
metadata:
  author: Google
  license: Apache-2.0
  version: 1.4.1
  requires:
    bins:
      - agents-cli
    install: "uv tool install google-agents-cli"
---

# ADK Code Reference

Activate `/google-agents-cli-workflow` first for required development phases and scaffolding steps.

## 1. Study Recipes (No Project Needed)

**Read the topic index in `references/samples.md` before answering "how do I build X".** Worked implementations exist for: sandboxed/per-user code execution, agent-loadable `SKILL.md` skills, cross-session memory, approval gates before risky actions, tool guardrails, per-user credentials, and scheduled/event-driven runs.

The index only gives you a name; the recipe is the code. Clone it and read its `AGENTS.md` before you implement anything it covers. Hand-writing a Docker or E2B sandbox wrapper, a skill loader, a moderation callback or a memory store — for a capability the index lists — means you stopped at the name.

## 2. Prerequisites for Writing Code

Do NOT write agent code until a project is scaffolded.

1. Verify project: run `agents-cli info` (proceed if config exists).
2. New project: run `agents-cli scaffold create <name>`.
3. Existing code: run `agents-cli scaffold enhance .`.

> **Language Support:** This reference covers the Python ADK SDK. Support for other languages coming soon.

## Quick Reference — Most Common Patterns

```python
from google.adk.agents import Agent

def get_weather(city: str) -> dict:
    """Get current weather for a city."""
    return {"city": city, "temp": "22°C", "condition": "sunny"}

root_agent = Agent(
    name="my_agent",
    model="gemini-3.7-flash",
    instruction="You are a helpful assistant that ...",
    tools=[get_weather],
)
```

---

## References

Use cheatsheets for common patterns. For deep knowledge, fetch the docs index or inspect the installed package.

| Reference | When to read |
|------|-------------|
| `references/samples.md` | **Topic-indexed catalog of ADK reference recipes.** Read in workflow Phase 1 — before scaffolding and before writing code — maps a capability to the recipe that implements it. |
| `references/adk-python.md` | Core ADK API: `Agent`, tools, callbacks, plugins, state, artifacts, multi-agent systems, `SequentialAgent` / `ParallelAgent` / `LoopAgent`, custom `BaseAgent`, `ManagedAgent` (server-hosted first-party agents), A2A protocol, A2UI. Default for most agents. |
| `references/adk-workflows.md` | Graph-based Workflow API (ADK 2.0): nodes, edges, fan-out/fan-in, HITL, parallel processing. Use when you need explicit graph topology. |
| `curl https://adk.dev/llms.txt` | Docs index (every page title + URL). Fetch it, then `WebFetch` the specific page for anything beyond the cheatsheets. |
| Installed ADK package | Exact signatures and symbols — inspect the source (see "Inspecting ADK Source Code" in `references/adk-python.md`). |

## Related Skills

- `/google-agents-cli-workflow` — Development workflow, coding guidelines, and operational rules
- `/google-agents-cli-scaffold` — Project creation and enhancement with `agents-cli scaffold create` / `scaffold enhance`
- `/google-agents-cli-eval` — Evaluation methodology, dataset schema, and the eval-fix loop
- `/google-agents-cli-deploy` — Deployment targets, CI/CD pipelines, and production workflows
