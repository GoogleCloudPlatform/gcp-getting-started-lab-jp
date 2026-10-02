# Terraform Clustering: Typed Edge Strategy

Infers edge types from HCL context to classify relationships between resources.

Edges are categorized into two groups:

- **Secondary->Primary relationships** -- infrastructure support (identity, network, encryption)
- **Primary->Primary relationships** -- service communication (data, cache, messaging, storage)

## Pass 1: Extract References from HCL

Parse HCL configuration text for all `resource_type.name.attribute` patterns:

- Regex: `(aws_\w+)\.(\w+)\.(\w+)` or `aws_\w+\.[\w\.]+`
- Capture fully qualified references: `aws_db_instance.prod.endpoint`
- Include references in: attribute values, `depends_on` arrays, variable interpolations

Store each reference with:

- `reference`: target resource address
- `field_path`: HCL attribute path where reference appears
- `raw_context`: surrounding HCL text (10 lines for LLM context)

## Pass 2: Classify Edge Type by Field Context

For each reference, determine edge type. Use the `secondary_role` of the source resource to guide classification.

### Secondary->Primary Relationships

These use the secondary's `secondary_role` as the relationship type:

- `identity_binding` -- IAM role attached to compute resource via instance profile or execution role
- `network_path` -- subnet, route table, NAT gateway, internet gateway serving a resource
- `access_control` -- IAM policy attachment granting access to resource
- `security` -- security group controlling traffic to/from resource
- `configuration` -- parameter group, subnet group, secret configuring resource
- `encryption` -- KMS key protecting a resource
- `orchestration` -- null_resource, time_sleep sequencing

### Primary->Primary Relationships

Infer from field paths and environment variable names:

#### Data Dependencies

Field name matches: `DATABASE*`, `DB_*`, `RDS*`, `CONNECTION_*`, `ENDPOINT*`

Environment variable name matches: `DATABASE*`, `DB_HOST`, `DB_ENDPOINT`, `RDS_*`

- **Type**: `data_dependency`
- **Example**: `aws_lambda_function.processor.environment.variables.DATABASE_URL` -> `aws_db_instance.main.endpoint`

#### Cache Dependencies

Field name matches: `REDIS*`, `CACHE*`, `MEMCACHED*`, `ELASTICACHE*`

- **Type**: `cache_dependency`
- **Example**: `aws_ecs_service.worker.environment.REDIS_HOST` -> `aws_elasticache_cluster.cache.cache_nodes`

#### Publish Dependencies

Field name matches: `SQS*`, `SNS*`, `QUEUE*`, `TOPIC*`, `KINESIS*`, `STREAM*`

- **Type**: `publishes_to`
- **Example**: `aws_lambda_function.publisher.environment.variables.SQS_QUEUE_URL` -> `aws_sqs_queue.events.id`

#### Storage Dependencies

Field name matches: `BUCKET*`, `S3*`, `STORAGE*`

Direction determined by context:

- Write context (upload, save, persist, put) -> `writes_to`
- Read context (download, fetch, load, get) -> `reads_from`
- Bidirectional -> Both edge types

- **Example**: `aws_lambda_function.worker.environment.variables.S3_BUCKET` -> `aws_s3_bucket.data.bucket`

#### DNS Resolution

A DNS record pointing to a compute resource.

- **Type**: `dns_resolution`
- **Example**: `aws_route53_record.api` -> `aws_lb.web` (A/ALIAS record pointing to load balancer)

#### Network Membership

Resources sharing the same VPC/subnet.

- **Type**: `network_membership`
- **Example**: Multiple primary resources referencing the same `aws_vpc.main`

### Infrastructure Relationships

These apply to both Secondary->Primary and resource-to-resource references:

#### Network Path

Field name: `vpc_id`, `subnet_id`, `subnet_ids`, `network_interface`

- **Type**: `network_path`
- **Example**: `aws_lambda_function.app.vpc_config.subnet_ids` -> `aws_subnet.private.id`

#### Security

Field name: `security_groups`, `vpc_security_group_ids`, `security_group_id`

- **Type**: `security`
- **Example**: `aws_instance.web.vpc_security_group_ids` -> `aws_security_group.web.id`

#### IAM Binding

Field name: `role`, `execution_role_arn`, `task_role_arn`, `instance_profile`

- **Type**: `iam_binding`
- **Example**: `aws_lambda_function.app.role` -> `aws_iam_role.lambda_exec.arn`

#### Encryption

Field name: `kms_key_id`, `kms_key_arn`, `server_side_encryption`, `encryption_key`

- **Type**: `encryption`
- **Example**: `aws_s3_bucket.data.server_side_encryption_configuration.rule.kms_master_key_id` -> `aws_kms_key.s3.arn`

#### Orchestration

Explicit `depends_on` array

- **Type**: `orchestration`
- **Example**: `depends_on = [aws_db_instance.main]`

## Default Fallback

If no patterns match, use LLM to infer edge type from:

- Resource types (compute -> storage likely data_dependency)
- Field names and values
- Raw HCL context

If LLM uncertain: `unknown_dependency` with confidence field.

## Evidence Structure

Every edge must include a structured `evidence` object:

```json
{
  "from": "aws_lambda_function.processor",
  "to": "aws_db_instance.main",
  "relationship_type": "data_dependency",
  "evidence": {
    "field_path": "environment.variables",
    "reference": "DATABASE_URL"
  }
}
```

Evidence fields:

- `field_path` -- HCL attribute path where the reference appears
- `reference` -- the specific value, variable name, or env var that creates the relationship

All edges stored in resource's `typed_edges[]` array and in the cluster's `edges[]` array.
