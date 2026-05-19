# Discover Phase: Billing Discovery

> Self-contained billing discovery sub-file. Scans for billing CSV/JSON files, parses billing data, builds service usage profiles, flags AI signals, and generates `billing-profile.json`.
> If no billing files are found, exits cleanly with no output.

**Execute ALL steps in order. Do not skip or optimize.**

---

## Step 0: Self-Scan for Billing Files

Scan the target directory for billing data:

- `**/*billing*.csv` — AWS billing export CSV
- `**/*billing*.json` — AWS billing export JSON
- `**/*cost*.csv`, `**/*cost*.json` — Cost Explorer report exports
- `**/*usage*.csv`, `**/*usage*.json` — Usage report exports
- `**/*CUR*.csv`, `**/*CUR*.json` — AWS Cost and Usage Reports (CUR)
- `**/*aws-cost*.csv`, `**/*aws-cost*.json` — AWS cost report naming conventions

**Exit gate:** If NO billing files are found, **exit cleanly**. Return no output artifacts. Other sub-discovery files may still produce artifacts.

---

## Step 1: Parse Billing Data

Supported formats:

- AWS Cost and Usage Report (CUR) CSV
- AWS Cost Explorer export CSV/JSON
- AWS billing export CSV

Extract from each line item:

- `service_description` — AWS service name (e.g., "Amazon Elastic Compute Cloud", "Amazon Simple Storage Service")
- `sku_description` — Specific SKU/resource (e.g., "m5.xlarge On-Demand Linux", "S3 Standard Storage")
- `cost` — Cost amount
- `usage_amount` — Usage quantity
- `usage_unit` — Usage unit (e.g., hours, GB-months, requests)

Group by service and calculate monthly totals.

---

## Step 2: Build Service Usage Profile

From the parsed billing data:

1. List all AWS services with non-zero spend
2. Calculate monthly cost per service
3. Identify top services by spend (sorted descending)
4. Note usage patterns (consistent vs bursty spend)

---

## Step 3: Flag AI Signals

Scan billing line items for AI-relevant patterns. For each match, record the pattern, line item details, and confidence score.

| Pattern | What to look for | Confidence |
| --- | --- | --- |
| 3.1 Bedrock billing | Description contains "Amazon Bedrock", "Bedrock"; model invocation charges, token-based billing | 98% |
| 3.2 SageMaker billing | "Amazon SageMaker" line items; endpoint hosting, training job, notebook instance charges | 95% |
| 3.3 Comprehend/Rekognition billing | "Amazon Comprehend", "Amazon Rekognition", "Amazon Textract"; per-unit or per-page charges | 85% |
| 3.4 Specialized AI services | "Amazon Transcribe", "Amazon Polly", "Amazon Lex", "Amazon Personalize", "Amazon Forecast", "Amazon Kendra", "Amazon Translate" | 85% |

---

## Step 4: Generate billing-profile.json

Write `$MIGRATION_DIR/billing-profile.json` with the following structure:

```json
{
  "metadata": {
    "report_date": "2026-02-24",
    "project_directory": "/path/to/project",
    "billing_source": "aws-cost-and-usage-report.csv",
    "billing_period": "2026-01"
  },
  "summary": {
    "total_monthly_spend": 2450.00,
    "service_count": 8,
    "currency": "USD"
  },
  "services": [
    {
      "aws_service": "Amazon Elastic Compute Cloud",
      "aws_service_type": "aws_instance",
      "monthly_cost": 450.00,
      "percentage_of_total": 0.18,
      "top_skus": [
        {
          "sku_description": "EC2 - m5.xlarge On-Demand Linux",
          "monthly_cost": 300.00
        },
        {
          "sku_description": "EC2 - t3.medium On-Demand Linux",
          "monthly_cost": 150.00
        }
      ],
      "ai_signals": []
    }
  ],
  "ai_signals": {
    "detected": false,
    "confidence": 0,
    "services": []
  }
}
```

Load `references/shared/schema-discover-billing.md` and validate the output against the `billing-profile.json` schema.

After generating the output file, the parent `discover.md` handles the phase status update — do not update `.phase-status.json` here.

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
