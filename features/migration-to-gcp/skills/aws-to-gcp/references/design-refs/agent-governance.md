# Agent Governance on GCP — Registry, Gateway, Policies

**Applies to:** every workload that lands on **Agent Runtime** via `design-refs/agent-runtime.md`
(and, where noted, agents redirected to Cloud Run/GKE). This file is the AWS -> GCP mapping layer
for the governance controls that surrounded the agent on AWS; the governed-deploy mechanics live in
the companion skills (`google-agents-cli-deploy` for gateway binding, `google-agents-cli-publish`
for registration).

Sources: the GEAP Govern docs (`docs.cloud.google.com/gemini-enterprise-agent-platform/govern`) and
the two Agent Gateway egress codelabs (`agw-cuj-arun-egress-gmcp`, `cloudnet-agent-gateway`) —
verified 2026-08-28; surfaces are moving (several commands are `alpha`/`beta`) — re-verify at
design time.

## The governance ideology (the mental model — lead with THIS, not product names)

GCP's Govern surface is a "centralized command center" for admins and security teams, organized
around **four pillars**: **Visibility** (Registry catalog + live topology of agent relationships),
**Identity and Access** (Agent Identity + IAM/IAP per-tool authorization), **Security and
Compliance** (Model Armor, semantic governance, DLP, audit trail), and **Operational Oversight**
(gateway logs, observability dashboard, policy logs). The principles underneath:

1. **Agents are first-class principals, not shared service accounts.** Each agent gets its own
   SPIFFE identity; policy attaches to _the agent_, so blast radius and audit are per-agent —
   every hop from user to model is authenticated and policy-driven (zero trust for agents).
2. **Deny-by-default through a catalog.** The Registry is not documentation — it is the
   enforcement boundary: a destination (API endpoint, MCP server, agent) that isn't registered is
   blocked at the gateway before any authorization logic runs. Governance starts with inventory.
3. **Policy at the choke point, not in agent code.** The Gateway is the single entry/exit for
   agent traffic so security admins enforce centrally while developers never touch networking
   primitives or embed policy in prompts/tools — separation of duties by architecture.
4. **Two policy planes**: _who may call what_ (REQUEST_AUTHZ — identity/IAM, per-tool CEL
   conditions like read-only) and _what may flow_ (CONTENT_AUTHZ — Model Armor screening of
   prompts/responses, DLP redaction). Semantic governance adds a third check: does the action
   match the user's intent and org constraints.
5. **Observe, then enforce.** Governance ships in DRY_RUN first; enforcement is flipped only
   after real traffic has been observed ALLOWED in logs — governance rollout is itself a
   migration with a validation gate, never a big-bang.

When presenting a design to the user, map their governance _requirements_ to these principles
first, then name the components that implement them (table below).

## The governance suite (what exists)

| Component                        | What it is                                                                                                                                                                                                                                                         | Surface (as of 2026-08)                                                                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Agent Registry**               | Centralized catalog of agents, MCP servers, tools, and API endpoints, org-wide, with a live topology view of agent relationships and traffic. Unregistered destinations are DENIED at the gateway.                                                                 | `gcloud [alpha] agent-registry` (`agents`, `endpoints`, `mcp-servers`, `services`)                                                                                                    |
| **Agent Gateway**                | The network entry/exit point for agent interactions. Two paths: **Client-to-Agent** (ingress) and **Agent-to-Anywhere** (egress zero-trust outbound proxy). Routes traffic from Agent Runtime AND Gemini Enterprise; VPC egress via a customer network attachment. | `gcloud [alpha] network-services agent-gateways import/describe` (YAML with `protocols: [MCP]`, registry reference, `governedAccessPath`)                                             |
| **Agent Identity**               | Per-agent SPIFFE-based principal (mTLS); every hop user->model is authenticated and policy-driven. Deploy-time opt-in.                                                                                                                                             | deploy flag `--enable-agent-identity`; engine `identity_type: AGENT_IDENTITY`; registry auto-records `RuntimeIdentity`                                                                |
| **IAM / IAP authorization**      | Per-tool egress authorization: the agent principal needs `roles/iap.egressor` on registry resources; CEL conditions on attributes like `iap.googleapis.com/mcp.toolName` and `mcp.tool.isReadOnly` give per-tool / read-only grants.                               | `gcloud [beta] service-extensions authz-extensions import` + `network-security authz-policies` (`REQUEST_AUTHZ`), `gcloud beta iap web set-iam-policy --resource-type=agent-registry` |
| **Model Armor**                  | Content screening on the gateway (prompt injection, jailbreak, PII/SDP with DLP inspect+redact templates), as a `CONTENT_AUTHZ` service extension.                                                                                                                 | authz-extension against `modelarmor.<region>.rep.googleapis.com`                                                                                                                      |
| **Semantic governance policies** | Policy layer asserting agent actions match user intent and org constraints ("Governing Agent Skills"), with policy logs.                                                                                                                                           | Govern console + policy logs                                                                                                                                                          |
| **IAM Conditions on state**      | Access control on Sessions and Memory Bank.                                                                                                                                                                                                                        | IAM Conditions                                                                                                                                                                        |

## AWS -> GCP governance mapping

| AWS-side control (discovered)                                  | GCP governance construct                                                                                                   |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| API Gateway authorizer / resource policy in front of the agent | Agent Gateway **Client-to-Agent** path + IAP/IAM `REQUEST_AUTHZ`                                                           |
| IAM task role scoping what the agent may call                  | **Agent Identity** + `roles/iap.egressor` per registry resource (per-tool CEL conditions)                                  |
| VPC endpoints / egress SG rules / proxy allowlists             | Agent Gateway **Agent-to-Anywhere** egress + Agent Registry allowlist (unregistered = denied)                              |
| WAF / Bedrock Guardrails on prompts and responses              | **Model Armor** `CONTENT_AUTHZ` on the gateway (+ DLP templates for PII redaction)                                         |
| Config-drift / inventory tooling for bots and integrations     | **Agent Registry** topology view                                                                                           |
| CloudTrail on agent API calls                                  | Gateway logs (`resource.type="networkservices.googleapis.com/Gateway"`, ALLOWED/DENIED per MCP `tools/call`) + audit trail |

## Binding rules for this skill

1. **Design:** when `agent_workloads[]` is non-empty AND discovery found any of the AWS-side
   controls above on the agent's path, add a `governance` note to the placement rationale and map
   the control per the table — do not silently drop a control the estate had. When none were found,
   still record Agent Registry registration as the post-deploy step (registration is the
   prerequisite for everything else).
2. **Generate (runbook):** the Step 3D runbook's governance item stages the rollout the way the
   codelabs do — **deploy → register → DRY_RUN → enforce**: register endpoints/MCP servers in
   Agent Registry first, run IAP authz extensions with `iamEnforcementMode: "DRY_RUN"` +
   `failOpen: true` while validating, and only then switch to enforced (`failOpen: false`). Never
   generate a runbook that flips enforcement on before the agent's tool calls have been observed
   ALLOWED in dry-run logs.
3. **Terraform boundary:** the second codelab provisions the whole governance stack (~40 resources)
   via Terraform — that is a valid customer path, but this plugin emits **no Terraform for
   governance resources** (same rule as the Agent Runtime engine itself); the runbook carries the
   gcloud/agents-cli commands and cites this file.
4. **Gemini Enterprise surfacing:** registering the agent for the business-user Agent Gallery is
   `agents-cli publish gemini-enterprise` — see `google-agents-cli-publish`. Gateway ingress from
   Gemini Enterprise is governed by the same registry + policies.

## Cross-references

- Placement: `design-refs/agent-runtime.md` (this file is its governance annex; IAP-in-front is a
  NON-eliminator precisely because this stack exists).
- Deploy-time binding: `google-agents-cli-deploy` SKILL.md ("binding an agent to an Agent
  Gateway"); flags observed live: `--enable-agent-identity`, `--agent-gateway[-egress]=<uri>`,
  `--allow-token-sharing`.
- Registration/fleet: `google-agents-cli-publish` (Agent Registry fleet management, Gemini
  Enterprise registration).
