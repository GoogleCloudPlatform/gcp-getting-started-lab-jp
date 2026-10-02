# j6-fargate-agentic-rag — known-good GCP reference (Agent Runtime)

Hand-made migration target for `user-journey-tests/aws/j6-fargate-agentic-rag/` (the fictional logistics company's policy copilot). This is the **answer key**: never referenced from inside the journey directory; agents under test must not find it from their cwd.

Project `aws-migration-501814` (override `GCP_PROJECT`), region `asia-northeast1`. Live-verified 2026-08-29: engine `2454606932451786752`, `deploy/05-verify.sh` 4/4.

## AWS → GCP mapping

| AWS (journey)                                                            | GCP (this reference)                                               | Notes                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ECS Fargate service `arc-policy-copilot` (FastAPI `/ask` + answer modes) | Agent Runtime engine `policy-copilot`                              | The platform serves, runs, and scales the agent; `api.py` is retired, and the `pipeline` answer mode loses its reason to exist — the live loop IS the deployment                                                                                                                                           |
| `LiteLlm(model="bedrock/jp.anthropic.claude-sonnet-4-6")`                | `model="gemini-3.7-flash"` (native string)                         | **The rebinding.** The LiteLLM wrapper and the `litellm` dependency are deleted, and the AWS geo-profile prefix has no GCP counterpart. Partner-Claude alternative: `LiteLlm(model="vertex_ai/claude-sonnet-4-6")` — 404s in this project until Model Garden access is enabled; recommend only what SERVES |
| Task-role credentials for Bedrock                                        | nothing                                                            | Agent Runtime authenticates to the model natively; **no AWS credential travels** (the runbook's `--secrets` carve-out, honored here)                                                                                                                                                                       |
| DynamoDB `arc-conversations` (item-per-turn) + prompt replay             | **Managed sessions** (platform)                                    | `memory.py` and the replay logic have no counterpart; continuity is platform state (verified via the `…/sessions` API)                                                                                                                                                                                     |
| RDS PostgreSQL 16 `arc-kb` (FTS: tsvector + GIN + pg_trgm)               | Cloud SQL PostgreSQL 16 `arc-kb`                                   | The schema and the journey's `bootstrap.py` load **verbatim** — full-text search lifts as-is; no vector store existed and none was invented                                                                                                                                                                |
| Secrets Manager JSON read via boto3 (`clients.py`)                       | `agents-cli deploy --secrets KB_CONNECTION_JSON=arc-kb-connection` | The platform injects the Secret Manager payload as an env var; the migrated `kb.py` has **no secrets client at all**                                                                                                                                                                                       |
| `search_kb` / `lookup_document` / `browse_topics` tools                  | identical                                                          | `tools.py` differs by ONE import line (package flattening)                                                                                                                                                                                                                                                 |
| ALB + SGs + ECR + Dockerfile                                             | nothing                                                            | Ingress, image, and network are platform concerns                                                                                                                                                                                                                                                          |

`copilot-overlay/` holds everything that differs from a stock `agents-cli create` scaffold: `agent.py` (model line rebound), `tools.py` (one import), `kb.py` (env-JSON credentials), `.env`. `build.sh` also copies the journey's `bootstrap.py` + corpus **verbatim** so the answer key serves the same 10 documents.

## Deploy order

```bash
cd user-journey-tests/gcp-references/aws/j6-fargate-agentic-rag

./build.sh                    # agents-cli scaffold + copilot-overlay + journey corpus loader
./deploy/01-services.sh
./deploy/02-knowledge-base.sh # Cloud SQL PG16 + connection secret + runtime-SA accessor (~10 min)
./deploy/03-load-corpus.sh    # the journey's own bootstrap, over the instance's public IP
./deploy/04-agent.sh          # agents-cli deploy --deployment-target agent_runtime --secrets …
./deploy/05-verify.sh         # 4 agent-contract checks
./deploy/99-teardown.sh
```

**The order is load-bearing, twice** (both learned live):

- The platform validates **secret access at deploy time** — 04 before 02's IAM grant fails with `code: 3 … secretAccessor`.
- A serving instance **freezes its env at start**. Deploying against a placeholder secret produces a copilot whose every tool call times out, and with scale-to-zero the bad instance can outlive your patience; 04 now refuses to run until the secret carries a real host.

One more operational fact: `agents-cli deploy` **updates the existing engine in place** when `deployment_metadata.json` is present in the staged project (an update rolls instances — which is also the fastest way to force a fresh env); it creates a new engine only when the stage dir was rebuilt from scratch.

## Verification

`deploy/05-verify.sh` asserts the agent contract (the journey's HTTP smoke test belongs to the retired FastAPI layer):

1. **Retrieval + citation** — the per-diem question runs `search_kb` and answers **65 USD** citing `[EXP-100 §2]`: the same row the AWS smoke test asserts.
2. **Honesty** — nonsense produces no fabricated `[XXX-000]` citation.
3. **Continuity** — "which team owns _that_ document?" resolves to RET-600's owner (Legal) from session history.
4. **Managed sessions** — the session id appears in the platform's `…/reasoningEngines/<id>/sessions` list.

On AWS the deployed posture is the deterministic `pipeline` loop (the lab clamps Bedrock tokens to zero); here the copilot runs its playbook **live** — in the verified run it chained `search_kb` twice and `browse_topics` before answering, exactly the loop the pipeline hard-codes.

## Cost & hygiene

Engine scales to zero; Cloud SQL is `db-f1-micro` (~$0.01/h). KB connectivity is demo-grade on purpose (public IP + 0.0.0.0/0 + TLS required, fixture data only) — production goes through the Cloud SQL connectors or PSC, the hardening the skill's runbook schedules after the lift.
