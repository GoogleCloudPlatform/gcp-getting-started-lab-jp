# Terraform Clustering: Classification Rules

Hardcoded lists for classifying AWS resources as PRIMARY or SECONDARY.

Each PRIMARY resource is assigned a `tier` indicating its infrastructure layer.

## Priority 0: Excluded Resources (Skip Entirely)

These resource types are **excluded from classification, clustering, and migration**. Do not classify them as PRIMARY or SECONDARY. Do not create clusters for them. Do not include them in `aws-resource-inventory.json`.

### Authentication Providers

Third-party and AWS-adjacent authentication resources. Users should keep their existing auth provider -- do not recommend migrating to GCP Identity Platform or any GCP auth service.

- `aws_cognito_user_pool` -- AWS Cognito User Pool (all variants: user_pool_client, user_pool_domain, identity_provider)
- `aws_cognito_identity_pool` -- AWS Cognito Identity Pool (all variants)
- `aws_cognito_user_pool_client` -- AWS Cognito User Pool Client

If encountered: log as "Auth provider detected -- excluded from migration scope. Keep your existing auth solution." and skip.

## Priority 1: PRIMARY Resources (Workload-Bearing)

These resource types are always PRIMARY:

### Compute (`tier: "compute"`)

- `aws_instance` -- EC2 virtual machine
- `aws_eks_cluster` -- Kubernetes cluster (EKS)
- `aws_eks_node_group` -- Kubernetes node group
- `aws_lambda_function` -- Serverless function
- `aws_ecs_cluster` -- Container orchestration cluster
- `aws_ecs_service` -- Container service
- `aws_ecs_task_definition` -- Container task definition
- `aws_elastic_beanstalk_environment` -- Managed application platform

### Database (`tier: "database"`)

- `aws_db_instance` -- RDS relational database instance
- `aws_rds_cluster` -- RDS Aurora cluster
- `aws_rds_cluster_instance` -- RDS Aurora cluster instance
- `aws_dynamodb_table` -- NoSQL key-value/document database
- `aws_elasticache_cluster` -- In-memory cache (Redis/Memcached)
- `aws_elasticache_replication_group` -- ElastiCache replication group
- `aws_redshift_cluster` -- Data warehouse

### Storage (`tier: "storage"`)

- `aws_s3_bucket` -- Object storage
- `aws_efs_file_system` -- Managed NFS file storage
- `aws_athena_database` -- Analytics query database

### Messaging (`tier: "messaging"`)

- `aws_sqs_queue` -- Message queue
- `aws_sns_topic` -- Pub/sub notification topic
- `aws_kinesis_stream` -- Real-time data stream

### Networking (`tier: "networking"`)

- `aws_vpc` -- Virtual Private Cloud (primary because it defines topology)
- `aws_lb` -- Application/Network Load Balancer
- `aws_alb` -- Application Load Balancer (alias)
- `aws_route53_zone` -- DNS zone

### Monitoring (`tier: "monitoring"`)

- `aws_cloudwatch_metric_alarm` -- CloudWatch alarm

### Other

- `module.*` -- Terraform module that wraps primary resources (tier inferred from wrapped resource)

**Action**: Mark as `PRIMARY` with assigned `tier`. Classification done. No secondary_role.

## Priority 2: SECONDARY Resources by Role

Match resource type against secondary classification table. Each match assigns a `secondary_role`:

### Identity (`identity`)

- `aws_iam_role` -- Workload identity / execution role
- `aws_iam_instance_profile` -- EC2 instance profile
- `data.aws_iam_policy_document` -- Data source reference to IAM policy document

### Access Control (`access_control`)

- `aws_iam_policy` -- IAM managed policy
- `aws_iam_role_policy` -- IAM inline policy
- `aws_iam_role_policy_attachment` -- IAM policy attachment
- `aws_iam_policy_attachment` -- IAM policy attachment (global)
- `aws_iam_user_policy_attachment` -- IAM user policy attachment

### Network Path (`network_path`)

- `aws_subnet` -- VPC subnet
- `aws_route_table` -- Route table
- `aws_route_table_association` -- Route table to subnet association
- `aws_nat_gateway` -- NAT gateway for outbound internet
- `aws_internet_gateway` -- Internet gateway for public access
- `aws_eip` -- Elastic IP address
- `aws_vpc_endpoint` -- VPC endpoint for private AWS service access
- `aws_network_interface` -- Elastic network interface

### Security (`security`)

- `aws_security_group` -- Security group (virtual firewall)
- `aws_security_group_rule` -- Individual security group rule
- `aws_waf_web_acl` -- WAF web access control list
- `aws_wafv2_web_acl` -- WAFv2 web access control list

### Configuration (`configuration`)

- `aws_db_subnet_group` -- RDS subnet group
- `aws_db_parameter_group` -- RDS parameter group
- `aws_elasticache_subnet_group` -- ElastiCache subnet group
- `aws_secretsmanager_secret` -- Secrets Manager secret
- `aws_secretsmanager_secret_version` -- Secrets Manager secret value
- `aws_ssm_parameter` -- Systems Manager parameter
- `aws_route53_record` -- DNS record
- `aws_cloudwatch_log_group` -- Log group
- `aws_lb_target_group` -- Load balancer target group
- `aws_lb_target_group_attachment` -- Target group attachment
- `aws_lb_listener` -- Load balancer listener
- `aws_lb_listener_rule` -- Load balancer listener rule
- `aws_s3_bucket_policy` -- S3 bucket policy
- `aws_s3_bucket_versioning` -- S3 bucket versioning config
- `aws_s3_bucket_server_side_encryption_configuration` -- S3 encryption config
- `aws_s3_bucket_public_access_block` -- S3 public access block

### Encryption (`encryption`)

- `aws_kms_key` -- KMS encryption key
- `aws_kms_alias` -- KMS key alias

### Orchestration (`orchestration`)

- `null_resource` -- Terraform orchestration marker
- `time_sleep` -- Orchestration delay
- `aws_cloudformation_stack` -- CloudFormation stack (prerequisite, not a deployable unit in Terraform context)

**Action**: Mark as `SECONDARY` with assigned role.

## Priority 3: LLM Inference Fallback

If resource type not in Priority 1 or 2, apply these **deterministic fallback heuristics** BEFORE free-form LLM reasoning:

| Pattern                                              | Classification    | secondary_role | confidence |
| ---------------------------------------------------- | ----------------- | -------------- | ---------- |
| Name contains `scheduler`, `task`, `job`, `workflow` | SECONDARY         | orchestration  | 0.65       |
| Name contains `log`, `metric`, `alert`, `dashboard`  | SECONDARY         | configuration  | 0.60       |
| Resource has zero references to/from other resources | SECONDARY         | configuration  | 0.50       |
| Resource only referenced by a `module` block         | SECONDARY         | configuration  | 0.55       |
| Type contains `policy` or `attachment`               | SECONDARY         | access_control | 0.65       |
| Type contains `subnet` or `network`                  | SECONDARY         | network_path   | 0.60       |
| None of the above match                              | Use LLM reasoning | --             | 0.50-0.75  |

If still uncertain after heuristics, use LLM reasoning. Mark with:

- `classification_source: "llm_inference"`
- `confidence: 0.5-0.75`

**Default**: If all heuristics and LLM fail: `SECONDARY` / `configuration` with confidence 0.5. It is safer to under-classify (secondary) than over-classify (primary), because secondaries are grouped into existing clusters while primaries create new clusters.

## Serves[] Population

For SECONDARY resources, populate `serves[]` array (list of PRIMARY resources it supports):

1. Extract all outgoing references from this SECONDARY's config
2. Include direct references: `field = resource_type.name.id` patterns
3. Include transitive chains: if referenced resource is also SECONDARY, trace to PRIMARY

**Example**: `aws_security_group.web` -> references `aws_vpc.main` (SECONDARY network_path) -> serves `aws_instance.web` (PRIMARY)

**Serves array**: Points back to PRIMARY workloads affected by this security group. Trace through SECONDARY resources until a PRIMARY is reached.
