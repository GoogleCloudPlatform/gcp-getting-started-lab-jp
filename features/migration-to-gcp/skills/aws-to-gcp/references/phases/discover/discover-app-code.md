# Discover Phase: App Code Discovery

## Contents

- Step 0: Self-Scan for Source Code
- Step 0.5: Auth SDK Exclusion List
- Step 1: Detect AWS SDK Imports
- Step 2: Infer Resources from Code
- Step 3: Flag AI Signals
- Step 4: AI Detection Gate
- Step 5: Extract AI Model Details
- Step 6: Map Integration Patterns
- Step 6B: Map Agent Workloads
- Step 7: Capture Supporting Infrastructure
- Step 8: Generate ai-workload-profile.json
- Output Validation Checklist — ai-workload-profile.json
- Design Phase Integration
- Step 9: Extract Routing Topology to `app-routes.json`
- Scope Boundary

> Self-contained application code discovery sub-file. Scans for source code, detects AWS SDK imports, infers resources, flags AI signals, and if AI confidence >= 70%, extracts detailed AI workload information and generates `ai-workload-profile.json`.
> If no source code files are found, exits cleanly with no output.

**Dead-end handling:** If this file exits without producing artifacts (no source code found, or AI confidence < 70%), report to the parent orchestrator: what signals were found (if any), the confidence level, and that the user should provide Terraform files, CloudFormation templates, or AWS billing exports to proceed with migration planning.

**Execute ALL steps in order. Do not skip or optimize.**

---

## Step 0: Self-Scan for Source Code

Recursively scan the entire target directory tree for source code and dependency manifests:

**Source code:**

- `**/*.py` (Python)
- `**/*.js`, `**/*.ts`, `**/*.jsx`, `**/*.tsx` (JavaScript/TypeScript)
- `**/*.go` (Go)
- `**/*.java` (Java)
- `**/*.php` (PHP)
- `**/*.scala`, `**/*.kt`, `**/*.rs` (Other)

**Dependency manifests:**

- `requirements.txt`, `setup.py`, `pyproject.toml`, `Pipfile` (Python)
- `package.json`, `package-lock.json`, `yarn.lock` (JavaScript)
- `go.mod`, `go.sum` (Go)
- `pom.xml`, `build.gradle` (Java)
- `composer.json`, `composer.lock` (PHP)
- `Cargo.toml`, `Cargo.lock` (Rust)

**Scan exclusions (all languages):** NEVER scan dependency-install directories for imports, AI signals, or routes — `vendor/` (Composer), `node_modules/`, `.venv/` / `venv/` / `**/site-packages/`, `target/` (Maven/Cargo), `build/`, `dist/`, `.terraform/`. Library source triggers thousands of false positives (e.g. a committed `vendor/` tree contains every `Aws\*Client` class definition). Dependency evidence comes from the manifests/lockfiles above — a committed `vendor/` directory is still excluded from code scanning; read `composer.json`/`composer.lock` instead. First-party code only.

**Exit gate:** If NO source code files or dependency manifests are found, **exit cleanly**. Return no output artifacts. Other sub-discovery files may still produce artifacts.

---

## Step 0.5: Auth SDK Exclusion List

Before scanning for AWS imports, check for third-party auth SDK imports. These are **recognized but excluded** from migration — they carry no GCP recommendation.

| Import Pattern                                                                                               | Auth Provider      |
| ------------------------------------------------------------------------------------------------------------ | ------------------ |
| `auth0` / `@auth0/` / `auth0-python` / `auth0/auth0-php`                                                     | Auth0              |
| `@supabase/supabase-js` / `supabase` (with `.auth`)                                                          | Supabase Auth      |
| `firebase-admin` (with `.auth`) / `firebase/auth` / `@angular/fire/auth` / `kreait/firebase-php` (with Auth) | Firebase Auth      |
| `@clerk/` / `clerk-sdk-python`                                                                               | Clerk              |
| `@okta/` / `okta-sdk-python` / `okta-jwt-verifier`                                                           | Okta               |
| `keycloak` / `@keycloak/keycloak-admin-client` / `python-keycloak`                                           | Keycloak           |
| `next-auth` / `@auth/core`                                                                                   | NextAuth / Auth.js |

If any auth SDK import is detected:

1. Log: "Detected [provider] auth SDK in [file] — excluded from migration scope. Keep your existing auth solution."
2. Do **not** infer an AWS resource or recommend a GCP replacement
3. Do **not** include in the AI signal scan or any output artifact

## Step 1: Detect AWS SDK Imports

Scan source files for AWS service imports:

- `boto3`, `botocore` (Python: `import boto3`, `from botocore...`)
- `@aws-sdk/*` (JS/TS: `import { S3Client } from '@aws-sdk/client-s3'`)
- `aws-sdk` (JS legacy: `const AWS = require('aws-sdk')`)
- `github.com/aws/aws-sdk-go` (Go: `import "github.com/aws/aws-sdk-go/service/s3"`)
- `github.com/aws/aws-sdk-go-v2` (Go v2: `import "github.com/aws/aws-sdk-go-v2/service/s3"`)
- `software.amazon.awssdk` (Java: `import software.amazon.awssdk.services.s3.*`)
- `com.amazonaws` (Java legacy: `import com.amazonaws.services.s3.*`)
- `aws/aws-sdk-php` (PHP: `use Aws\S3\S3Client;`, `new Aws\Sdk([...])`, `$sdk->createS3()`; Laravel bridge `aws/aws-sdk-php-laravel`)
- `aws-sdk-rust` / `aws-sdk-*` (Rust: `use aws_sdk_s3`)

For each import found, record:

- `file_path` — Source file containing the import
- `import_statement` — The actual import line
- `inferred_aws_service` — Which AWS service this maps to
- `confidence` — 0.60-0.80 (lower than IaC since we're inferring from code, not reading config)

---

## Step 2: Infer Resources from Code

Map SDK imports to likely AWS resources. These are inferred — they supplement IaC evidence but at lower confidence:

| Import pattern                                                              | Inferred AWS resource        |
| --------------------------------------------------------------------------- | ---------------------------- |
| `boto3.client('s3')` / `@aws-sdk/client-s3` / `aws_sdk_s3`                  | S3 bucket                    |
| `boto3.client('dynamodb')` / `@aws-sdk/client-dynamodb`                     | DynamoDB table               |
| `boto3.client('sqs')` / `@aws-sdk/client-sqs`                               | SQS queue                    |
| `boto3.client('sns')` / `@aws-sdk/client-sns`                               | SNS topic                    |
| `boto3.client('lambda')` / `@aws-sdk/client-lambda`                         | Lambda function              |
| `boto3.client('ecs')` / `@aws-sdk/client-ecs`                               | ECS service                  |
| `boto3.client('eks')` / `@aws-sdk/client-eks`                               | EKS cluster                  |
| `boto3.client('rds')` / `@aws-sdk/client-rds`                               | RDS instance                 |
| `boto3.client('secretsmanager')` / `@aws-sdk/client-secrets-manager`        | Secrets Manager secret       |
| `boto3.client('kinesis')` / `@aws-sdk/client-kinesis`                       | Kinesis stream               |
| `boto3.client('stepfunctions')` / `@aws-sdk/client-sfn`                     | Step Functions state machine |
| `boto3.client('cloudfront')` / `@aws-sdk/client-cloudfront`                 | CloudFront distribution      |
| `boto3.client('cognito-idp')` / `@aws-sdk/client-cognito-identity-provider` | Cognito user pool            |
| `redis` / `ioredis` / `predis/predis` / `new Redis()` (phpredis)            | ElastiCache Redis instance   |

**PHP (`aws/aws-sdk-php`):** every service above appears as `Aws\<Namespace>\<Namespace>Client` (`Aws\S3\S3Client`, `Aws\DynamoDb\DynamoDbClient`, `Aws\Sqs\SqsClient`, `Aws\SecretsManager\SecretsManagerClient`, `Aws\CognitoIdentityProvider\CognitoIdentityProviderClient`, ...) or via the `$sdk->create<Namespace>()` factory — map to the same inferred resources at the same confidence.

Confidence for inferred resources: 0.60-0.80 (inferring existence, not reading infrastructure config).

---

## Step 3: Flag AI Signals

Scan source code files and dependency manifests for AI-relevant patterns. For each match, record the pattern, file location, and confidence score.

| Pattern                                        | What to look for                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Confidence |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| 2.1 Bedrock Runtime SDK                        | Imports: `boto3.client('bedrock-runtime')`, `@aws-sdk/client-bedrock-runtime`, `github.com/aws/aws-sdk-go-v2/service/bedrockruntime`, `software.amazon.awssdk.services.bedrockruntime`, `Aws\BedrockRuntime\BedrockRuntimeClient` (PHP)                                                                                                                                                                                                                                                                                                      | 95%        |
| 2.2 Bedrock Agent SDK                          | Imports: `boto3.client('bedrock-agent-runtime')`, `@aws-sdk/client-bedrock-agent-runtime`, `Aws\BedrockAgentRuntime\BedrockAgentRuntimeClient` (PHP)                                                                                                                                                                                                                                                                                                                                                                                         | 95%        |
| 2.3 SageMaker SDK                              | Imports: `import sagemaker`, `from sagemaker import`, `boto3.client('sagemaker')`, `@aws-sdk/client-sagemaker`, `software.amazon.awssdk.services.sagemaker`, `Aws\SageMaker\SageMakerClient` / `Aws\SageMakerRuntime\SageMakerRuntimeClient` (PHP)                                                                                                                                                                                                                                                                                           | 95%        |
| 2.4 LLM SDKs (OpenAI)                          | Imports: `openai`, `from openai import OpenAI`, `client.chat.completions.create()`, PHP `openai-php/client` (`OpenAI::client(...)` / `$client->chat()->create()`), model strings (`gpt-4o`, `gpt-4.1`, `o3`, etc.)                                                                                                                                                                                                                                                                                                                           | 98%        |
| 2.5 LLM SDKs (Anthropic)                       | Imports: `anthropic`, `from anthropic import Anthropic`, `client.messages.create()`, model strings (`claude-*`)                                                                                                                                                                                                                                                                                                                                                                                                                              | 98%        |
| 2.6 LLM SDKs (Other)                           | Imports: `cohere`, `mistralai`, `google.generativeai`, other LLM provider SDKs                                                                                                                                                                                                                                                                                                                                                                                                                                                               | 98%        |
| 2.7 Comprehend/Rekognition/Textract            | Imports: `boto3.client('comprehend')`, `boto3.client('rekognition')`, `boto3.client('textract')`, `boto3.client('translate')`, `boto3.client('polly')`, `boto3.client('transcribe')`, `boto3.client('lex-runtime')` and equivalent `@aws-sdk/client-*` imports                                                                                                                                                                                                                                                                               | 90%        |
| 2.8 Embeddings & RAG                           | `langchain` + `BedrockEmbeddings`; `llama_index` + Bedrock; vector database usage with embeddings                                                                                                                                                                                                                                                                                                                                                                                                                                            | 85%        |
| 2.9 Google ADK (Agent Development Kit)         | Imports/deps: Python `from google.adk` / `google-adk` in manifests; TypeScript `@google/adk`; Go `google.golang.org/adk/v2` (v1: `google.golang.org/adk`); Java/Kotlin Maven group `com.google.adk` (artifacts `google-adk`, `google-adk-dev`, `google-adk-kotlin-core`), imports `com.google.adk.*`. **There is NO PHP ADK** (verified 2026-08-28: ADK ships Python/TS/Go/Java only) — a PHP agent is never a 2.9 hit                                                                                                                       | 95%        |
| 2.10 Agent frameworks & managed agent runtimes | `langgraph` + graph/agent constructs (`StateGraph`, `create_react_agent`); `crewai` + `Crew(`/`Agent(` definitions; `langchain` agent constructs (`AgentExecutor`, `create_*_agent` — LangChain alone is NOT an agent signal); Amazon Bedrock AgentCore clients `boto3.client('bedrock-agentcore')` / `boto3.client('bedrock-agentcore-control')` / `Aws\BedrockAgentCore*` (PHP); PHP LLPhant (`theodo-group/llphant`) agent constructs (`AutoPHP`, `FunctionRunner` loops — plain LLPhant chains/RAG are pattern 2.8, not an agent signal) | 85-90%     |

Also check dependency manifests for AI/ML SDK dependencies:

- `boto3` (with Bedrock/SageMaker usage patterns)
- `sagemaker` (SageMaker Python SDK)
- `@aws-sdk/client-bedrock-runtime` / `@aws-sdk/client-bedrock-agent-runtime`
- `@aws-sdk/client-sagemaker`
- `@aws-sdk/client-comprehend` / `@aws-sdk/client-rekognition` / `@aws-sdk/client-textract`
- `openai` (OpenAI SDK — many AWS-hosted apps use OpenAI rather than Bedrock)
- `anthropic` (Anthropic SDK)
- `litellm` (LLM router — indicates gateway usage)
- `langchain`, `langchain-aws`, `langchain-openai`, `langchain-community` (orchestration frameworks)
- `google-adk` (Python ADK) / `@google/adk` (TypeScript ADK) / `google.golang.org/adk` (Go ADK) / `com.google.adk:google-adk` (Java/Kotlin ADK)
- `langgraph` (agent graphs), `crewai` (multi-agent framework)
- `aws/aws-sdk-php` (PHP — with Bedrock/SageMaker client usage), `openai-php/client` (PHP OpenAI SDK — community-maintained; a detection pattern, never a recommendation), `theodo-group/llphant` (PHP LLM orchestration framework)

---

## Step 4: AI Detection Gate

Compute overall AI confidence from all signals found in Step 3:

```text
IF (Multiple strong signals: LLM SDK + Bedrock SDK)
  THEN confidence = 95%+ (very high)

IF (Any one strong signal: LLM SDK, Bedrock SDK, SageMaker SDK)
  THEN confidence = 90%+ (high)

IF (Any agent-framework signal: ADK import, LangGraph/CrewAI agent constructs, Bedrock AgentCore client)
  THEN confidence = 90%+ (high)

IF (Weaker signals only: Comprehend, variable patterns)
  THEN confidence = 60-70% (medium)

IF (No signals found)
  THEN confidence = 0% (no AI workload detected)
```

### False Positive Checklist

Before finalizing AI detection, verify signals are genuine:

- **DynamoDB alone is not AI** — Require Bedrock or SageMaker SDK usage. A DynamoDB table by itself is a standard database.
- **S3 alone is not AI** — Require model artifact patterns or SageMaker references. An S3 bucket by itself is standard storage.
- **Vector database alone is not AI** — Require embeddings library imports (langchain, llama-index). An OpenSearch or PostgreSQL with pgvector by itself is a regular database.
- **Framework in manifest but never imported is not an agent** — A dependency entry alone (e.g. `google-adk` in `requirements.txt`) does not count; require an active import or agent construct in code.
- **LangChain alone is not an agent** — Require agent-executor/graph constructs (`AgentExecutor`, `create_react_agent`, `StateGraph`, `Crew(`). Plain LangChain chains stay pattern 2.8.
- **Dead/commented-out code excluded** — Only count active code.

**Exit gate:** If overall AI confidence < 70%, **exit cleanly**. Do not generate `ai-workload-profile.json`. Report to the parent orchestrator: signals found, confidence level, and reason for not generating the AI profile. The inferred resources from Steps 1-2 remain available for other sub-files (e.g., discover-iac.md may use them for evidence merge). If no other sub-discoverer produces artifacts, the parent orchestrator will inform the user to provide Terraform files, CloudFormation templates, or AWS billing exports.

**If confidence >= 70%**, continue to Steps 5-8 below.

---

## Step 5: Extract AI Model Details

For each AI signal found during detection, extract model-level details:

**From application code:**

Scan files that contained AI signals for specific model information:

- **Model identifiers** — Look for model name strings passed to constructors or API calls:

  **Bedrock patterns:**
  - `client.invoke_model(modelId="anthropic.claude-sonnet-4-6")` -> model_id: `"anthropic.claude-sonnet-4-6"` (old-generation IDs like `anthropic.claude-3-sonnet-*` still appear in customer code — capture whatever the call names)
  - `client.invoke_model(modelId="amazon.titan-text-express-v1")` -> model_id: `"amazon.titan-text-express-v1"`
  - `client.invoke_model(modelId="meta.llama3-...")` -> model_id: `"meta.llama3-..."`
  - `BedrockChat(model_id="...")` (LangChain) -> model_id from parameter
  - PHP: `$client->invokeModel(['modelId' => '...'])` / `$client->converse(['modelId' => '...'])` (aws-sdk-php array args) -> model_id from the `modelId` key
  - Model string patterns: `anthropic.claude-*`, `amazon.titan-*`, `meta.llama*`, `ai21.*`, `cohere.*`, `mistral.*`, `stability.*`

  **SageMaker patterns:**
  - `sagemaker.Model(model_data="...")` -> model_id from model data
  - `Predictor(endpoint_name="...")` -> model_id: endpoint name
  - `HuggingFaceModel(...)` -> model_id from model config
  - SageMaker JumpStart model IDs

  **OpenAI patterns:**
  - `client.chat.completions.create(model="gpt-4o")` -> model_id: `"gpt-4o"`
  - `openai.ChatCompletion.create(model="gpt-4")` -> model_id: `"gpt-4"` (legacy API)
  - `client.embeddings.create(model="text-embedding-3-small")` -> model_id: `"text-embedding-3-small"`
  - PHP (`openai-php/client`): `$client->chat()->create(['model' => 'gpt-4o', ...])` / `$client->embeddings()->create([...])` -> model_id from the `model` key
  - Model strings in config files or environment variables: `OPENAI_MODEL`, `MODEL_NAME`, etc.
  - Look for model string patterns: `gpt-*`, `o1*`, `o3*`, `o4*`, `text-embedding-*`, `dall-e-*`, `whisper-*`, `tts-*`

  **Other provider patterns:**
  - `anthropic.Anthropic().messages.create(model="claude-*")` -> model_id: `"claude-*"`
  - `Agent(model="gemini-...")` / `LlmAgent(model=...)` (Google ADK) -> model_id from the `model` parameter

- **Capabilities used** — Determine from API calls and method signatures:
  - `text_generation`: `invoke_model()`, `converse()`, `messages.create()`, `chat.completions.create()`
  - `streaming`: `invoke_model_with_response_stream()`, `converse_stream()`, `stream()`, `stream=True` in OpenAI calls, async iterators
  - `function_calling`: `toolConfig=` parameter (Bedrock Converse), `tools=` (OpenAI/Anthropic), tool definitions
  - `vision`: image bytes, image URLs, or multimodal content passed as input
  - `embeddings`: `invoke_model()` with embedding model IDs, `client.embeddings.create()`, `BedrockEmbeddings`
  - `batch_processing`: batch inference jobs, bulk processing patterns
  - `json_mode`: `response_format={"type": "json_object"}` (OpenAI), structured output schemas
  - `image_generation`: `invoke_model()` with Stability AI model IDs, `client.images.generate()` (DALL-E)
  - `speech_to_text`: `boto3.client('transcribe')`, `client.audio.transcriptions.create()` (Whisper)
  - `text_to_speech`: `boto3.client('polly')`, `client.audio.speech.create()` (TTS)
  - `knowledge_base`: `retrieve()`, `retrieve_and_generate()` calls on Bedrock Agent Runtime
  - `guardrails`: `guardrailIdentifier` parameter in Bedrock calls

- **Usage context** — Infer from the combination of:
  - File path and module name (e.g., `src/search/indexer.py` -> search/indexing)
  - Class and function names (e.g., `RecommendationEngine.get_recommendations` -> recommendations)
  - Import statements (e.g., `from langchain.embeddings` -> embeddings/RAG)
  - Surrounding code context (what data flows in and out of the AI call)

**From Terraform/CloudFormation (if IaC discovery also ran):**

- Bedrock agent configurations (agent name, foundation model, instructions)
- SageMaker endpoint configurations (instance type, model data, scaling)
- Resource addresses for cross-referencing with code

**From billing data (if billing discovery also ran):**

- Which AI services have billing line items
- Monthly spend per AI service

---

## Step 6: Map Integration Patterns

Determine how the application integrates with AI services:

- **Primary SDK**: Which AWS AI SDK is used
  - `boto3` (Bedrock/SageMaker via boto3)
  - `sagemaker` (SageMaker Python SDK)
  - `@aws-sdk/client-bedrock-runtime` (Node.js Bedrock)
  - `@aws-sdk/client-sagemaker` (Node.js SageMaker)
  - `github.com/aws/aws-sdk-go-v2/service/bedrockruntime` (Go Bedrock)
  - `software.amazon.awssdk.services.bedrockruntime` (Java Bedrock)
  - `aws/aws-sdk-php` — `Aws\BedrockRuntime\*` / `Aws\SageMakerRuntime\*` (PHP Bedrock/SageMaker)

- **SDK version**: Extract from dependency files (`requirements.txt`, `package.json`, `go.mod`, `composer.json`/`composer.lock`, `Cargo.toml`, etc.)

- **Frameworks**: Does the code use orchestration frameworks?
  - LangChain (`from langchain...`)
  - LlamaIndex (`from llama_index...`)
  - Google ADK (`from google.adk...`)
  - Semantic Kernel
  - LLPhant (PHP: `use LLPhant\...`)
  - No framework (raw SDK calls)

- **Languages**: Which programming languages contain AI code?

- **Integration pattern**: Classify as one of:
  - `direct_sdk` — Direct AWS SDK calls (e.g., `bedrock_client.invoke_model()`, `sagemaker.predict()`) or OpenAI SDK calls
  - `framework` — Via LangChain, LlamaIndex, or similar
  - `rest_api` — Raw HTTP calls to Bedrock, SageMaker, or OpenAI endpoints
  - `mixed` — Combination of the above

- **Gateway/router type** (`gateway_type`): Detect whether AI calls go through a gateway, router, or framework. This critically affects migration effort (gateway users can migrate in 1-3 days vs 1-3 weeks for direct SDK).

  Scan for these patterns and classify:

  | Pattern                                                      | Gateway Type     | Evidence                           |
  | ------------------------------------------------------------ | ---------------- | ---------------------------------- |
  | `from litellm import completion` / `litellm` in dependencies | `llm_router`     | LiteLLM — multi-provider router    |
  | `base_url` containing `openrouter.ai`                        | `llm_router`     | OpenRouter — multi-provider router |
  | `portkey` imports or `x-portkey-` headers                    | `llm_router`     | Portkey — AI gateway               |
  | `helicone` imports or `x-helicone-` headers                  | `llm_router`     | Helicone — AI gateway              |
  | API Gateway, ALB, or custom proxy routing to AI endpoints    | `api_gateway`    | API gateway proxying AI calls      |
  | `from vapi_python import Vapi` / Vapi SDK                    | `voice_platform` | Vapi — voice AI platform           |
  | `bland` SDK or Bland.ai API calls                            | `voice_platform` | Bland.ai — voice AI platform       |
  | `retell` SDK or Retell API calls                             | `voice_platform` | Retell — voice AI platform         |
  | `from langchain` with provider imports                       | `framework`      | LangChain orchestration framework  |
  | `from llama_index` with provider imports                     | `framework`      | LlamaIndex orchestration framework |
  | `from google.adk` agent definitions                          | `framework`      | Google ADK orchestration framework |
  | `use LLPhant\` with provider config (PHP)                    | `framework`      | LLPhant orchestration framework    |
  | Direct SDK calls only (no router/gateway/framework)          | `direct`         | Direct API integration             |

  Set `gateway_type` to `null` if no AI signals were detected or detection is ambiguous.

Build the **capabilities summary** — a flat boolean map of which AI capabilities are actively used across all detected models:

```json
{
  "text_generation": true,
  "streaming": true,
  "function_calling": false,
  "vision": false,
  "embeddings": true,
  "batch_processing": false,
  "knowledge_base": false,
  "guardrails": false
}
```

A capability is `true` only if there is evidence from code analysis that it is actively used.

---

## Step 6B: Map Agent Workloads

For each agent-framework signal from Step 3 (rows 2.9, 2.10 — plus 2.2 when Bedrock Agents are orchestrated from code), build one `agent_workloads[]` entry (schema: `references/shared/schema-discover-ai.md`):

- `framework` — one of `adk`, `langgraph`, `crewai`, `langchain_agents`, `openai_agents`, `bedrock_agents`, `bedrock_agentcore`, `custom`. PHP agent code is always `custom` (or `bedrock_agents`/`bedrock_agentcore` when driven through those AWS services) — there is no PHP ADK/LangGraph/CrewAI; LLPhant-built agents are `custom`.
- `language` — the implementation language of the agent code (`php` is valid)
- `files[]` — files containing the agent definitions/loop
- `evidence[]` — same shape as `models[].evidence` (source, file, line, pattern)
- `aws_host` — cross-reference IaC **when discover-iac.md also ran**: match the agent code to its hosting resource (an `aws_ecs_service`/task definition whose image or name references the agent module; an `aws_instance` whose `user_data` launches it; an `aws_lambda_function` whose handler imports it). Set `{type, address}` on a confident match; otherwise `null`. Do not guess.
- `session_state` — `{store, evidence}`: `dynamodb` when agent files read/write a session-named DynamoDB table, `elasticache` when a redis client carries conversation state, `in_memory` when the framework's default in-memory sessions are used, else `unknown`. `null` when the agent is stateless.
- `model_binding` — `{model_id, via}` linking the agent to the LLM it calls: `model_id` MUST match (or be added to) a `models[]` entry; `via` is one of `native` (framework-native model string, e.g. ADK `model="gemini-..."`), `litellm` (`LiteLlm(model="bedrock/...")` — the model id inside the route string still goes into `models[]`), `langchain` (ChatBedrock/ChatOpenAI wrapper), `sdk` (hand-rolled client the agent's tools call). `null` when the binding cannot be read from code. An agent bound to a NON-Google endpoint (Bedrock, OpenAI, Azure) is still an agent workload — placement is framework-based; the model swap is the AI design's job, not a reason to skip the entry.

Set `summary.agent_workloads_detected: true` if and only if at least one entry was built. This step is inventory only — record what exists and where it runs; target recommendations are out of scope here (see Scope Boundary).

---

## Step 7: Capture Supporting Infrastructure

**Only if Terraform/CloudFormation files were found (IaC discovery also ran)**, extract AI-related infrastructure resources:

- **AI resources**: `aws_bedrockagent_agent`, `aws_bedrockagent_knowledge_base`, `aws_bedrock_guardrail` (note the AWS provider's Bedrock Agents types use the `bedrockagent_` prefix — there is no `aws_bedrock_agent`), `aws_sagemaker_endpoint`, `aws_sagemaker_model`, `aws_sagemaker_notebook_instance`, `aws_sagemaker_pipeline`, etc.
- **Supporting resources** that serve AI primaries:
  - IAM roles used by Bedrock agents or SageMaker endpoints
  - VPC configurations attached to SageMaker instances
  - Secrets Manager entries referenced by AI code (API keys, credentials)
  - S3 buckets used for model artifacts, training data, or knowledge base sources

For each resource, capture: `address`, `type`, `file`, and relevant `config`.

If no Terraform/CloudFormation files were provided, set `infrastructure: []`.

---

## Step 8: Generate ai-workload-profile.json

Load `references/shared/schema-discover-ai.md` and generate output following the `ai-workload-profile.json` schema.

**CRITICAL field names** — use EXACTLY these keys:

- `model_id` (not model_name, name)
- `service` (not service_type, aws_service)
- `detected_via` (not detection_method, source)
- `capabilities_used` (not capabilities, features)
- `usage_context` (not description, purpose)
- `pattern` in integration (not integration_type, method)
- `gateway_type` in integration (not gateway, router_type)
- `capabilities_summary` (not capabilities, feature_flags)
- `ai_source` in summary (not provider, source_provider)
- `agent_workloads` top-level array + `agent_workloads_detected` in summary (absent means false; include the array only when Step 6B produced entries)

**Determining `ai_source`:**

- `"bedrock"` — Only Bedrock SDK/models detected (patterns 2.1, 2.2)
- `"sagemaker"` — Only SageMaker SDK/models detected (pattern 2.3)
- `"openai"` — Only OpenAI SDK/models detected (pattern 2.4)
- `"anthropic"` — Only Anthropic SDK/models detected (pattern 2.5, direct — not via Bedrock)
- `"multiple"` — Multiple AI providers detected in the same codebase
- `"other"` — Other LLM providers or traditional ML only (no LLM)

**Conditional sections:**

- `current_costs` — Include ONLY if billing data was provided (billing discovery ran). Omit entirely if no billing data.
- `infrastructure` — Set to `[]` if no Terraform/CloudFormation files were provided (IaC discovery did not run).

After generating the output file, the parent `discover.md` handles the phase status update — do not update `.phase-status.json` here.

---

## Output Validation Checklist — ai-workload-profile.json

- `metadata.sources_analyzed` reflects which data sources were actually provided
- `summary.overall_confidence` matches the detection confidence from Step 4
- `summary.total_models_detected` matches the length of `models` array
- `summary.ai_source` is set correctly: `"bedrock"`, `"sagemaker"`, `"openai"`, `"anthropic"`, `"multiple"`, or `"other"` based on detected LLM SDKs
- Every entry in `models` has `model_id`, `service`, `detected_via`, `evidence`, `capabilities_used`, and `usage_context`
- `models[].detected_via` only contains sources that were actually analyzed (`"code"`, `"terraform"`, `"cloudformation"`, `"billing"`)
- `models[].evidence` array has at least one entry per source listed in `detected_via`
- `models[].capabilities_used` only lists capabilities with evidence from code analysis
- `integration.capabilities_summary` is consistent with the union of all `models[].capabilities_used`
- `integration.gateway_type` is set: one of `"llm_router"`, `"api_gateway"`, `"voice_platform"`, `"framework"`, `"direct"`, or `null`
- `infrastructure` is empty array `[]` if no Terraform/CloudFormation was provided
- `current_costs` section is present ONLY if billing data was provided; omitted entirely otherwise
- `detection_signals` matches the signals found in Step 3
- `summary.agent_workloads_detected` is `true` if and only if `agent_workloads` is present and non-empty; every entry has `framework`, `language`, `files`, and `evidence`
- All field names use EXACT required keys

---

## Design Phase Integration

The Design phase (`references/phases/design/design.md`) uses `ai-workload-profile.json`:

1. **`summary.ai_source`** — Routes to the correct design reference: `"bedrock"` → `references/design-refs/ai-bedrock-to-agent-platform.md`, `"openai"` → `references/design-refs/ai-openai-to-agent-platform.md`, `"both"` → load both relevant files, `"other"` → `references/design-refs/ai.md` (traditional ML)
2. **`models`** — Determines which Agent Platform (formerly Vertex AI) / Gemini models to recommend via the model selection decision tree
3. **`integration.capabilities_summary`** — Validates Agent Platform feature parity (e.g., if `function_calling` is `true`, the selected Agent Platform model must support tool use)
4. **`integration.pattern`** and **`integration.primary_sdk`** — Determines code migration guidance (direct SDK swap vs framework provider swap vs REST endpoint change)
5. **`integration.gateway_type`** — Determines migration effort and approach: `"llm_router"` or `"framework"` → config change (1-3 days); `"direct"` → full SDK swap (1-3 weeks)
6. **`integration.frameworks`** — If LangChain is used, migration may be simpler (swap provider, keep chains)
7. **`infrastructure`** — Identifies supporting GCP resources needed (IAM roles, VPC config)
8. **`current_costs.monthly_ai_spend`** — Baseline for cost comparison in estimate phase
9. **`agent_workloads` / `summary.agent_workloads_detected`** — Routes agent-hosting compute to the agent placement rubric (`design-refs/agent-runtime.md`) instead of the generic container mapping

---

## Step 9: Extract Routing Topology to `app-routes.json`

This step runs **regardless** of the Step 4 AI Detection Gate — it is required for the user-journey synthesis in the Generate phase, not for AI workload detection. Routes are anchored evidence (parsed from real files); never invent or infer routes that aren't declared in code.

For each detected language/framework, parse the routes file **deterministically** using the Read/Grep tools — do NOT emit a parser script:

- **Rails**: Read `config/routes.rb`. Parse `resources`, `resource`, `get`, `post`, `put`, `patch`, `delete`, `match`, `namespace`, `scope`, `root`. Each route becomes `{verb, path, controller, action, requires_auth}`. Set `requires_auth: true` when the controller (or one of its ancestors) declares `before_action :authenticate_user!` (or a project-specific equivalent like `before_action :require_login`). Record `engine` when the route comes from a mounted engine (e.g. `devise_for :users` → `engine: "devise"`).
- **Express (Node.js)**: Grep for `app.METHOD('/path', ...)` and `router.METHOD('/path', ...)` patterns where METHOD ∈ `{get, post, put, patch, delete, all}`. Capture verb, path, and the handler function name as `action`. Set `requires_auth: true` when a known auth middleware (e.g. `passport.authenticate`, `requireAuth`, `ensureAuthenticated`) appears before the handler in the same chain.
- **Django**: Read `urls.py`. Parse `path()` and `re_path()` declarations. The view callable name becomes `action`. Set `requires_auth: true` when the view is wrapped in `@login_required`, `LoginRequiredMixin`, or `permission_classes` with auth.
- **Flask**: Grep for `@app.route('/path', methods=[...])` and `@bp.route(...)` decorators. The decorated function name is `action`. Set `requires_auth: true` when `@login_required` (or equivalent) is also present.
- **FastAPI**: Grep for `@app.get`, `@app.post`, `@app.put`, `@app.patch`, `@app.delete`, `@router.<verb>` decorators. The function name is `action`. Set `requires_auth: true` when a `Depends(get_current_user)`-style auth dependency appears in the signature.
- **Sinatra**: Grep for `get '/path' do`, `post '/path' do`, etc. Handler block context is the `action`.
- **Go (chi / gin / mux)**: Grep for `r.Get("/path", handler)`, `r.POST(...)`, `mux.HandleFunc(...)` patterns. Handler function name is `action`.
- **Java Spring**: Grep for `@RequestMapping`, `@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`, `@PatchMapping`. The method name is `action` and the enclosing class is `controller`. Set `requires_auth: true` when the class or method is annotated with `@PreAuthorize`, `@Secured`, or sits behind a Spring Security config that requires auth for the path prefix.
- **Laravel (PHP)**: Read `routes/web.php`, `routes/api.php` (and any other `routes/*.php`). Parse `Route::get('/path', [Controller::class, 'method'])` and the other verbs (`post`, `put`, `patch`, `delete`, `any`, `match`); expand `Route::resource(...)` / `Route::apiResource(...)` to the standard seven/five actions. Routes declared in `routes/api.php` get the `/api` prefix. Honor `Route::prefix(...)` and `Route::group([...])` path prefixes. Set `requires_auth: true` when the route (or an enclosing group) carries `->middleware('auth')`, `'auth:sanctum'`, `'auth:api'`, or a project-equivalent auth middleware.
- **Symfony (PHP)**: Grep controllers for `#[Route('/path', methods: ['GET'])]` PHP attributes (legacy `@Route` annotations too), plus `config/routes.yaml` entries. The controller class is `controller`, the method is `action`; a class-level `#[Route]` prefix prepends to method paths. Set `requires_auth: true` when the class/method has `#[IsGranted(...)]` / `#[Security(...)]` or the path falls under an authenticated `access_control` rule in `config/packages/security.yaml`.
- **Slim (PHP)**: Grep for `$app->get('/path', ...)`, `$app->post(...)`, etc., and `$group->...` inside `$app->group('/prefix', ...)`. Handler callable/class name is `action`. Set `requires_auth: true` when an auth middleware is attached via `->add(...)` on the route or its group.

Write `$MIGRATION_DIR/app-routes.json` with this exact schema:

```json
{
  "framework": "rails",
  "framework_version": "7.1.6",
  "routes_file": "config/routes.rb",
  "routes": [
    {
      "verb": "GET",
      "path": "/dashboard",
      "controller": "DashboardController",
      "action": "index",
      "requires_auth": true
    },
    {
      "verb": "POST",
      "path": "/users",
      "controller": "Users::RegistrationsController",
      "action": "create",
      "requires_auth": false,
      "engine": "devise"
    },
    {
      "verb": "POST",
      "path": "/attachments",
      "controller": "AttachmentsController",
      "action": "create",
      "requires_auth": true
    }
  ]
}
```

**No routes file found:** If no routes file can be located for any detected framework (e.g. source code is libraries/scripts only with no HTTP layer), write `{"framework": null, "routes_file": null, "routes": []}` and continue. Do NOT fail the discover phase. The Generate phase's user-journey synthesis will detect the empty `routes[]` and skip gracefully.

**Required fields per route entry:** `verb`, `path`, `controller`, `action`, `requires_auth`. **Optional:** `engine` (when mounted from a Rack engine such as Devise).

---

## Scope Boundary

**This phase covers Discover & Analysis ONLY.**

FORBIDDEN — Do NOT include ANY of:

- GCP service names, recommendations, or equivalents
- Migration strategies, phases, or timelines
- Terraform generation for GCP
- Cost estimates or comparisons
- Effort estimates

**Your ONLY job: Inventory what exists in AWS. Nothing else.**
