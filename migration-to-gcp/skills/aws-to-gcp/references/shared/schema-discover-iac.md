# IaC Discovery Schemas

Schemas for `aws-resource-inventory.json` and `aws-resource-clusters.json`, produced by `discover-iac.md`.

**Convention**: Values shown as `X|Y` in examples indicate allowed alternatives -- use exactly one value per field, not the literal pipe character.

---

## aws-resource-inventory.json (Phase 1 output)

Complete inventory of discovered AWS resources with classification, dependencies, and AI detection.

```json
{
  "metadata": {
    "report_date": "2026-04-12",
    "project_directory": "/path/to/terraform",
      "iac_sources": ["terraform", "cloudformation"],
      "terraform_version": ">= 1.0.0",
      "cloudformation_templates_count": 0
  },
  "summary": {
    "total_resources": 50,
    "primary_resources": 12,
    "secondary_resources": 38,
    "total_clusters": 6,
    "classification_coverage": "100%"
  },
  "resources": [
    {
      "address": "aws_ecs_service.orders_api",
      "type": "aws_ecs_service",
      "name": "orders_api",
      "classification": "PRIMARY",
      "tier": "compute",
      "confidence": 0.99,
      "config": {
        "launch_type": "FARGATE",
        "desired_count": 2,
        "cpu": 512,
        "memory": 1024
      },
      "depth": 3,
      "cluster_id": "compute_ecs_us-east-1_001"
    },
    {
      "address": "aws_iam_role.app",
      "type": "aws_iam_role",
      "name": "app",
      "classification": "SECONDARY",
      "tier": "identity",
      "confidence": 0.99,
      "secondary_role": "identity",
      "serves": ["aws_ecs_service.orders_api", "aws_ecs_service.products_api"],
      "config": {
        "name": "app-execution-role"
      },
      "depth": 2,
      "cluster_id": "compute_ecs_us-east-1_001"
    },
    {
      "address": "aws_vpc.main",
      "type": "aws_vpc",
      "name": "main",
      "classification": "PRIMARY",
      "tier": "networking",
      "confidence": 0.99,
      "config": {
        "cidr_block": "10.0.0.0/16"
      },
      "depth": 0,
      "cluster_id": "networking_vpc_us-east-1_001"
    }
  ],
  "ai_detection": {
    "has_ai_workload": false,
    "confidence": 0,
    "confidence_level": "none",
    "signals_found": [],
    "ai_services": []
  },
  "ambiguities": [
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
  ]
}
```

**CRITICAL Field Names** (use EXACTLY these keys):

- `address` -- Terraform resource address or normalized CloudFormation address (NOT `id`, `resource_address`)
- `type` -- Resource type (NOT `resource_type`)
- `name` -- Resource name component (NOT `resource_name`)
- `classification` -- `"PRIMARY"` or `"SECONDARY"` (NOT `class`, `category`)
- `tier` -- Infrastructure layer: compute, database, storage, networking, identity, messaging, monitoring (NOT `layer`)
- `confidence` -- Classification confidence 0.0-1.0 (NOT `certainty`)
- `secondary_role` -- For secondaries only: identity, access_control, network_path, configuration, encryption, orchestration
- `serves` -- For secondaries only: array of primary resource addresses served
- `depth` -- Dependency depth (0 = foundational, N = depends on depth N-1)
- `cluster_id` -- Which cluster this resource belongs to

**Key Sections:**

- `metadata` -- Report metadata (report_date, project_directory, iac_sources, terraform_version when Terraform is present, cloudformation_templates_count)
- `summary` -- Aggregate statistics (total_resources, primary/secondary counts, cluster count, classification_coverage)
- `resources[]` -- All discovered resources with fields above
- `ai_detection` -- AI workload detection results:
  - `has_ai_workload` -- boolean
  - `confidence` -- 0.0-1.0
  - `confidence_level` -- "very_high" (90%+), "high" (70-89%), "medium" (50-69%), "low" (< 50%), "none" (0%)
  - `signals_found[]` -- array of detection signals with method, pattern, confidence, evidence
  - `ai_services[]` -- list of AI services detected (sagemaker, bedrock, comprehend, etc.)
- `ambiguities[]` -- Resources whose AWS topology is ambiguous and require a Clarify-phase user decision. Produced by `discover-iac.md` Step 7.5. Each entry has:
  - `aws_address` -- the inventory address of the ambiguous resource
  - `aws_type` -- the resource type (e.g., `aws_kinesis_firehose_delivery_stream`)
  - `ambiguity_type` -- one of: `missing_destination`, `unclear_traffic_source`, `unclear_trigger`, `unclear_job_script`, `unclear_subscribers`, `unclear_principal`, `placeholder_value_must_be_overwritten`, `unclear_version` (extensible)
  - `detail` -- human-readable explanation of why this is ambiguous
  - `suggested_clarify_question` -- text Clarify will present verbatim
  - `options[]` -- multiple-choice answers, each with `id` (A/B/C/...), `label`, `implies_gcp` (the GCP target Design must use if this option is chosen)
  - Always present (write `[]` if no ambiguities detected)

---

## aws-resource-clusters.json (Phase 1 output)

Resources grouped into logical clusters for migration with full dependency graph and creation order.

```json
{
  "clusters": [
    {
      "cluster_id": "networking_vpc_us-east-1_001",
      "aws_region": "us-east-1",
      "primary_resources": [
        "aws_vpc.main"
      ],
      "secondary_resources": [
        "aws_subnet.app",
        "aws_security_group.app"
      ],
      "network": null,
      "creation_order_depth": 0,
      "must_migrate_together": true,
      "dependencies": [],
      "edges": []
    },
    {
      "cluster_id": "database_rds_us-east-1_001",
      "aws_region": "us-east-1",
      "primary_resources": [
        "aws_db_instance.db"
      ],
      "secondary_resources": [
        "aws_db_subnet_group.main"
      ],
      "network": "networking_vpc_us-east-1_001",
      "creation_order_depth": 1,
      "must_migrate_together": true,
      "dependencies": ["networking_vpc_us-east-1_001"],
      "edges": [
        {
          "from": "aws_db_instance.db",
          "to": "aws_vpc.main",
          "relationship_type": "network_membership",
          "evidence": {
            "field_path": "db_subnet_group_name",
            "reference": "VPC membership"
          }
        }
      ]
    },
    {
      "cluster_id": "compute_ecs_us-east-1_001",
      "aws_region": "us-east-1",
      "primary_resources": [
        "aws_ecs_service.orders_api",
        "aws_ecs_service.products_api"
      ],
      "secondary_resources": [
        "aws_iam_role.app"
      ],
      "network": "networking_vpc_us-east-1_001",
      "creation_order_depth": 2,
      "must_migrate_together": true,
      "dependencies": ["database_rds_us-east-1_001"],
      "edges": [
        {
          "from": "aws_ecs_service.orders_api",
          "to": "aws_db_instance.db",
          "relationship_type": "data_dependency",
          "evidence": {
            "field_path": "task_definition.container_definitions[0].environment[].value",
            "reference": "DATABASE_URL"
          }
        }
      ]
    }
  ],
  "creation_order": [
    { "depth": 0, "clusters": ["networking_vpc_us-east-1_001"] },
    { "depth": 1, "clusters": ["database_rds_us-east-1_001"] },
    { "depth": 2, "clusters": ["compute_ecs_us-east-1_001"] }
  ]
}
```

**Key Fields:**

- `cluster_id` -- Unique cluster identifier (deterministic format: `{service_category}_{service_type}_{aws_region}_{sequence}`)
- `aws_region` -- AWS region for this cluster
- `primary_resources` -- AWS resources that map independently
- `secondary_resources` -- AWS resources that support primary resources
- `network` -- Which VPC cluster this cluster belongs to (cluster ID reference, or null if networking cluster itself)
- `creation_order_depth` -- Depth level in topological sort (0 = foundational)
- `must_migrate_together` -- Boolean indicating if cluster is an atomic deployment unit
- `dependencies` -- Other cluster IDs this cluster depends on (derived from cross-cluster Primary->Primary edges)
- `edges` -- Typed relationships between resources with structured evidence
- `creation_order` -- Global ordering of clusters by depth level (for migration sequencing)
