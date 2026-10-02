# Azure SDK -> Google Cloud SDK Call-Site Map

**Loaded by:** `references/phases/discover.md` (app-code scan — the detection patterns below are what it
greps for) and `references/phases/design.md` (Step 6, per-call-site rewrite plan). Generate turns the
plan into review-only notes; this skill emits no application source code.

## Two columns, two very different confidence levels

- **Detection pattern** — the literal package/namespace/import string to grep for in the user's own
  source. This is a parsing rule, not a claim about the world: if the string is in their code, the row
  fires.
- **GCP target** — the _service_ the call site lands on, taken from Google's cross-cloud comparison
  table (https://docs.cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison, fetched
  2026-08-06) and this skill's `references/shared/service-map.md`.

**The exact client-library package name and version are NEVER written from recall.** Before any rewrite
note names an import, fetch that service's client-libraries page —
`https://docs.cloud.google.com/<service>/docs/reference/libraries` — in the same run and cite it. A
rewrite note without a same-run library-page citation is recorded as `confidence: "inferred"` with
`manual_review: true`, and Generate emits it as a `# TODO(verify):` line rather than an import.

## Master map

| Azure surface            | Detection pattern (grep)                                                                                                              | GCP target service                                             | Rewrite class                            |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------- |
| Credentials / auth       | `azure-identity`, `azure.identity`, `DefaultAzureCredential`, `ManagedIdentityCredential`, `ClientSecretCredential`, `Azure.Identity` | Application Default Credentials (ADC) + service accounts       | **deployment-time, mostly not code**     |
| Blob Storage             | `azure-storage-blob`, `azure.storage.blob`, `BlobServiceClient`, `@azure/storage-blob`, `Azure.Storage.Blobs`, `azblob`               | Cloud Storage                                                  | mechanical, per-op                       |
| Service Bus              | `azure-servicebus`, `azure.servicebus`, `@azure/service-bus`, `Azure.Messaging.ServiceBus`, `ServiceBusClient`                        | Pub/Sub or Cloud Tasks (`Q_MAP.messaging` decides)             | semantic — see sessions/DLQ below        |
| Service Bus (LEGACY)     | `WindowsAzure.ServiceBus`, `Microsoft.Azure.ServiceBus`, `com.microsoft.azure.servicebus`                                             | same as above                                                  | **flag first — retiring, see below**     |
| Event Hubs               | `azure-eventhub`, `@azure/event-hubs`, `Azure.Messaging.EventHubs`                                                                    | Pub/Sub                                                        | semantic (partitions -> ordering keys)   |
| Cosmos DB                | `azure-cosmos`, `azure.cosmos`, `@azure/cosmos`, `Microsoft.Azure.Cosmos`, `CosmosClient`                                             | Firestore / Spanner / Bigtable / AlloyDB per `Q_MAP.cosmos`    | **rewrite — data model, not just calls** |
| Key Vault (secrets)      | `azure-keyvault-secrets`, `azure.keyvault.secrets`, `@azure/keyvault-secrets`, `SecretClient`                                         | Secret Manager                                                 | mechanical                               |
| Key Vault (keys/crypto)  | `azure-keyvault-keys`, `CryptographyClient`, `KeyClient`                                                                              | Cloud KMS                                                      | mechanical, key-name shape differs       |
| Azure OpenAI             | `AzureOpenAI(`, `azure_endpoint=`, `openai.AzureOpenAI`, `Azure.AI.OpenAI`, `@azure/openai`                                           | Vertex AI                                                      | **two routes — see below**               |
| Azure AI Search          | `azure-search-documents`, `@azure/search-documents`, `Azure.Search.Documents`, `SearchClient`, `SearchIndexerClient`                  | Agent Search or a self-managed vector store per `Q_MAP.search` | **reindex, not a per-call port**         |
| Application Insights     | `applicationinsights`, `opencensus-ext-azure`, `Microsoft.ApplicationInsights`, `APPLICATIONINSIGHTS_CONNECTION_STRING`               | Cloud Trace / Cloud Monitoring / Cloud Logging                 | re-instrument via OpenTelemetry          |
| Azure Files (SDK access) | `azure-storage-file-share`, `@azure/storage-file-share`, `ShareServiceClient`                                                         | Filestore (NFS) or NetApp Volumes (SMB)                        | usually becomes a mount, not an SDK call |
| Table Storage            | `azure-data-tables`, `@azure/data-tables`, `Azure.Data.Tables`                                                                        | no comparison-table pairing                                    | **Deferred — specialist engagement**     |
| ARM control plane        | `azure-mgmt-*`, `@azure/arm-*`, `Azure.ResourceManager.*`                                                                             | Terraform / gcloud, not runtime code                           | usually delete, not port                 |

## Per-language coverage

Rows are emitted per (surface, language) pair. Coverage differs by language and the file says so
plainly rather than pretending parity:

| Language          | Detection confidence                                                                       | Rewrite guidance confidence                                                                            |
| ----------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| Python            | high — imports are unambiguous (`from azure.storage.blob import ...`)                      | high for storage/secrets; **live-verify** every library name                                           |
| Node / TypeScript | high — `@azure/*` scope is unambiguous                                                     | high for storage/secrets; **live-verify** every library name                                           |
| Go                | medium — module paths (`github.com/Azure/azure-sdk-for-go/sdk/...`) vary by SDK generation | **live-verify required** on every row                                                                  |
| .NET / C#         | medium — `Azure.*` and legacy `Microsoft.Azure.*`/`WindowsAzure.*` namespaces coexist      | **live-verify required** on every row; the legacy-vs-current split below is the first thing to resolve |
| Java              | medium — `com.azure.*` (current) vs `com.microsoft.azure.*` (legacy)                       | **live-verify required** on every row                                                                  |

For Go, .NET and Java the skill records the call site and the target service, then routes the rewrite to
a `# TODO(verify):` note citing the library page it could not confirm. It does not invent a method name.

## Legacy Service Bus SDKs — flag before mapping

The Azure Service Bus FAQ states that on **30 September 2026** Microsoft retires the SDK libraries
`WindowsAzure.ServiceBus`, `Microsoft.Azure.ServiceBus` and `com.microsoft.azure.servicebus`, along with
end of support for the **SBMP protocol**, which becomes unusable after that date; the libraries keep
functioning afterwards but receive no support or updates. The current libraries are
`Azure.Messaging.ServiceBus` (.NET) and `com.azure.messaging.servicebus` (Java) over AMQP
(https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-faq, fetched 2026-08-06).

Discovery raises `[LEGACY_SDK]` on any of those three strings. The migration consequence is real and
worth stating to the user: a codebase on a legacy Service Bus SDK is carrying a **source-side** deadline
independent of the GCP move, so "leave it on Azure for now" is not a cost-free option for that component.

## Auth: the one rewrite that is mostly not a rewrite

Azure call sites typically construct a credential explicitly (`DefaultAzureCredential()`) and hand it to
each client. Google client libraries resolve **Application Default Credentials** at construction time
without an explicit credential object, so the usual change is _deleting_ the credential plumbing rather
than translating it. Binding that identity is deployment-time work: a service account plus an IAM policy
(and, on GKE, Workload Identity Federation for GKE —
https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

Mapping of the source's identity shapes:

- **System-assigned managed identity** -> one service account per workload, bound at deploy time.
- **User-assigned managed identity shared by N workloads** -> the same sharing is possible but is a
  decision, not a default; note it and let `Q_IDENTITY` own it.
- **Client ID + client secret in config** -> a service account with no key; if the code path genuinely
  needs a credential file, that is a finding to surface, not a pattern to reproduce.
- **Entra Workload Identity Federation from AKS pods** -> Entra WIF explicitly supports GKE
  (https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation), so a pod that must
  keep reaching Entra-protected Azure resources during coexistence can keep its federated credential and
  re-point the subject to the GKE service account. Two federations then exist side by side (GKE -> Google
  IAM, GKE -> Entra); say so explicitly rather than implying one replaces the other.

## Azure OpenAI: two routes, and the shape difference is the point

**Route 1 — OpenAI-compatible endpoint (smallest diff).** Vertex AI exposes an OpenAI-compatible Chat
Completions endpoint. In the documented Python sample the client is constructed with
`base_url=f"https://{location}-aiplatform.googleapis.com/v1/projects/{project_id}/locations/{location}/endpoints/openapi"`
and `api_key=credentials.token`, where `credentials` comes from `google.auth` `default()` refreshed
through `google.auth.transport.requests`, with `model="google/gemini-2.0-flash-001"`
(https://docs.cloud.google.com/vertex-ai/generative-ai/docs/samples/generativeaionvertexai-gemini-chat-completions-non-streaming,
fetched 2026-08-06).

The shape differences that break a naive find-and-replace, stated explicitly:

1. **`api_key` is not an API key.** It is a short-lived ADC-derived OAuth token. Anything that caches
   the client for the process lifetime will start failing when the token expires — the credential must
   be refreshed, so the client construction moves inside a refresh-aware helper.
2. **The Azure `deployment name` disappears.** Azure OpenAI addresses a _deployment_ you created;
   the Vertex path addresses a _model id_ in the `model` field. Config keys named `deployment` /
   `AZURE_OPENAI_DEPLOYMENT` have no counterpart and must be re-derived.
3. **`azure_endpoint` and `api_version` disappear**, replaced by the location-bearing `base_url` above.
4. **Self-deployed Model Garden models** replace the literal `openapi` endpoint id with your own endpoint
   id; that detail is documented on the auth-and-credentials page rather than the sample page, and those
   examples use a `v1beta1` path rather than `v1` — verify which applies before writing a URL.

**Route 2 — native Vertex AI SDK.** Larger diff, full access to Vertex-native features. Choose per
`Q_MAP.ai`; do not default silently.

Content filtering, safety settings, and token accounting differ between the platforms in ways that are
not covered by either route — flag them as a functional-parity review item, never as "equivalent".

## Azure AI Search: the client you find decides the rewrite scope

`SearchClient` — queries plus document upload calls — is the **push** model: the application owns
ingestion, so the rewrite re-points those calls at whatever the `Q_MAP.search` target ingests. A
`SearchIndexerClient`, or an indexer created in the portal and therefore invisible to a code scan, is the
**pull** model: a data-source connector, a schedule, and usually a skillset. That is infrastructure to
re-architect, not call sites to translate, and the two are not interchangeable — AI enrichment and
integrated vectorization "must use the pull model (indexers) to load an index", because skillsets "are
attached to indexers and don't run independently"
(https://learn.microsoft.com/en-us/azure/search/search-what-is-data-import, fetched 2026-08-06). Record
which model the estate uses; it decides whether the work is a call-site rewrite or a pipeline rebuild.

Two discovery notes. The service endpoint is `https://<service-name>.search.windows.net`
(https://learn.microsoft.com/en-us/azure/search/search-create-service-portal), so an app setting holding
that host is often the only evidence of a search dependency in an estate with no IaC. And the previous
`Microsoft.Azure.Search` client library (v10) "is now retired"
(https://learn.microsoft.com/en-us/python/api/overview/azure/search-documents-readme) — a call site still
on it is a rewrite whichever cloud it ends up on.

## Application Insights -> OpenTelemetry

The comparison table pairs Azure Monitor with Cloud Monitoring, Azure Monitor Logs with Cloud Logging,
Application Insights with Cloud Trace, and the App Insights Profiler with Cloud Profiler. The practical
route is OpenTelemetry instrumentation exporting to Google Cloud, which decouples the app from both
vendors. Two things to record per service:

- **Custom telemetry** (`TrackEvent`, `TrackMetric`, custom dimensions) has no automatic equivalent —
  each becomes a metric descriptor or structured log field decision.
- **The connection string is deployment config, not code** — `APPLICATIONINSIGHTS_CONNECTION_STRING` in
  an app setting is a discovery signal that the workload is instrumented at all, which is often the only
  evidence available that a service emits telemetry.

## Cosmos DB call sites are a data-model rewrite

Do not emit per-operation rewrites for Cosmos DB before `Q_MAP.cosmos` has recorded a target. The call
site is the smallest part of the change: partition-key design, consistency level, change-feed consumers,
stored procedures/triggers, and the RU-based cost model all move differently per target. Discovery
records the call sites and the API flavor; Design records the chosen target and marks every row
`manual_review: true`.
