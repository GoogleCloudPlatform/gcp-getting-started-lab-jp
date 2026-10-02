# j6-fargate-agentic-rag — policy copilot (agentic RAG on ECS Fargate)

A fictional mid-size logistics company runs an internal **policy copilot**: a
[google-adk](https://google.github.io/adk-docs/) agent that answers staff
questions strictly from the company's policy knowledge base, working each
question as a retrieval loop — search, judge the hits, reformulate and search
again, then answer with citations like `[EXP-100 §2]`.

This is the **agent-workload** counterpart to `j4-fargate-ai-chatbot`: j4 is a
plain FastAPI service making one direct Bedrock SDK call per request; this
journey hosts a real agent framework with tools, a retrieval loop, and a
conversation store — the combination that changes its GCP landing zone.

## Stack

| Piece              | Implementation                                                                                                                                      |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Agent              | google-adk `Agent` with three function tools (`search_kb`, `lookup_document`, `browse_topics`)                                                      |
| Model binding      | **Bedrock via LiteLLM** — `LiteLlm(model="bedrock/jp.anthropic.claude-sonnet-4-6")`, task-role credentials, no API key anywhere                        |
| Answer modes       | `pipeline` (default): the retrieval loop as deterministic code, zero model calls — runs in accounts with no Bedrock quota. `model`: the live agent. |
| Knowledge base     | RDS **PostgreSQL 16** — full-text search (generated `tsvector` + GIN) with a `pg_trgm` fuzzy assist; no vector store, no embedding model            |
| Conversation store | DynamoDB `arc-conversations`, one item per turn (composite key + TTL); recent turns are replayed into the model's context                           |
| Hosting            | ECS Fargate service behind an ALB, ECR image, credentials in Secrets Manager, default VPC                                                           |

## Deploy / verify / tear down

Requires `~/.aws/journeys.env` (`EXPECTED_ACCOUNT_ID`, `AUTOTEARDOWN_DATE`).

```bash
./scripts/deploy.sh                       # terraform + image + service (~10 min, RDS is the long pole)
./scripts/bootstrap-kb.sh                 # schema + the 10-document policy corpus
./scripts/smoke-test.sh "$BASE_URL"       # 11 assertions; check 5 proves the retry loop
./scripts/teardown.sh
```

The smoke test only speaks HTTP, so the identical script must pass against
any re-platformed deployment of this workload.

## Run the migration skill against this journey

```bash
cd user-journey-tests/aws/j6-fargate-agentic-rag

claude --plugin-dir ../../../features/migration-to-gcp
# then: "migrate from AWS to GCP"

# or headless:
claude --plugin-dir ../../../features/migration-to-gcp -p "migrate from AWS to GCP" \
  --permission-mode acceptEdits
```

Things a correct run should get right:

- Discovery must detect the **agent framework** (google-adk imports, LiteLLM
  in the dependency set) and the conversation store, not just "a container
  calling an LLM".
- The agent's model binding is a **Bedrock** route — the design has to carry
  a model decision for it, and generated artifacts must not quietly port AWS
  credentials to make the old binding keep working.
- The knowledge base is plain Postgres full-text search — there is no vector
  database in this estate, and none should be invented for it.
