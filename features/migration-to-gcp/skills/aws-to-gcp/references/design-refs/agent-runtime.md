# Agent Workload Placement Rubric — Agent Runtime

**Applies to:** detected agent-framework workloads (`ai-workload-profile.json` -> `agent_workloads[]`):
Google ADK, LangGraph, CrewAI, LangChain agents, OpenAI Agents SDK self-hosted on ECS/Fargate, EC2, or
Lambda; Amazon Bedrock Agents (`aws_bedrockagent_*`); Amazon Bedrock AgentCore (`bedrock-agentcore`
clients).

**Target:** **Agent Runtime on the Gemini Enterprise Agent Platform (GEAP; formerly "Vertex AI Agent
Engine")** — the managed agent runtime. Naming guard: "Agent Runtime" in this file always means the
GCP managed runtime; AWS's `bedrock-agent-runtime` / "Bedrock Agent Runtime" API strings belong to
Amazon Bedrock and are never renamed or conflated.

## Companion skill (google-agents-cli)

Before applying this rubric or shaping the target configuration:

- Read the latest version of **`google-agents-cli-deploy`** at
  `~/.claude/skills/google-agents-cli-deploy/SKILL.md` (fallbacks
  `~/.agents/skills/google-agents-cli-deploy/SKILL.md`, then project-local
  `.claude/skills/google-agents-cli-deploy/SKILL.md`). Its Deployment Target Decision Matrix, deploy
  flags, sizing defaults, secrets handling, and rollback notes are the source of truth for the GCP
  side.
- This skill family does **not** install via `npx skills add google/skills` — see
  `references/shared/companion-skills.md` > "Google agent skills" for the canonical registration.
  If found, include the rationale phrase `"sourced from google-agents-cli-deploy SKILL.md"`. If not
  found, fall back to this rubric and add the warning (verbatim):
  `"google-agents-cli-deploy not installed; used aws-to-gcp fallback rubric (design-refs/agent-runtime.md). Install with: uv tool install google-agents-cli"`.

This rubric is the AWS -> GCP **decision** layer for agent workloads. The google-agents-cli skill is
the **how** layer for the chosen target.

## Inputs

`ai-workload-profile.json` -> `agent_workloads[]` (plus `models[]` for the already-on-target check),
`preferences.json` -> `ai_constraints.ai_framework`, `design_constraints.container_orchestration`.

## Eliminators (redirect away from Agent Runtime — first match wins)

| # | Condition                                                                  | Redirect | Why                                |
| - | -------------------------------------------------------------------------- | -------- | ---------------------------------- |
| 1 | `container_orchestration` = `gke-autopilot` / `gke-standard` (K8s mandate) | GKE      | Preserve the Kubernetes investment |

Conditions per the google-agents-cli-deploy decision matrix; re-verify live at design time per
SKILL.md Philosophy (research before deciding).

**NON-eliminators (corrected 2026-08-28 — do not reintroduce):** earlier revisions of this file
redirected on four conditions Agent Runtime now handles; none of them justifies leaving the managed
agent runtime:

- **Pub/Sub-push / Eventarc trigger endpoint** — ADK `trigger_sources` routes are reachable on
  Agent Runtime through the Agent Engine `/api` passthrough
  (`.../reasoningEngines/v1/{resource}/api/apps/{app}/trigger/pubsub`), and push
  subscriptions/Eventarc deliver with OIDC auth; an unauthenticated trigger source is an
  integration-hardening task, not a placement change (Cloud Run is merely the _simplest_ target for
  unauthenticated sources — offer it as the alternative on the trade-off card, never as a forced
  redirect).
- **IAP in front of the agent** — the need behind IAP (governed internal access) is met on the
  platform: agents on Agent Runtime surface through **Gemini Enterprise** (org identity, governed
  access) and the engine's endpoints are IAM-authenticated. The literal `--iap` flag remains
  Cloud Run-only; requiring that specific mechanism is a constraint to surface on the trade-off
  card, not an eliminator.
- **Revision-based rollback / traffic splitting as a hard requirement** — Agent Runtime supports
  runtime revisions (v1 API: `reasoningEngines.runtimeRevisions` `query`/`streamQuery` — verified
  2026-08-28); rollback/traffic control works against revisions, and each `agents-cli deploy`
  additionally leaves the previous engine serving until you delete it (blue/green by default).
  The old "fix-and-redeploy only" limitation is gone.
- **Org allows deploys only via gcloud/Terraform** — Agent Runtime has a Terraform resource (see
  google-agents-cli-deploy `references/agent-runtime.md` + `terraform-patterns.md`; "deploy via
  Terraform" is a documented path). This plugin's generated runbook uses `agents-cli`, but IaC-only
  tooling policy does not force the workload onto Cloud Run.

**On redirect** (any eliminator fires, or a Bedrock knowledge base maps to Agent Search): map the
resource as a **normal workload of the redirect target** — ordinary `gcp_config` for that service,
Terraform emits normally, and do **NOT** set `deployment_tool` or `no_terraform_emit`. Those two
keys belong exclusively to `gcp_service: "Agent Runtime"` outcomes. Record the eliminator in
`rationale` (and in `agent_placement[].eliminator_applied`).

## Signals (pro-Agent-Runtime)

- **OAuth user-consent flows** (agent accesses user-scoped Google APIs) -> Agent Runtime REQUIRED
  (managed OAuth is not available on Cloud Run) — skip the trade-off card.
- **Self-managed session store** (`agent_workloads[].session_state.store` = `dynamodb` /
  `elasticache`) -> managed Sessions (`VertexAiSessionService`) replaces it — strong signal.
- **Spiky / idle-heavy traffic** -> not billed when idle (vCPU-hour + GiB-hour cost model).
- **VPC-SC / PSC-I requirements** -> supported via network attachments.
- **Minimal-ops preference** -> lowest setup complexity of the three targets (purpose-built for
  agents).

## Priority rule (binding)

When `agent_workloads[]` is non-empty and no eliminator fires, **Agent Runtime is the default
recommendation** — SKILL.md Philosophy applies: a newer GCP product that better fits the source takes
precedence over the stale rubric default (here, over "Containerized workloads -> Cloud Run"). Per
SKILL.md's trade-off mandate, still present a research-populated trade-off card with **Agent Runtime
listed first, marked "Recommended (default)"** and Cloud Run as the alternative; record the pick in
`preferences.json.design_choices[]` keyed by `aws_address`.

**Headless disposition:** Agent Runtime (the documented default), recorded with
`chosen_by: "headless-default"`.

## Sizing

Same knobs as Cloud Run: `cpu`, `memory`, `concurrency`, `min_instances`, `max_instances`.
Deploy-tool defaults: cpu `1`, memory `4Gi`, concurrency `8`, min `0` (scale to zero — agents-cli
≥ 1.4; 1.3.x defaulted to `1`, and the scaffold's generated Terraform pins `1`), max `10`. When CloudWatch
access-pattern data exists, reuse the Cloud Run sizing formulas in `compute.md` but cap `concurrency`
at 8 unless load-tested — agent servers are memory-bound (peak ≈ base + concurrency × per-request
working set: context window, history, RAG chunks). Record `sizing_source` per the design-infra Step
1.5 audit-trail rule.

## Session-state migration

Self-managed DynamoDB/ElastiCache session stores are superseded by managed Sessions. Map the store
resource normally in `gcp-design.json` but append to its rationale: "session data moves to Agent
Runtime managed Sessions (VertexAiSessionService); the mapped target is transitional — decommission
after cutover", and add a matching `warnings[]` entry.

## Bedrock Agents / AgentCore mapping

- **Bedrock Agents** (`aws_bedrockagent_agent`, `aws_bedrockagent_knowledge_base`): **rebuild as
  Google ADK agents on Agent Runtime** — a Bedrock agent definition is config, an ADK agent is code,
  so parity is Partial (rebuild, not an import). Knowledge bases -> Agent Search; the business
  no-code agent hub -> Gemini Enterprise.
- **Bedrock AgentCore** (`bedrock-agentcore` / `bedrock-agentcore-control` clients): **Agent
  Runtime** (the direct managed-agent-runtime analog; the agent code itself is framework-portable).

## Output Schema

```json
{
  "aws_address": "aws_ecs_service.agent",
  "aws_type": "aws_ecs_service",
  "aws_config": { "cpu": 1024, "memory": 4096, "desired_count": 1 },
  "gcp_service": "Agent Runtime",
  "gcp_config": {
    "deployment_tool": "agents-cli",
    "no_terraform_emit": true,
    "cpu": "1",
    "memory": "4Gi",
    "concurrency": 8,
    "min_instances": 1,
    "max_instances": 10,
    "region": "us-central1",
    "session_service": "managed (VertexAiSessionService)"
  },
  "confidence": "inferred",
  "human_expertise_required": false,
  "rationale": "Agent gate: ADK agent on Fargate -> Agent Runtime (managed agent runtime, GEAP); sourced from google-agents-cli-deploy SKILL.md",
  "rubric_applied": ["Agent gate: eliminators PASS", "Priority rule: Agent Runtime default"]
}
```

## Examples

### Example 1 (flagship): ADK agent on ECS Fargate

- AWS: `aws_ecs_service` running a Python ADK agent (Gemini models via API key, sessions in a
  DynamoDB table) behind API Gateway -> VPC Link -> NLB, plus an ALB path.
- Eliminators: PASS (no K8s mandate — the only eliminator).
- -> **GCP: Agent Runtime** (`deployment_tool: "agents-cli"`, `no_terraform_emit: true`); DynamoDB
  sessions -> managed Sessions; trade-off card shown with Agent Runtime as "Recommended (default)"
  (headless: default). Confidence: `inferred`.

### Example 2: ADK agent on EC2

- AWS: `aws_instance` hosting the same agent (launched from `user_data`).
- The `aws_instance` Conditions exception in `fast-path.md` routes it here instead of the
  deterministic Compute Engine mapping.
- Eliminators: PASS -> **GCP: Agent Runtime**. Confidence: `inferred`.

## Post-placement governance

After placement, map any AWS-side controls found on the agent's path (API GW authorizers, task-role
scoping, egress SGs/proxies, Bedrock Guardrails) to the GCP governance suite — **Agent Registry,
Agent Gateway (ingress + zero-trust egress), Agent Identity, IAP/IAM per-tool authorization, Model
Armor** — per `design-refs/agent-governance.md`. Registration in Agent Registry is the post-deploy
baseline even when no such controls were found.

## Cross-references

- Detection: `references/phases/discover/discover-app-code.md` Steps 3 and 6B.
- Interception: `references/phases/design/design-infra.md` Pass 2 agent gate;
  `fast-path.md` Preferred-target agent row and the `aws_instance` Conditions exception.
- Placement record: `references/phases/design/design-ai.md` Part 4B -> `agent_placement[]`.
- Artifacts: `references/phases/generate/generate-artifacts-ai.md` Step 3D emits the agents-cli
  redeploy runbook; `references/phases/generate/generate-artifacts-infra.md` emits NO Terraform for
  `gcp_service: "Agent Runtime"` resources.
