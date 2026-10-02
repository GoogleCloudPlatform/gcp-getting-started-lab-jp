# Billing Discovery Schema

Schema for `billing-profile.json`, produced by `discover-billing.md`.

**Convention**: Values shown as `X|Y` in examples indicate allowed alternatives -- use exactly one value per field, not the literal pipe character.

---

## billing-profile.json (Phase 1 output)

Cost breakdown derived from AWS Cost and Usage Report (CUR) or billing CSV. Provides service-level spend and AI signal detection from billing data alone.

```json
{
  "metadata": {
    "report_date": "2026-04-12",
    "project_directory": "/path/to/project",
    "billing_source": "aws-cost-usage-report.csv",
    "billing_period": "2026-03"
  },
  "summary": {
    "total_monthly_spend": 2450.00,
    "service_count": 8,
    "currency": "USD"
  },
  "services": [
    {
      "aws_service": "Amazon Elastic Container Service",
      "aws_service_type": "aws_ecs_service",
      "monthly_cost": 450.00,
      "percentage_of_total": 0.18,
      "top_skus": [
        {
          "sku_description": "Fargate - vCPU Hours",
          "monthly_cost": 300.00
        },
        {
          "sku_description": "Fargate - GB Memory Hours",
          "monthly_cost": 150.00
        }
      ],
      "ai_signals": []
    },
    {
      "aws_service": "Amazon Relational Database Service",
      "aws_service_type": "aws_db_instance",
      "monthly_cost": 800.00,
      "percentage_of_total": 0.33,
      "top_skus": [
        {
          "sku_description": "RDS for PostgreSQL - db.r6g.large Multi-AZ",
          "monthly_cost": 500.00
        },
        {
          "sku_description": "RDS for PostgreSQL - GP3 Storage",
          "monthly_cost": 300.00
        }
      ],
      "ai_signals": []
    },
    {
      "aws_service": "Amazon Bedrock",
      "aws_service_type": "aws_bedrock_inference_profile",
      "monthly_cost": 600.00,
      "percentage_of_total": 0.24,
      "top_skus": [
        {
          "sku_description": "Bedrock - Claude Sonnet On-Demand Input Tokens",
          "monthly_cost": 200.00
        },
        {
          "sku_description": "Bedrock - Claude Sonnet On-Demand Output Tokens",
          "monthly_cost": 400.00
        }
      ],
      "ai_signals": ["bedrock", "foundation_models"]
    }
  ],
  "ai_signals": {
    "detected": true,
    "confidence": 0.85,
    "services": ["Amazon Bedrock"]
  }
}
```

**Key Fields:**

- `summary.total_monthly_spend` -- Total monthly AWS spend from the billing export
- `summary.service_count` -- Number of distinct AWS services with charges
- `services[].aws_service_type` -- Terraform resource type equivalent for the service (used by downstream phases)
- `services[].monthly_cost` -- Monthly cost for this service
- `services[].top_skus` -- Highest-cost line items within the service
- `services[].ai_signals` -- AI-related keywords found in SKU descriptions for this service
- `ai_signals.detected` -- Whether any AI/ML services were found in the billing data
- `ai_signals.confidence` -- Confidence that the project uses AI (derived from billing SKU analysis)
- `ai_signals.services` -- List of AI-related AWS services found
