# Discover Phase: IaC (Terraform / CloudFormation) Discovery

> Self-contained IaC discovery sub-file. Scans for IaC files, extracts Terraform resources and CloudFormation stacks, classifies, builds dependency graphs, clusters, and generates output files.
> If no IaC files are found, exits cleanly with no output.

**Execute ALL steps in order. Do not skip or optimize.**

## Step 0: Self-Scan for IaC Files

Recursively scan the entire target directory tree for infrastructure files:

**Terraform:**

- `**/*.tf`, `**/*.tf.json` — resource definitions
- `**/*.tfvars`, `**/*.auto.tfvars` — variable values
- `**/*.tfstate` — state files (read-only, if present)
- `**/.terraform.lock.hcl` — lock files
- `**/modules/*/` — module directories and nested modules

**CloudFormation:**

- `**/*.json`, `**/*.yaml`, `**/*.yml`, `**/*.template` — scan for `AWSTemplateFormatVersion` or `AWS::` resource type declarations
- `**/cloudformation/`, `**/cfn/`, `**/stacks/` — common CloudFormation directory conventions
- `**/sam.yaml`, `**/sam.yml`, `**/*-template.yaml` — SAM (Serverless Application Model) templates
- `**/cdk.out/**/*.template.json` — CDK synthesized templates

**Contextual files** (recorded but not processed — useful for future discovery phases):

- **Kubernetes:** `**/k8s/*.yaml`, `**/kubernetes/*.yaml`, `**/manifests/*.yaml`
- **Docker:** `**/Dockerfile`, `**/docker-compose*.yml`
- **CI/CD:** `**/buildspec.yml`, `**/appspec.yml`, `**/.github/workflows/*.yml`, `**/.gitlab-ci.yml`, `**/Jenkinsfile`, `**/codepipeline*.json`

Record file paths and types for all files found.

**Exit gate:** If NO Terraform files (`.tf`, `.tfvars`, `.tfstate`, `.terraform.lock.hcl`) AND NO CloudFormation templates are found, **exit cleanly**. Return no output artifacts. Other sub-discovery files may still produce artifacts.

## Step 1: Extract Resources from Terraform

1. Read all `.tf`, `.tfvars`, and `.tfstate` files in working directory (recursively)
2. Extract all resources matching `aws_*` pattern (e.g., `aws_instance`, `aws_s3_bucket`, `aws_db_instance`)
3. For each resource, capture exactly:
   - `address` (e.g., `aws_instance.web`)
   - `type` (e.g., `aws_instance`)
   - `name` (resource name component, e.g., `web`)
   - `config` (object with key attributes: `instance_type`, `ami`, `region`, etc.)
   - `raw_hcl` (raw HCL text for this resource, needed for Step 4)
   - `depends_on` (array of addresses this resource depends on)
4. Also extract provider and backend configuration (for region detection)
5. Report total resources found to user (e.g., "Parsed 50 AWS resources from 12 Terraform files")

## Step 1b: Extract Resources from CloudFormation

If CloudFormation templates were found (Step 0), also extract resources from them:

1. Read all CloudFormation template files
2. Parse the `Resources` section of each template
3. For each resource, capture exactly:
   - `address` — the **Terraform-normalized** address, constructed as `<normalized_type>.<logical_id>` (e.g. `aws_instance.WebServer`, `aws_rds_cluster.ProductionAuroraCluster`). Use the **CloudFormation type normalization map** below to convert the CFN `AWS::Service::Type` to the Terraform-style type, then join with `.` + the logical ID **exactly as it appears in the template** (preserve CamelCase — do not lowercase or snake_case the logical ID). **This `address` field MUST NEVER be the raw CFN form `AWS::EC2::Instance.WebServer`** — downstream phases (Design ADRs, Generate Terraform labels) read this field expecting Terraform-style.
   - `cfn_address` — the raw CloudFormation form (`AWS::EC2::Instance.WebServer`), preserved as a separate field for traceability so downstream phases can still cite the source template's logical-id form when useful (e.g. in user-facing summaries). Optional but recommended on every CFN-sourced resource.
   - `type` (e.g., `aws_instance` — normalize CloudFormation `AWS::EC2::Instance` to Terraform-style type for uniform downstream processing)
   - `name` (logical ID from the template, e.g., `WebServer`)
   - `config` (object with key `Properties` values: `InstanceType`, `ImageId`, etc.)
   - `raw_cfn` (raw JSON/YAML text for this resource)
   - `depends_on` (array of addresses — same Terraform-normalized form — from `DependsOn` declarations and `Ref`/`Fn::GetAtt` references)
   - `source_format` (`"cloudformation"` — distinguishes from Terraform resources)
4. Also extract `Parameters`, `Outputs`, and `Mappings` sections (for region and config detection)
5. Report total resources found to user (e.g., "Parsed 30 AWS resources from 5 CloudFormation templates")

**CloudFormation type normalization map** (convert to Terraform-style types for uniform processing):

| CloudFormation Type | Normalized Type |
| --- | --- |
| `AWS::EC2::VPC` | `aws_vpc` |
| `AWS::EC2::Subnet` | `aws_subnet` |
| `AWS::EC2::SecurityGroup` | `aws_security_group` |
| `AWS::EC2::SecurityGroupIngress` | `aws_security_group_rule` |
| `AWS::EC2::SecurityGroupEgress` | `aws_security_group_rule` |
| `AWS::EC2::RouteTable` | `aws_route_table` |
| `AWS::EC2::SubnetRouteTableAssociation` | `aws_route_table_association` |
| `AWS::EC2::InternetGateway` | `aws_internet_gateway` |
| `AWS::EC2::NatGateway` | `aws_nat_gateway` |
| `AWS::EC2::EIP` | `aws_eip` |
| `AWS::EC2::VPCEndpoint` | `aws_vpc_endpoint` |
| `AWS::EC2::Instance` | `aws_instance` |
| `AWS::S3::Bucket` | `aws_s3_bucket` |
| `AWS::RDS::DBInstance` | `aws_db_instance` |
| `AWS::RDS::DBSubnetGroup` | `aws_db_subnet_group` |
| `AWS::RDS::DBParameterGroup` | `aws_db_parameter_group` |
| `AWS::RDS::DBCluster` | `aws_rds_cluster` |
| `AWS::EKS::Cluster` | `aws_eks_cluster` |
| `AWS::EKS::Nodegroup` | `aws_eks_node_group` |
| `AWS::Lambda::Function` | `aws_lambda_function` |
| `AWS::ECS::Service` | `aws_ecs_service` |
| `AWS::ECS::TaskDefinition` | `aws_ecs_task_definition` |
| `AWS::ECS::Cluster` | `aws_ecs_cluster` |
| `AWS::SQS::Queue` | `aws_sqs_queue` |
| `AWS::SNS::Topic` | `aws_sns_topic` |
| `AWS::DynamoDB::Table` | `aws_dynamodb_table` |
| `AWS::ElastiCache::CacheCluster` | `aws_elasticache_cluster` |
| `AWS::ElastiCache::ReplicationGroup` | `aws_elasticache_replication_group` |
| `AWS::ElastiCache::SubnetGroup` | `aws_elasticache_subnet_group` |
| `AWS::Redshift::Cluster` | `aws_redshift_cluster` |
| `AWS::CloudFront::Distribution` | `aws_cloudfront_distribution` |
| `AWS::ApiGateway::RestApi` | `aws_api_gateway_rest_api` |
| `AWS::ApiGatewayV2::Api` | `aws_apigatewayv2_api` |
| `AWS::Kinesis::Stream` | `aws_kinesis_stream` |
| `AWS::StepFunctions::StateMachine` | `aws_sfn_state_machine` |
| `AWS::Cognito::UserPool` | `aws_cognito_user_pool` |
| `AWS::ElasticLoadBalancingV2::LoadBalancer` | `aws_lb` |
| `AWS::ElasticLoadBalancingV2::TargetGroup` | `aws_lb_target_group` |
| `AWS::ElasticLoadBalancingV2::Listener` | `aws_lb_listener` |
| `AWS::AutoScaling::AutoScalingGroup` | `aws_autoscaling_group` |
| `AWS::EFS::FileSystem` | `aws_efs_file_system` |
| `AWS::IAM::Role` | `aws_iam_role` |
| `AWS::IAM::Policy` | `aws_iam_policy` |
| `AWS::IAM::InstanceProfile` | `aws_iam_instance_profile` |
| `AWS::KMS::Key` | `aws_kms_key` |
| `AWS::SecretsManager::Secret` | `aws_secretsmanager_secret` |
| `AWS::SSM::Parameter` | `aws_ssm_parameter` |
| `AWS::Logs::LogGroup` | `aws_cloudwatch_log_group` |
| `AWS::CloudWatch::Alarm` | `aws_cloudwatch_metric_alarm` |
| `AWS::Events::Rule` | `aws_cloudwatch_event_rule` |
| `AWS::Route53::HostedZone` | `aws_route53_zone` |
| `AWS::Route53::RecordSet` | `aws_route53_record` |
| `AWS::SageMaker::NotebookInstance` | `aws_sagemaker_notebook_instance` |
| `AWS::Bedrock::Agent` | `aws_bedrock_agent` |
| General pattern: `AWS::ServiceName::ResourceType` | `aws_servicename_resourcetype` (lowercase, underscored) only after checking known Terraform provider type exceptions |

Merge Terraform and CloudFormation resources into a single resource list for downstream processing. If a resource appears in both sources (same logical resource), prefer the Terraform definition and record `source_format: "terraform"`.

## Step 2: Flag AI Signals

Scan all `.tf` files and CloudFormation templates for AI-relevant patterns. For each match, record the pattern, file location, and confidence score.

| Pattern | What to look for | Confidence |
| --- | --- | --- |
| Bedrock resources | `aws_bedrock_*` resource types (`_agent`, `_knowledge_base`, `_guardrail`, `_model_invocation_logging_configuration`, `_custom_model`); CloudFormation `AWS::Bedrock::*` | 95% |
| SageMaker resources | `aws_sagemaker_*` resource types (`_endpoint`, `_model`, `_notebook_instance`, `_training_job`, `_pipeline`, `_feature_group`); CloudFormation `AWS::SageMaker::*` | 95% |
| Comprehend resources | `aws_comprehend_*` resource types; CloudFormation `AWS::Comprehend::*` | 85% |
| Rekognition resources | `aws_rekognition_*` resource types; CloudFormation `AWS::Rekognition::*` | 85% |
| Textract resources | `aws_textract_*` resource types | 80% |
| Lex resources | `aws_lex_*`, `aws_lexv2_*` resource types; CloudFormation `AWS::Lex::*` | 80% |
| Transcribe/Polly resources | `aws_transcribe_*`, `aws_polly_*` resource types | 80% |
| AI module usage | Module names containing `*ai*`, `*ml*`, `*model*`, `*prediction*`, `*bedrock*`, `*sagemaker*`; variable values referencing `bedrock`, `sagemaker` | 70% |
| Variable references | Variable/local names matching `*bedrock*`, `*sagemaker*`, `*model*`, `*ml*`; values containing `bedrock`, `sagemaker`, `comprehend`, `rekognition` | 60% |

Record all signals for the `ai_detection` section in `aws-resource-inventory.json`. If any signal has confidence >= 70%, set `has_ai_workload: true`.

**Note:** This step only detects signals from Terraform/CloudFormation. Full AI workload profiling (code analysis, billing data) is handled by `discover-app-code.md`.

## Step 2.5: Complexity Assessment

Count the unique AWS resource types extracted in Step 1 (and Step 1b) that are PRIMARY candidates
(compute, database, storage, messaging services — not IAM, security groups, or service-linked resources).
Use the Priority 1 list from classification-rules.md as reference:

**Primary types:** aws_instance, aws_ecs_service, aws_ecs_task_definition, aws_ecs_cluster,
aws_eks_cluster, aws_lambda_function, aws_elastic_beanstalk_environment,
aws_db_instance, aws_rds_cluster, aws_dynamodb_table,
aws_elasticache_cluster, aws_elasticache_replication_group,
aws_redshift_cluster, aws_s3_bucket, aws_efs_file_system,
aws_sqs_queue, aws_sns_topic, aws_kinesis_stream,
aws_sfn_state_machine, aws_cloudfront_distribution,
aws_api_gateway_rest_api, aws_apigatewayv2_api, aws_lb

Count resources matching these types. This is the **primary resource count**.

- **If primary resource count <= 8:** Use **simplified discovery** (Step 3S below). Skip Steps 3-6.
- **If primary resource count > 8:** Use **full discovery** (Steps 3-6, unchanged).

## Step 3S: Simplified Discovery (<= 8 primary resources)

For small projects, skip the full clustering pipeline. Instead:

1. **Classify resources** using only Priority 1 hardcoded rules from the PRIMARY types list above.
   - Resources matching the list → PRIMARY
   - All other resources → SECONDARY with role inferred from type:
     - `aws_iam_role*`, `aws_iam_policy*`, `aws_iam_user*`, `aws_iam_instance_profile` → role: identity
     - `aws_security_group*`, `aws_vpc*`, `aws_subnet*`,
       `aws_internet_gateway`, `aws_nat_gateway`, `aws_route_table*`,
       `aws_network_acl*`, `aws_route53*` → role: network_path
     - `aws_kms_key*`, `aws_secretsmanager_secret*`, `aws_ssm_parameter` → role: encryption
     - `aws_cloudwatch*`, `aws_autoscaling*` → role: configuration
     - Everything else → role: configuration
   - Set `confidence: 0.99` for all

2. **Build simple dependency edges:**
   - For each SECONDARY resource, find which PRIMARY resource it serves by checking
     Terraform reference expressions (e.g., `aws_ecs_service.X.name` referenced
     in an IAM role → that role serves that ECS service)
   - Edge type: `serves` for all edges (skip typed-edge classification)
   - If no reference found, attach to the nearest PRIMARY resource by file proximity

3. **Create clusters** using simple grouping:
   - **Networking cluster:** All `aws_vpc`, `aws_subnet`, `aws_internet_gateway`,
     `aws_nat_gateway`, `aws_security_group`, `aws_route_table*`,
     `aws_network_acl*`, `aws_route53*` resources → 1 cluster
   - **Per-primary clusters:** Each PRIMARY resource + its SECONDARY `serves` dependents → 1 cluster
   - Naming: `{category}_{type}_{region}_{sequence}` (same convention as full clustering)

4. **Set depth:** Networking cluster = depth 0. All other clusters = depth 1. (No Kahn's algorithm needed.)

5. **Load** `references/shared/schema-discover-iac.md` and write output files
   (`aws-resource-inventory.json`, `aws-resource-clusters.json`) using the same schema.
   Add to metadata: `"clustering_mode": "simplified"`.

6. **Proceed to Step 7** (same as full path).

**Note:** The simplified path produces the SAME output schema as the full path. Downstream
phases (clarify, design, estimate, generate) work identically regardless of clustering mode.

## Step 3: Classify Resources (PRIMARY vs SECONDARY)

1. Read `references/clustering/terraform/classification-rules.md` completely
2. For EACH resource from Step 1 (and Step 1b), apply classification rules in priority order:
   - **Priority 1**: Check if in PRIMARY list → mark `classification: "PRIMARY"`, assign `tier`, continue
   - **Priority 2**: Check if type matches SECONDARY patterns → mark `classification: "SECONDARY"` with `secondary_role` (one of: `identity`, `access_control`, `network_path`, `configuration`, `encryption`, `orchestration`)
   - **Priority 3**: Apply fallback heuristics first, then LLM inference → mark as SECONDARY with `secondary_role` and `confidence` field (0.5-0.75)
   - **Default**: Mark as `SECONDARY` with `secondary_role: "configuration"` and `confidence: 0.5`
3. For each resource, also record:
   - `confidence`: `0.99` (hardcoded) or `0.5-0.75` (LLM inference)
4. Confirm ALL resources have `classification` and `confidence` fields
5. Report counts (e.g., "Classified: 12 PRIMARY, 38 SECONDARY")

## Step 4: Build Dependency Edges and Populate Serves

1. Read `references/clustering/terraform/typed-edges-strategy.md` completely
2. For EACH resource from Step 1 (and Step 1b), extract references from `raw_hcl` or `raw_cfn`:
   - For Terraform: Extract all `aws_*\.[\w\.]+` patterns
   - For CloudFormation: Extract all `Ref`, `Fn::GetAtt`, and `Fn::Sub` references
   - Classify edge type by field name/value context (see typed-edges-strategy.md)
   - Store as `{from, to, relationship_type, evidence}` in `typed_edges[]` array
   - Include both **Secondary→Primary** edges (identity, network_path, etc.) and **Primary→Primary** edges (data_dependency, cache_dependency, publishes_to, etc.)
3. For SECONDARY resources, populate `serves[]` array:
   - Trace outgoing references to PRIMARY resources
   - Trace incoming `depends_on` references from PRIMARY resources
   - Include transitive chains (e.g., IAM Policy → IAM Role → Lambda)
4. Report dependency summary (e.g., "Found 45 typed edges, 38 secondaries populated serves arrays")

## Step 5: Calculate Topological Depth

1. Read `references/clustering/terraform/depth-calculation.md` completely
2. Use Kahn's algorithm (or equivalent topological sort) to assign `depth` field:
   - Depth 0: resources with no incoming dependencies
   - Depth N: resources where at least one dependency is depth N-1
3. **Detect cycles**: If any resource cannot be assigned depth, flag error: "Circular dependency detected between: [resources]. Breaking lowest-confidence edge."
4. Confirm ALL resources have `depth` field (integer >= 0)
5. Report depth summary (e.g., "Depth 0: 8 resources, Depth 1: 15 resources, ..., Max depth: 3")

## Step 6: Apply Clustering Algorithm

1. Read `references/clustering/terraform/clustering-algorithm.md` completely
2. Apply Rules 1-6 in exact priority order:
   - **Rule 1: Networking Cluster** — `aws_vpc` + all `network_path` secondaries → 1 cluster
   - **Rule 2: Same-Type Grouping** — ALL primaries of identical type → 1 cluster (not one per resource)
   - **Rule 3: Seed Clusters** — Each remaining PRIMARY gets cluster + its `serves[]` secondaries
   - **Rule 4: Merge on Dependencies** — Merge only if single deployment unit (rare)
   - **Rule 5: Skip Service-Linked Resources** — `aws_service_linked_role` and similar never get own cluster; attach to service they enable
   - **Rule 6: Deterministic Naming** — `{service_category}_{service_type}_{aws_region}_{sequence}` (e.g., `compute_ec2_us-east-1_001`, `database_rds_us-east-1_001`)
3. For each cluster, also populate:
   - `network` — which VPC the cluster's resources belong to
   - `must_migrate_together` — boolean (true for all clusters by default; set false only if resources can be migrated independently)
   - `dependencies` — array of other cluster IDs this cluster depends on (derived from Primary→Primary edges between clusters)
4. Assign `cluster_id` to EVERY resource (must match one of generated clusters)
5. Confirm ALL resources have `cluster_id` field
6. Build `creation_order` — global ordering of clusters by depth level
7. Report clustering results (e.g., "Generated 6 clusters from 50 resources")

## Step 7: Write Final Output Files

**This step is MANDATORY. Write all files with exact schemas.**

### 7a: Write aws-resource-inventory.json

1. Create file: `$MIGRATION_DIR/aws-resource-inventory.json`
2. Load `references/shared/schema-discover-iac.md` and write with the exact schema for `aws-resource-inventory.json`

**CRITICAL field names (use EXACTLY these):**

- `address` (resource Terraform address or normalized CloudFormation address)
- `type` (resource Terraform type — normalized for CloudFormation resources)
- `name` (resource name component)
- `classification` (PRIMARY or SECONDARY)
- `tier` (infrastructure layer: compute, database, storage, networking, identity, etc.)
- `confidence` (classification confidence, 0.0-1.0)
- `secondary_role` (for secondaries only; one of: identity, access_control, network_path, configuration, encryption, orchestration)
- `serves` (for secondaries only; list of resources this secondary supports)
- `cluster_id` (assigned cluster)
- `depth` (topological depth, integer >= 0)
- `source_format` (optional; `"terraform"` or `"cloudformation"` — only present for CloudFormation-sourced resources)

Include top-level sections:

- `metadata` — report_date, project_directory, terraform_version, cloudformation_templates_count
- `summary` — total_resources, primary_resources, secondary_resources, total_clusters, classification_coverage
- `resources[]` — all resources with above fields
- `ai_detection` — has_ai_workload, confidence, confidence_level, signals_found, ai_services

### 7b: Write aws-resource-clusters.json

1. Create file: `$MIGRATION_DIR/aws-resource-clusters.json`
2. Write with the exact schema for `aws-resource-clusters.json` (from `schema-discover-iac.md`, already loaded above)

**CRITICAL field names (use EXACTLY these):**

- `cluster_id` (matches resources' cluster_id)
- `primary_resources` (array of addresses)
- `secondary_resources` (array of addresses)
- `network` (which VPC this cluster belongs to)
- `creation_order_depth` (matches resource depths)
- `must_migrate_together` (boolean — whether cluster is atomic deployment unit)
- `dependencies` (array of other cluster IDs this depends on)
- `aws_region` (AWS region for this cluster)
- `edges` (array of {from, to, relationship_type, evidence})

Include top-level `creation_order` array:

```json
"creation_order": [
  { "depth": 0, "clusters": ["networking_vpc_us-east-1_001"] },
  { "depth": 1, "clusters": ["identity_iam_us-east-1_001"] },
  { "depth": 2, "clusters": ["database_rds_us-east-1_001"] }
]
```

### 7c: Validate Output Files

1. Confirm `$MIGRATION_DIR/aws-resource-inventory.json` exists and is valid JSON
2. Confirm `$MIGRATION_DIR/aws-resource-clusters.json` exists and is valid JSON
3. Verify all resource addresses in inventory appear in exactly one cluster
4. Verify all cluster IDs match resource cluster_id assignments
5. Report to user: "Wrote aws-resource-inventory.json (X resources) and aws-resource-clusters.json (Y clusters)"

After generating output files, the parent `discover.md` handles the phase status update — do not update `.phase-status.json` here.

## Step 7.5: Detect Ambiguous Resources

**Detect ambiguous resources and surface them in `aws-resource-inventory.json.ambiguities[]`.**

For every PRIMARY resource, run the explicit file-content checks below. Each failed check produces one entry in a top-level `ambiguities[]` array in `aws-resource-inventory.json`. These checks are **explicit, deterministic, and based on file-content inspection** — do NOT use LLM inference. Either the inventory data triggers the check or it does not.

Each ambiguity entry has this shape:

```json
{
  "aws_address": "aws_kinesis_firehose_delivery_stream.ProductionPumaFirehose",
  "aws_type": "aws_kinesis_firehose_delivery_stream",
  "ambiguity_type": "missing_destination",
  "detail": "Destination type is null / placeholder. Without knowing whether logs go to S3, OpenSearch, Splunk, or Redshift, the GCP target cannot be determined (Cloud Logging vs Pub/Sub+Dataflow vs Cloud Storage vs BigQuery)",
  "suggested_clarify_question": "Where does Firehose stream `ProductionPumaFirehose` deliver records?",
  "options": [
    {"id": "A", "label": "S3 (archive)", "implies_gcp": "Pub/Sub → Dataflow → Cloud Storage"},
    {"id": "B", "label": "OpenSearch (search)", "implies_gcp": "Pub/Sub → Dataflow → Elasticsearch on GCE"},
    {"id": "C", "label": "Splunk (SIEM)", "implies_gcp": "Pub/Sub → Splunk Connector for Dataflow"},
    {"id": "D", "label": "Redshift (analytics)", "implies_gcp": "Pub/Sub → Dataflow → BigQuery"},
    {"id": "E", "label": "Cloud Logging (application logs)", "implies_gcp": "Direct write_log_entries via Cloud Logging API"}
  ]
}
```

### Ambiguity Checks

Run each check below against every resource in `resources[]`. Each failed check appends one entry to `ambiguities[]`.

**Check 1 — Firehose with missing destination**

- **Resource type:** `aws_kinesis_firehose_delivery_stream`
- **Condition:** `config.destination` is absent, `null`, empty string, or equals the literal `"PLACEHOLDER"`. Also fires if `destination` is set but the matching nested config (e.g. `s3_configuration`, `extended_s3_configuration`, `elasticsearch_configuration`, `splunk_configuration`, `redshift_configuration`, `http_endpoint_configuration`) is absent.
- **`ambiguity_type`:** `"missing_destination"`
- **`detail`:** `"Destination type is null / placeholder. Without knowing whether logs go to S3, OpenSearch, Splunk, or Redshift, the GCP target cannot be determined (Cloud Logging vs Pub/Sub+Dataflow vs Cloud Storage vs BigQuery)"`
- **`suggested_clarify_question`:** ``"Where does Firehose stream `<name>` deliver records?"``
- **`options`:** the 5 options shown in the example above.

**Check 2 — ECS service with no LoadBalancer attachment**

- **Resource type:** `aws_ecs_service`
- **Condition:** `config.load_balancer` is absent OR empty array AND `config.desired_count` (or `desired_count`) is greater than 0. Cross-check that no `aws_lb_target_group.target_group_arn` in the inventory is referenced from this service's `raw_hcl`/`raw_cfn`.
- **`ambiguity_type`:** `"unclear_traffic_source"`
- **`detail`:** `"ECS service has no LoadBalancer attachment but DesiredCount > 0. Traffic source unknown — cannot pick between Cloud Run (public HTTP), Cloud Run internal, Cloud Run jobs, or Cloud Scheduler + Cloud Run."`
- **`suggested_clarify_question`:** ``"How does traffic reach ECS service `<name>`?"``
- **`options`:**
  - `{"id": "A", "label": "Public HTTP from ALB-equivalent", "implies_gcp": "Cloud Run (public, ingress=all)"}`
  - `{"id": "B", "label": "Internal service-to-service", "implies_gcp": "Cloud Run (ingress=internal) or GKE ClusterIP"}`
  - `{"id": "C", "label": "Batch worker — no HTTP", "implies_gcp": "Cloud Run Jobs or GKE Job"}`
  - `{"id": "D", "label": "Scheduled run", "implies_gcp": "Cloud Scheduler → Cloud Run Job"}`

**Check 3 — Lambda with no triggering event source**

- **Resource type:** `aws_lambda_function`
- **Condition:** No other resource in the inventory references this Lambda's `function_name` or `arn` from any of: `aws_apigatewayv2_integration`, `aws_apigatewayv2_route`, `aws_api_gateway_integration`, `aws_s3_bucket_notification`, `aws_dynamodb_table.stream_arn`, `aws_lambda_event_source_mapping`, `aws_cloudwatch_event_rule`, `aws_cloudwatch_event_target`, `aws_sns_topic_subscription`, `aws_sqs_queue` (event source mapping), `aws_lambda_permission`.
- **`ambiguity_type`:** `"unclear_trigger"`
- **`detail`:** `"Lambda has no detectable trigger in the inventory. GCP target depends on the trigger (Cloud Run for HTTP, Cloud Run Job + Scheduler for cron, Eventarc + Cloud Run for events)."`
- **`suggested_clarify_question`:** ``"What invokes Lambda function `<name>`?"``
- **`options`:**
  - `{"id": "A", "label": "HTTP / API Gateway", "implies_gcp": "Cloud Run (HTTP)"}`
  - `{"id": "B", "label": "S3 / DynamoDB / SNS / SQS event", "implies_gcp": "Eventarc → Cloud Run"}`
  - `{"id": "C", "label": "Scheduled (cron)", "implies_gcp": "Cloud Scheduler → Cloud Run Job"}`
  - `{"id": "D", "label": "Invoked manually / by other Lambda only", "implies_gcp": "Cloud Run Job (manual)"}`
  - `{"id": "E", "label": "Dead code — not invoked anymore", "implies_gcp": "Do not migrate; mark Deferred"}`

**Check 4 — Glue job with missing script location**

- **Resource type:** `aws_glue_job`
- **Condition:** `config.command.script_location` is absent, `null`, empty, or equals the literal `"PLACEHOLDER"`.
- **`ambiguity_type`:** `"unclear_job_script"`
- **`detail`:** `"Glue job has no Command.script_location value. Cannot determine job semantics (PySpark vs Spark SQL vs Python shell) — GCP target choice (Dataflow, Dataproc Serverless, Cloud Run Job) depends on this."`
- **`suggested_clarify_question`:** ``"What does Glue job `<name>` execute?"``
- **`options`:**
  - `{"id": "A", "label": "PySpark / Spark ETL", "implies_gcp": "Dataproc Serverless"}`
  - `{"id": "B", "label": "Spark SQL", "implies_gcp": "BigQuery + Dataform"}`
  - `{"id": "C", "label": "Python shell (no Spark)", "implies_gcp": "Cloud Run Job"}`
  - `{"id": "D", "label": "Streaming ETL", "implies_gcp": "Dataflow streaming"}`
  - `{"id": "E", "label": "Unknown / placeholder", "implies_gcp": "Mark Deferred — specialist engagement"}`

**Check 5 — SNS topic with no subscribers**

- **Resource type:** `aws_sns_topic`
- **Condition:** No `aws_sns_topic_subscription` resource in the inventory has a `topic_arn` (or `topic` reference) pointing to this topic's address.
- **`ambiguity_type`:** `"unclear_subscribers"`
- **`detail`:** `"SNS topic has no subscriber resources in inventory. Cannot determine fanout pattern — Pub/Sub topic + subscriptions vs Pub/Sub with no subscribers (dead) vs direct email/SMS via Cloud Functions."`
- **`suggested_clarify_question`:** ``"Who subscribes to SNS topic `<name>`?"``
- **`options`:**
  - `{"id": "A", "label": "Other services in this account (subs defined elsewhere)", "implies_gcp": "Pub/Sub topic + Pub/Sub subscriptions"}`
  - `{"id": "B", "label": "Email / SMS notifications", "implies_gcp": "Pub/Sub → Cloud Function → SendGrid / Twilio"}`
  - `{"id": "C", "label": "Cross-account subscribers", "implies_gcp": "Pub/Sub with IAM-granted external subscribers"}`
  - `{"id": "D", "label": "No active subscribers — dead topic", "implies_gcp": "Do not migrate; mark Deferred"}`

**Check 6 — IAM role with unclear principal**

- **Resource type:** `aws_iam_role`
- **Condition:** `config.assume_role_policy` (parsed as JSON) has `Statement[].Principal` values where no `Principal.Service` matches a service that has a primary resource in this inventory (e.g. `ecs-tasks.amazonaws.com` requires an ECS resource; `lambda.amazonaws.com` requires a Lambda resource), AND no `Principal.AWS` matches an account ID or role address present elsewhere in the inventory.
- **`ambiguity_type`:** `"unclear_principal"`
- **`detail`:** `"IAM role's AssumeRolePolicyDocument references a principal not matched by any resource in this account. Cannot determine the GCP IAM service account binding target."`
- **`suggested_clarify_question`:** ``"What assumes IAM role `<name>`? It references a principal not present in this inventory."``
- **`options`:**
  - `{"id": "A", "label": "External AWS account / federated identity", "implies_gcp": "Workload Identity Federation"}`
  - `{"id": "B", "label": "A workload outside this discovery scope", "implies_gcp": "Service account; bind manually later"}`
  - `{"id": "C", "label": "Human IAM user / SSO", "implies_gcp": "Cloud Identity / IAM user binding"}`
  - `{"id": "D", "label": "Unused / dead role", "implies_gcp": "Do not migrate; mark Deferred"}`

**Check 7 — Secrets Manager secret with placeholder value**

- **Resource type:** `aws_secretsmanager_secret` (also check the paired `aws_secretsmanager_secret_version`)
- **Condition:** Any of: `config.secret_string` equals literal `"PLACEHOLDER"`, is empty string, or is `null`. Also fires if the secret_version's `secret_string` matches the same conditions.
- **`ambiguity_type`:** `"placeholder_value_must_be_overwritten"`
- **`detail`:** `"Secret contains placeholder / empty value. The migration cannot copy real secret material — the operator must populate Secret Manager post-deploy."`
- **`suggested_clarify_question`:** ``"Secret `<name>` has a placeholder value. How should the GCP Secret Manager entry be populated?"``
- **`options`:**
  - `{"id": "A", "label": "I will populate via gcloud / console post-deploy", "implies_gcp": "Create Secret Manager resource with placeholder; add post-deploy step"}`
  - `{"id": "B", "label": "Import from existing Secrets Manager via secret_id reference", "implies_gcp": "Create Secret Manager resource + sync job"}`
  - `{"id": "C", "label": "Reference an environment variable at deploy time", "implies_gcp": "Secret Manager + CI/CD secret injection"}`
  - `{"id": "D", "label": "This secret is no longer used", "implies_gcp": "Do not migrate; mark Deferred"}`

**Check 8 — Resource with unclear engine version**

- **Resource type:** Any resource where `config.engine_version` field exists (typical: `aws_db_instance`, `aws_rds_cluster`, `aws_elasticache_cluster`, `aws_elasticache_replication_group`, `aws_opensearch_domain`).
- **Condition:** `config.engine_version` exists in the schema but the value is `null`, empty string, or a non-parseable version string (does not match `^\d+(\.\d+){0,3}$` or a recognized version alias such as `latest`).
- **`ambiguity_type`:** `"unclear_version"`
- **`detail`:** `"Resource has an engine_version field but the value is null or unparseable. Cannot select compatible GCP target version (Cloud SQL major-version alignment, Memorystore Redis version, etc.)."`
- **`suggested_clarify_question`:** ``"What engine version does `<name>` actually run? The inventory value is missing/unparseable."``
- **`options`:**
  - `{"id": "A", "label": "Major version 5.x", "implies_gcp": "Pick latest GCP minor for 5.x"}`
  - `{"id": "B", "label": "Major version 6.x", "implies_gcp": "Pick latest GCP minor for 6.x"}`
  - `{"id": "C", "label": "Major version 7.x or newer", "implies_gcp": "Pick latest GCP minor for 7.x+"}`
  - `{"id": "D", "label": "Use AWS default (latest at provision time)", "implies_gcp": "Pick latest GCP minor for current default major"}`
  - `{"id": "E", "label": "Unknown — operator must specify before deploy", "implies_gcp": "Set GCP target to latest stable + flag for review"}`

### Output Behavior

1. Append every triggered ambiguity entry to a top-level `ambiguities` array in `aws-resource-inventory.json` (even if empty — write `"ambiguities": []`).
2. Each entry MUST include all six fields above (`aws_address`, `aws_type`, `ambiguity_type`, `detail`, `suggested_clarify_question`, `options`).
3. Replace `<name>` in `suggested_clarify_question` with the actual resource short name (the part after the dot in the address, e.g. `ProductionPumaFirehose` from `aws_kinesis_firehose_delivery_stream.ProductionPumaFirehose`).
4. Multiple ambiguities for the same resource are allowed (e.g. an ECS service can produce both `unclear_traffic_source` and (via a related role) `unclear_principal`).
5. **If `ambiguities[]` is non-empty, the user-facing Discover summary MUST list each ambiguity as a one-line bullet (format: `- <aws_address>: <ambiguity_type> — <detail (first sentence)>`) BEFORE proceeding to Clarify.** This makes the ambiguities visible to the user immediately, not only when Clarify runs.

## Step 8: Generate `aws-architecture.mmd` mermaid diagram of the source AWS architecture

**BLOCKING — Discover phase MUST NOT mark `phases.discover = "completed"` until `$MIGRATION_DIR/aws-architecture.mmd` exists and contains at least one valid `flowchart TB` line and at least one node per PRIMARY resource.** This step is not optional and not "best-effort" — past iterations skipped it silently when the buffer ran low. If you cannot emit the file, you cannot complete the Discover phase. Write the file before any summary or status update.

Write a Mermaid `flowchart TB` diagram to `$MIGRATION_DIR/aws-architecture.mmd` that visualizes the source AWS topology from `aws-resource-inventory.json` and `aws-resource-clusters.json`:

- One `subgraph` per CLUSTER (group by `cluster_id`)
- One node per PRIMARY resource (label: `<aws_type short>: <aws_address>`)
- Edges from `aws-resource-clusters.json.clusters[].edges[]` (use the edge `relationship_type` as the label)
- Use AWS service emoji/icon prefixes where natural (e.g. 🗄️ for RDS, 📦 for S3, 🚀 for ECS, 🌐 for ALB, 🔑 for IAM, ⚡ for Lambda, 📨 for SQS/SNS)
- Add a top-level `subgraph Internet` containing any `aws_route53_*` records or public ALBs

The diagram MUST be a valid Mermaid block (start with `flowchart TB` on line 1; no surrounding ` ```mermaid ` fence — the file is `.mmd` not `.md`).

**Post-write validation (BLOCKING):** After writing the file, Read it back from disk. Verify (a) line 1 starts with the literal string `flowchart TB`, (b) the count of node declarations (lines containing `[` or `(` introducing a node) is at least equal to the count of PRIMARY resources in `aws-resource-inventory.json`. If either check fails, regenerate the file before proceeding. Refuse to update `.phase-status.json` until both checks pass.

Also add a brief `## AWS architecture (visual)` section to the user-facing Discover summary that links to the file: `See $MIGRATION_DIR/aws-architecture.mmd for a rendered topology diagram.`

## Output Validation Checklist

### aws-resource-inventory.json

- Every resource has `address`, `type`, `name`, and `classification` fields
- Every resource has `confidence` field
- Every PRIMARY resource has `depth` and `tier` fields
- Every SECONDARY resource has `secondary_role` and `serves` fields
- Every resource has `cluster_id` matching one of the generated clusters
- All field names use EXACT required keys (see Step 7a)
- No duplicate resource addresses
- `ai_detection` section present with `has_ai_workload` and `confidence` fields
- If `has_ai_workload: true`, then `signals_found` array contains at least one signal with confidence >= 70%
- If `has_ai_workload: false`, then `confidence: 0` and `signals_found: []`
- `ai_services` array lists only services actually detected (bedrock, sagemaker, etc.)
- `confidence_level` is one of: "very_high" (90%+), "high" (70-89%), "medium" (50-69%), "low" (< 50%), "none" (0%)
- `ambiguities` array is present (may be empty `[]`); each entry includes `aws_address`, `aws_type`, `ambiguity_type`, `detail`, `suggested_clarify_question`, `options[]`
- Each `options[]` entry includes `id`, `label`, `implies_gcp`
- If `ambiguities[]` is non-empty, the Discover summary lists each as a bullet before handoff to Clarify
- Output is valid JSON

### aws-resource-clusters.json

- Every cluster has `cluster_id`, `primary_resources`, `secondary_resources`
- `primary_resources` and `secondary_resources` are non-overlapping
- `creation_order_depth` matches resource depths
- `aws_region` is populated for every cluster
- `network` field is populated (references VPC resource or null if standalone)
- `must_migrate_together` is a boolean
- `dependencies` array contains only valid cluster IDs
- `edges` array uses `{from, to, relationship_type, evidence}` format
- `creation_order` array is topologically sorted
- All cluster dependencies exist in clusters array
- All resource addresses across all clusters account for every resource in inventory
- No duplicate cluster_ids
- No cycles in dependency graph
- Output is valid JSON

---

## Design Phase Integration

The Design phase (`references/phases/design/design.md`) uses both outputs:

1. **From aws-resource-clusters.json:**
   - `creation_order` — evaluates clusters depth-first (foundational first)
   - `primary_resources` / `secondary_resources` — knows which resources map independently vs which support others
   - `edges` — understands resource relationships and evidence
   - `network` — knows which VPC resources belong to
   - `dependencies` — understands cluster-level ordering
   - `must_migrate_together` — respects atomic deployment constraints

2. **From aws-resource-inventory.json:**
   - `config` — looks up config values against design-ref signals
   - `classification` / `secondary_role` — handles primary/secondary differently
   - `serves` — determines if secondary's primary is mapped
   - `depth` — validates clustering logic
   - `tier` — routes to correct design-ref file (compute.md, database.md, etc.)
   - `ai_detection` — determines if AI design phase runs

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
