# GCP Pricing Cache

**Last updated:** 2026-04-12
**Region:** us-central1
**Currency:** USD
**Accuracy:** +-5-10% for infrastructure services (sourced from cloud.google.com/pricing pages and verified aggregators), +-15-25% for AI models (sourced from public pricing pages and provider documentation)

> Prices may vary by region and change over time. Use for estimation only. For real-time pricing, prefer `google-developer-knowledge` to find current Google Cloud pricing docs, then verify against official cloud.google.com/pricing pages. **Vertex AI** model pricing may differ between regions and inference modes. All services in this file default to **us-central1** unless noted.

---

## Compute

### Compute Engine (On-Demand, Linux)

| Instance        | vCPUs | Memory (GB) | $/hour  | $/month  |
| --------------- | ----- | ----------- | ------- | -------- |
| e2-micro        | 0.25  | 1           | 0.00838 | 6.11     |
| e2-small        | 0.5   | 2           | 0.01675 | 12.23    |
| e2-medium       | 1     | 4           | 0.03351 | 24.46    |
| e2-standard-2   | 2     | 8           | 0.06701 | 48.92    |
| e2-standard-4   | 4     | 16          | 0.13402 | 97.84    |
| e2-standard-8   | 8     | 32          | 0.26805 | 195.67   |
| n2-standard-2   | 2     | 8           | 0.09710 | 70.90    |
| n2-standard-4   | 4     | 16          | 0.19420 | 141.79   |
| n2-standard-8   | 8     | 32          | 0.38850 | 283.58   |
| n2-standard-16  | 16    | 64          | 0.77690 | 567.17   |
| n2-highmem-2    | 2     | 16          | 0.13100 | 95.64    |
| n2-highmem-4    | 4     | 32          | 0.26200 | 191.28   |
| n2-highmem-8    | 8     | 64          | 0.52410 | 382.56   |
| c2-standard-4   | 4     | 16          | 0.20880 | 152.43   |
| c2-standard-8   | 8     | 32          | 0.41760 | 304.86   |
| c3-standard-4   | 4     | 16          | 0.20160 | 147.18   |
| c3-standard-8   | 8     | 32          | 0.40322 | 294.35   |

Sustained use discounts apply automatically (up to 30% for N1/N2 after full monthly usage). Spot VMs offer 60-91% savings for fault-tolerant workloads.

### Cloud Run

| Metric             | Rate         |
| ------------------ | ------------ |
| Per vCPU-second    | $0.00002400  |
| Per GiB-second     | $0.00000250  |
| Per million requests | $0.40      |
| Free tier          | 2M requests + 180K vCPU-seconds + 360K GiB-seconds / month |

CPU always allocated (default). Minimum instances billed even when idle. Tier 2 regions: $0.00003360/vCPU-sec, $0.00000350/GiB-sec.

### Cloud Functions (Cloud Run functions)

| Metric                       | Rate                               |
| ---------------------------- | ---------------------------------- |
| Per invocation               | $0.0000004                         |
| Per GB-second (memory)       | $0.0000025                         |
| Per GHz-second (CPU)         | $0.0000100                         |
| Networking per GB (egress)   | $0.12                              |
| Free tier                    | 2M invocations + 400K GB-sec/month |

> **Note:** Cloud Functions (1st gen) is now branded as "Cloud Run functions (1st gen)." New deployments should use Cloud Run functions (2nd gen), which follows Cloud Run pricing above.

### GKE (Google Kubernetes Engine)

| Metric                          | Rate         |
| ------------------------------- | ------------ |
| Standard cluster management fee | $0.10/hr ($73.00/month) |
| Autopilot per vCPU-hour         | $0.0445      |
| Autopilot per GB memory-hour    | $0.0049      |
| Autopilot per ephemeral storage GB-hour | $0.00014 |
| Free tier                       | $74.40/month credits (1 Autopilot or zonal Standard cluster) |

Worker nodes billed separately as Compute Engine instances. Autopilot manages and bills per pod. Flex CUDs: 28% (1yr), 46% (3yr).

---

## Database

### Cloud SQL for PostgreSQL (On-Demand)

| Instance             | vCPUs | Memory (GB) | $/hour  |
| -------------------- | ----- | ----------- | ------- |
| db-f1-micro          | 0.6   | 0.6         | 0.0150  |
| db-g1-small          | 0.5   | 1.7         | 0.0255  |
| db-custom-1-3840     | 1     | 3.75        | 0.0500  |
| db-custom-2-7680     | 2     | 7.5         | 0.1000  |
| db-custom-4-15360    | 4     | 15          | 0.2000  |
| db-custom-8-30720    | 8     | 30          | 0.4000  |
| db-custom-16-61440   | 16    | 60          | 0.8000  |

| Storage/IO              | Rate       |
| ----------------------- | ---------- |
| SSD per GB-month        | $0.170     |
| HDD per GB-month        | $0.090     |
| Automated backup per GB | $0.080     |

High availability (regional) approximately doubles instance cost. Read replicas billed at same rate as primary. CUDs: 25% (1yr), 52% (3yr) -- excludes shared-core (db-f1-micro, db-g1-small).

### Cloud SQL for MySQL (On-Demand)

Same instance pricing as Cloud SQL for PostgreSQL. Storage and backup rates identical.

### AlloyDB for PostgreSQL

| Metric                       | Rate       |
| ---------------------------- | ---------- |
| Per vCPU-hour (all instances)| $0.06608   |
| Per GB memory-hour           | $0.0112    |
| Storage per GB-hour          | $0.0004109 (~$0.30/month) |
| Backup storage per GB-hour   | $0.000137  |

AlloyDB offers PostgreSQL compatibility with automated horizontal read scaling. Primary and read pool instances share the same per-vCPU/memory pricing. Storage is shared across all instances in a cluster. CUDs: 25% (1yr), 52% (3yr).

### Cloud Spanner

| Metric                   | Rate           |
| ------------------------ | -------------- |
| Per node-hour            | $0.90          |
| Per processing unit-hour | $0.09          |
| Storage per GB-month     | $0.30          |

Minimum 1 node (100 processing units). Multi-region costs approximately 3x single-region.

### Firestore

| Metric                           | Rate        |
| -------------------------------- | ----------- |
| Document read per 100K           | $0.030      |
| Document write per 100K          | $0.090      |
| Document delete per 100K         | $0.010      |
| Stored data per GB-month         | $0.108      |
| Free tier (daily)                | 50K reads + 20K writes + 20K deletes + 1 GB storage |

> **Note:** Pricing shown is for us-central1 (single-region). Multi-region locations (e.g., nam5) have higher rates (~$0.06/100K reads, $0.18/100K writes). Enterprise edition uses unit-based pricing (4 KiB read units, 1 KiB write units). CUDs: 20% (1yr), 40% (3yr).

### Memorystore for Redis (On-Demand)

| Tier      | Capacity (GB) | $/hour  | $/month  |
| --------- | ------------- | ------- | -------- |
| Basic M1  | 1             | 0.016   | 11.68    |
| Basic M2  | 4             | 0.065   | 47.45    |
| Basic M3  | 10            | 0.130   | 94.90    |
| Standard M1 | 1           | 0.032   | 23.36    |
| Standard M5 | 35          | 0.552   | 403.00   |

Standard tier includes automatic failover and cross-zone replication.

---

## Storage

### Cloud Storage

| Tier                           | Rate per GB-month |
| ------------------------------ | ----------------- |
| Standard (us-central1)         | $0.020            |
| Nearline                       | $0.010            |
| Coldline                       | $0.004            |
| Archive                        | $0.0012           |

> **Note (May 2026 pricing changes):** Multi-region Nearline increases from $0.010 to $0.015/GB. Multi-region Archive (us/eu) decreases from $0.004 to $0.0024/GB. Coldline Class B operations increase from $0.05 to $0.10 per 10K. Single-region rates listed above are unaffected.

| Operations                   | Rate       |
| ---------------------------- | ---------- |
| Class A (create) per 10K     | $0.05      |
| Class B (read) per 10K       | $0.004     |
| Nearline retrieval per GB    | $0.01      |
| Coldline retrieval per GB    | $0.02      |
| Archive retrieval per GB     | $0.05      |

---

## Networking

### Cloud Load Balancing

| Metric                                    | Rate       |
| ----------------------------------------- | ---------- |
| Forwarding rule per hour (first 5)        | $0.025     |
| Forwarding rule per hour (6+)             | $0.010     |
| Forwarding rule monthly (first 5)         | $18.25     |
| Data processed per GB (outbound)          | $0.008-$0.012 (varies by region) |

### Cloud NAT

| Metric                            | Rate       |
| --------------------------------- | ---------- |
| Per NAT gateway per hour          | $0.0440    |
| Per GB processed                  | $0.0440    |
| Monthly fixed (per gateway)       | $32.12     |

### Egress Pricing (Internet)

| Tier                              | Rate per GB |
| --------------------------------- | ----------- |
| 0-1 TB/month                     | $0.12       |
| 1-10 TB/month                    | $0.11       |
| 10+ TB/month                     | $0.08       |
| Intra-region (same zone)         | Free        |
| Intra-region (different zone)    | $0.01       |
| Inter-region (within US)         | $0.01       |
| Inter-region (cross-continent)   | $0.08       |

### Cloud DNS

| Metric                        | Rate       |
| ----------------------------- | ---------- |
| Managed zone per month        | $0.20      |
| Per million queries            | $0.40      |

### Cloud CDN

| Metric                         | Rate       |
| ------------------------------ | ---------- |
| Cache egress per GB (US)       | $0.08      |
| Cache fill per GB              | $0.01      |
| HTTP requests per 10K          | $0.0075    |
| HTTPS requests per 10K         | $0.01      |
| Data processing per GB (first 100 TiB) | $0.05 |
| Data processing per GB (next 400 TiB) | $0.04 |

> **Note (May 2026 pricing change):** Starting May 1, 2026, CDN Interconnect, Direct Peering, and Carrier Peering per-GiB rates increase in NA, EU, and Asia.

---

## VPC

VPC itself is free. Add-ons:

| Component                        | Rate       |
| -------------------------------- | ---------- |
| Cloud VPN tunnel per hour        | $0.05      |
| Cloud VPN tunnel monthly         | $36.50     |
| Cloud Interconnect per 10Gbps port-hour | $1.125 |
| Private Service Connect endpoint | Free       |

---

## Supporting Services

### Secret Manager

| Metric                     | Rate       |
| -------------------------- | ---------- |
| Per secret version (active) per month | $0.06 |
| Per 10K access operations  | $0.03      |

### Cloud Logging

| Metric                         | Rate       |
| ------------------------------ | ---------- |
| Log ingestion per GB (over 50 GB free) | $0.50 |
| Log storage per GB-month       | $0.01      |

### Cloud Monitoring

| Metric                          | Rate         |
| ------------------------------- | ------------ |
| Per 1K monitoring API calls     | Free (first 1M) |
| Custom metrics per time series  | $0.258/month (first 100K free) |
| Alerting notifications per month | Free (first 100) |

### Pub/Sub

| Metric                          | Rate       |
| ------------------------------- | ---------- |
| Per TiB (Message Delivery Basic) | $40.00    |
| BigQuery subscriptions per TiB  | $50.00     |
| Cloud Storage subscriptions per TiB | $50.00 |
| Import topics (Kinesis) per TiB | $50.00     |
| Import topics (GCS/EventHubs/MSK/Confluent) per TiB | $80.00 |
| Free tier                        | 10 GB/month |

> **Note:** Pub/Sub Lite is deprecated and will be turned down March 18, 2026. Migrate to standard Pub/Sub.

### Cloud Tasks

| Metric                     | Rate                    |
| -------------------------- | ----------------------- |
| Per million operations     | $0.40                   |
| Free tier                  | 1M operations/month     |

---

## Analytics

### BigQuery

| Metric                          | Rate       |
| ------------------------------- | ---------- |
| On-demand query per TiB         | $6.25      |
| Active logical storage per GiB-month | $0.020 |
| Long-term logical storage per GiB-month | $0.010 |
| Streaming inserts per 200MB     | $0.012     |
| Free tier                       | 1 TiB queries + 10 GiB storage per month |

Capacity pricing available via editions (Standard/Enterprise/Enterprise Plus). Physical (compressed) storage billing model also available for reduced costs.

> **Note (Feb 2026):** Multi-region network data transfer fees now apply when BigQuery jobs in one location read from multi-region Cloud Storage buckets.

### Dataflow

| Metric                     | Rate            |
| -------------------------- | --------------- |
| Worker per vCPU-hour       | $0.056          |
| Worker per GB-hour         | $0.003504       |
| Worker per SSD GB-hour     | $0.000054       |

---

## Vertex AI Models (On-Demand)

### Gemini Models (per 1M tokens)

| Model                    | Input $/1M | Output $/1M | Context | Tier      | Status |
| ------------------------ | ---------- | ----------- | ------- | --------- | ------ |
| Gemini 3.1 Pro Preview (<=200K) | 2.00 | 12.00 | 1M | premium | Preview; verify lifecycle before production recommendation |
| Gemini 3.1 Pro Preview (>200K)  | 4.00 | 18.00 | 1M | premium | Long-context rates |
| Gemini 3 Flash Preview        | 0.50 | 3.00  | 1M | fast    | Preview; verify lifecycle before production recommendation |
| Gemini 2.5 Pro (<=200K)  | 1.25       | 10.00       | 1M      | mid       | GA; verify current lifecycle |
| Gemini 2.5 Pro (>200K)   | 2.50       | 15.00       | 1M      | mid       | long context rates |
| Gemini 2.5 Flash         | 0.30       | 2.50        | 1M      | fast      | GA; verify current lifecycle |
| Gemini 2.5 Flash Lite    | 0.10       | 0.40        | 1M      | budget    | GA; verify current lifecycle |
| ~~Gemini 2.0 Flash~~     | ~~0.10~~   | ~~0.40~~    | ~~1M~~  | ~~fast~~  | **DEPRECATED -- shutdown June 1, 2026** |
| ~~Gemini 2.0 Flash Lite~~| ~~0.075~~  | ~~0.30~~    | ~~1M~~  | ~~budget~~| **DEPRECATED -- shutdown June 1, 2026** |
| ~~Gemini 1.5 Pro~~       | --         | --          | --      | --        | **SHUT DOWN** |
| ~~Gemini 1.5 Flash~~     | --         | --          | --      | **SHUT DOWN** |

> **DEPRECATION WARNING:** Gemini 2.0 Flash and 2.0 Flash Lite are deprecated and shut down **June 1, 2026**. Migrate to a current Gemini 2.5 or Gemini 3 model. All Gemini 1.x models are already shut down.

### Partner Models on Vertex AI (per 1M tokens)

| Model                           | Provider  | Input $/1M | Output $/1M | Context | Tier      |
| ------------------------------- | --------- | ---------- | ----------- | ------- | --------- |
| Claude Sonnet 4.6 (via Vertex)  | Anthropic | 3.00       | 15.00       | 1M      | flagship  |
| Claude Opus 4.6 (via Vertex)    | Anthropic | 5.00       | 25.00       | 1M      | premium   |
| Claude Haiku 4.5 (via Vertex)   | Anthropic | 1.00       | 5.00        | 200K    | fast      |
| Llama 4 Maverick (via Model Garden) | Meta  | 0.24       | 0.97        | 1M      | mid       |
| Llama 4 Scout (via Model Garden) | Meta     | 0.17       | 0.66        | 10M     | efficient |
| Mistral Large (via Model Garden) | Mistral  | 2.00       | 6.00        | 32K     | flagship  |

### Embeddings

| Model                               | Rate per 1M tokens |
| ------------------------------------ | ------------------- |
| text-embedding-005                   | $0.00002 per char (~$0.025/1M tokens) |
| text-multilingual-embedding-002      | $0.00002 per char   |
| Vertex AI Multimodal Embeddings      | $0.0001 per image   |

### Imagen (Image Generation)

| Metric                  | Rate              |
| ----------------------- | ----------------- |
| Standard per image      | $0.020            |
| High quality per image  | $0.040            |

---

## Source Provider Pricing (for Migration Comparison)

Use alongside GCP pricing to calculate migration ROI. These are the AWS/OpenAI prices the user is currently paying.

### Amazon Bedrock (On-Demand, per 1M tokens)

| Model                            | Input $/1M | Output $/1M | Context | Tier      | Status |
| -------------------------------- | ---------- | ----------- | ------- | --------- | ------ |
| Claude Opus 4.6 (Bedrock)       | 5.00       | 25.00       | 1M      | premium   | GA |
| Claude Sonnet 4.6 (Bedrock)     | 3.00       | 15.00       | 1M      | flagship  | GA |
| Claude Haiku 4.5 (Bedrock)      | 1.00       | 5.00        | 200K    | fast      | GA |
| Amazon Nova Pro                  | 0.80       | 3.20        | 300K    | mid       | GA |
| Amazon Nova Lite                 | 0.06       | 0.24        | 300K    | fast      | GA |
| Amazon Nova Micro                | 0.035      | 0.14        | 128K    | budget    | GA |
| Amazon Nova 2 Pro                | 1.25       | 10.00       | 260K    | premium   | **PREVIEW** (Nova Forge early access) |
| Llama 4 Maverick (Bedrock)       | 0.24       | 0.97        | 1M      | mid       | GA |
| Llama 4 Scout (Bedrock)          | 0.17       | 0.66        | 3.5M    | efficient | GA |
| DeepSeek-R1 (Bedrock)            | 1.35       | 5.40        | 128K    | reasoning | GA |
| Mistral Large 3                  | 0.50       | 1.50        | 256K    | flagship  | GA |

> **Note on Llama 4 Bedrock pricing:** Bedrock on-demand rates for Llama 4 Maverick ($0.24/$0.97) and Scout ($0.17/$0.66) are higher than third-party providers like DeepInfra ($0.15/$0.60 Maverick, $0.08/$0.30 Scout). Use third-party rates for lowest-cost comparisons.

### OpenAI (Standard Tier, per 1M tokens)

| Model              | Input $/1M | Output $/1M | Context | Tier      | Status |
| ------------------ | ---------- | ----------- | ------- | --------- | ------ |
| GPT-5.5            | 5.00       | 30.00       | unknown | frontier  | Verify live on OpenAI pricing page |
| GPT-5.4            | 2.50       | 15.00       | unknown | flagship  | Verify live on OpenAI pricing page |
| GPT-5.4 mini       | 0.75       | 4.50        | unknown | mini      | Verify live on OpenAI pricing page |
| GPT-5.2            | 1.75       | 14.00       | unknown | mid       | Verify live on OpenAI pricing page |
| GPT-5 / GPT-5.1    | 1.25       | 10.00       | unknown | mid       | Verify live on OpenAI pricing page |
| GPT-4o             | 2.50       | 10.00       | unknown | legacy    | ChatGPT retirement does not imply API retirement; verify live |
| o3                  | 2.00       | 8.00        | 200K    | reasoning | GA |
| o4-mini             | 1.10       | 4.40        | 200K    | reasoning | Verify live on OpenAI pricing page |

> **Note:** OpenAI and Vertex AI model catalogs change quickly. Always verify current API availability, model names, processing tiers, long-context surcharges, regional uplift, and batch discounts before publishing estimates.

### Amazon SageMaker

| Instance          | $/hour  | $/month  |
| ----------------- | ------- | -------- |
| ml.t3.medium      | 0.05    | 36.50    |
| ml.m5.large       | 0.115   | 83.95    |
| ml.m5.xlarge      | 0.23    | 167.90   |
| ml.g4dn.xlarge    | 0.736   | 537.28   |

---

## Staleness Note

> **Cache freshness policy:** If `Last updated` date is more than 90 days from the current date, prices should be considered stale. In that case, the agent should attempt web search for current pricing from cloud.google.com/pricing/* pages. If web search is unavailable, use these cached prices with a staleness warning: "Cached pricing data is >90 days old; accuracy may be significantly degraded."
>
> Prices in this file are approximate reference points sourced from public GCP pricing documentation and verified third-party aggregators (economize.cloud, pricepertoken.com). Actual prices may vary based on region, usage commitments, negotiated contracts, and GCP pricing updates. All infrastructure prices default to **us-central1** unless noted.
