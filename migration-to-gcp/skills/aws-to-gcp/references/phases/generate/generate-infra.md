# Generate Phase: Infrastructure Migration Plan

> Loaded by generate.md when estimation-infra.json exists.

**Execute ALL steps in order. Do not skip or optimize.**

> **Budget note (headless / time-constrained runs):** This planning stage produces a **single file** (`generation-infra.json`). If the wall-clock budget is tight, emit a **minimum-viable** plan (just `migration_plan.total_weeks`, `migration_plan.phases` with the 6 stage names, and a 3-row `risks` array) before elaborating Parts 2-9. See `generate.md` -> **Budget Guidance** for the artifact emission order in Stage 2. Do not block on producing a complete plan if it prevents Stage 2 from running.

## Prerequisites

Read the following artifacts from `$MIGRATION_DIR/`:

- `gcp-design.json` (REQUIRED) -- GCP architecture design from Phase 3
- `estimation-infra.json` (REQUIRED) -- Cost estimates from Phase 4
- `aws-resource-clusters.json` (REQUIRED) -- Cluster dependency graph from Phase 1
- `preferences.json` (REQUIRED) -- User migration preferences from Phase 2

If any required file is missing: **STOP**. Output: "Missing required artifact: [filename]. Complete the prior phase that produces it."

## Part 1: Migration Timeline

Build an 8-12 week migration timeline based on:

- **Cluster count** from `aws-resource-clusters.json` -- more clusters = longer infrastructure phase
- **Dependency depth** from `creation_order` -- deeper graphs need more sequential work
- **Service complexity** from `gcp-design.json` -- databases and stateful services take longer
- **Cutover strategy** from `preferences.json` -- maintenance window vs. blue-green affects timeline

### Stage 1: Setup (Weeks 1-2)

- Finalize GCP project structure and billing alerts
- Provision foundational infrastructure: VPC, subnets, Cloud Router, Cloud NAT
- Configure IAM roles and service accounts per cluster requirements
- Establish AWS-to-GCP connectivity (Cloud VPN or Cloud Interconnect for data migration)
- Set up CI/CD pipeline for Terraform deployments
- Configure monitoring baseline (Cloud Monitoring, alerting policies)

### Stage 2: Proof of Concept (Weeks 3-4)

- Deploy the **shallowest-depth cluster** (lowest `creation_order_depth`) to GCP
- Validate application connectivity and performance
- Test data pipeline from AWS to GCP (database replication, storage sync)
- Measure baseline latency and throughput
- Confirm cost tracking matches `estimation-infra.json` projections
- **Go/No-Go checkpoint**: If PoC fails acceptance criteria, stop and reassess

### Stage 3: Infrastructure Deployment (Weeks 5-7)

- Deploy remaining clusters in `creation_order` sequence (depth-first)
- For each cluster:
  - Deploy infrastructure per `gcp-design.json` resource mappings
  - Configure cross-cluster networking and firewall rules
  - Validate service health checks
  - Run integration tests
- Implement monitoring and logging per cluster
- Establish backup and restore procedures

### Stage 4: Data Migration (Weeks 8-9)

**Include this phase ONLY if `gcp-design.json` contains database or storage resources
(see resource detection rules in generate-artifacts-scripts.md Step 1).**
**If no data migration is needed, compress the timeline: move Cutover to Weeks 8-9
and Validation to Week 10. Reduce `total_weeks` accordingly.**

- **Databases**: Set up continuous replication (RDS/Aurora to Cloud SQL)
  - Initial full snapshot transfer
  - Enable ongoing replication (Database Migration Service or native replication)
  - Validate data integrity (row counts, checksums)
- **Object storage**: Sync S3 buckets to Cloud Storage
  - Use Storage Transfer Service or `gsutil`/`gcloud storage cp` for bulk transfer
  - Enable ongoing sync for new objects
- **Secrets**: Migrate secrets from AWS Secrets Manager to GCP Secret Manager
- Establish dual-write pattern for production data

### Stage 5: Cutover (Weeks 10-11, or Weeks 8-9 if Stage 4 skipped)

- Pre-cutover validation:
  - All clusters deployed and healthy on GCP
  - Data replication lag < 1 second
  - All integration tests passing
  - Rollback procedures tested
- Execute cutover per `preferences.json` cutover_strategy:
  - **maintenance-window**: Schedule downtime, switch DNS, validate
  - **blue-green**: Gradual traffic shift (10% -> 50% -> 100%)
- Monitor for 24-48 hours post-cutover
- Keep AWS resources running as hot standby

### Stage 6: Validation and Cleanup (Week 12)

- Monitor GCP performance for 1 full week
- Compare actual costs against `estimation-infra.json` projections
- Run final data integrity checks
- Document any drift or issues
- Begin AWS teardown planning (execute teardown after 2-week stability period)

## Part 2: Risk Assessment

Build a risk matrix from the discovered infrastructure and migration complexity.

### Risk Categories

For each risk, assess:

- **Probability**: `"high"` (>60%), `"medium"` (30-60%), `"low"` (<30%)
- **Impact**: `"critical"` (service outage), `"high"` (degraded service), `"medium"` (delayed timeline), `"low"` (minor inconvenience)
- **Mitigation**: Specific action to reduce probability or impact

### Standard Risks

| Risk                             | Probability | Impact   | Mitigation                                                                                      |
| -------------------------------- | ----------- | -------- | ----------------------------------------------------------------------------------------------- |
| Data loss during migration       | low         | critical | Dual-write for 2 weeks before cutover; full backup before migration; checksums on all transfers |
| Performance regression on GCP    | medium      | high     | PoC testing (Weeks 3-4); load testing (Week 5); performance baseline comparison                 |
| Extended downtime during cutover | medium      | high     | Practice cutover in staging; automate DNS switch; rollback procedure on standby                 |
| Cost overrun vs estimates        | medium      | medium   | Set billing alerts at 80% and 100% of projected; weekly cost review                             |
| Cross-region latency             | low         | medium   | Validate latency in PoC phase; consider same-region deployment for latency-sensitive services   |
| Terraform state corruption       | low         | high     | Remote state with locking (GCS + Cloud Storage backend); state backups before each apply        |

### Dynamic Risks

Add additional risks based on discovered infrastructure:

- If **databases with replication** exist: Add "Replication lag during cutover" (medium/high)
- If **stateful services** (Redis, Elasticsearch): Add "State migration data loss" (low/critical)
- If **multiple regions** in AWS: Add "Cross-region dependency during migration" (medium/medium)
- If **AI workloads** coexist: Add "Model performance drift on Vertex AI" (medium/high)
- If **Redshift** resources exist (`aws_redshift_*` or `gcp_service` is **`Deferred -- specialist engagement`** in `gcp-design.json`): Add "Redshift migration complexity" (high/high) with mitigation: "**No automated GCP analytics target** -- engage **GCP account team** and/or **data analytics migration partner** before architecture or cost commitments; plugin does not prescribe BigQuery/Dataflow/Dataproc."

## Part 3: Success Metrics

### Per-Service Metrics

For each service in `gcp-design.json`, define:

| Metric       | Target                                           | Measurement                            |
| ------------ | ------------------------------------------------ | -------------------------------------- |
| Availability | 99.9% uptime                                     | Cloud Monitoring uptime checks         |
| Latency      | Within 10% of AWS baseline                       | P50, P95, P99 response times           |
| Error rate   | < 0.1%                                           | Cloud Monitoring error metrics         |
| Cost         | Within 15% of `estimation-infra.json` projection | GCP Billing export weekly              |

### Overall Migration Metrics

| Metric             | Target                                       |
| ------------------ | -------------------------------------------- |
| Data integrity     | 100% -- zero data loss confirmed by checksums |
| Migration timeline | Within 2 weeks of planned schedule           |
| Rollback success   | Tested and confirmed < 1 hour RTO            |
| Team confidence    | Go/No-Go passed at each phase gate           |

## Part 4: Rollback Procedures

### Trigger Conditions

Initiate rollback if ANY of:

- Data integrity issues detected during validation (checksum mismatch)
- Performance regression > 20% vs AWS baseline (P95 latency)
- Error rate > 1% sustained for 15 minutes
- Cost overrun > 50% vs `estimation-infra.json` projections
- Critical GCP service limitation discovered that blocks functionality

### Per-Phase Rollback

| Phase                | Rollback Action                                    | RTO          |
| -------------------- | -------------------------------------------------- | ------------ |
| Setup (1-2)          | Delete GCP resources; no impact                    | < 1 hour     |
| PoC (3-4)            | Tear down PoC cluster; AWS unaffected              | < 1 hour     |
| Infrastructure (5-7) | Tear down GCP clusters; AWS still primary          | < 2 hours    |
| Data Migration (8-9) | Stop replication; AWS data is authoritative         | < 30 minutes |
| Cutover (10-11)      | Reverse DNS to AWS; resume AWS traffic             | < 1 hour     |
| Post-Cutover (12+)   | Manual restore from backup; AWS resources archived | 2-4 hours    |

### Rollback Procedure (Pre-DNS Cutover)

1. Pause dual-write replication
2. Reverse DNS records (GCP to AWS endpoints)
3. Verify AWS services receiving traffic
4. Shut down GCP workloads (keep for 1 week as standby)
5. Monitor AWS for 24 hours
6. Post-mortem: document what triggered rollback

### Rollback Procedure (Post-DNS Cutover)

1. If within 48 hours: Reverse DNS, resume AWS from replicated state
2. If beyond 48 hours: Restore AWS from backup (2-4 hour RTO)
3. Validate data integrity after restore
4. Resume AWS operations
5. Post-mortem and reassess migration approach

## Part 5: Team and Roles

### RACI Matrix

| Activity               | Migration Lead | Infrastructure Engineer | Database Engineer | Application Developer | QA Engineer |
| ---------------------- | -------------- | ----------------------- | ----------------- | --------------------- | ----------- |
| Migration planning     | A/R            | C                       | C                 | C                     | I           |
| GCP project setup      | A              | R                       | I                 | I                     | I           |
| Network infrastructure | A              | R                       | I                 | I                     | I           |
| Database migration     | A              | C                       | R                 | I                     | C           |
| Application deployment | A              | C                       | I                 | R                     | C           |
| Data validation        | A              | I                       | R                 | C                     | R           |
| Performance testing    | A              | C                       | C                 | C                     | R           |
| Cutover execution      | R              | R                       | R                 | C                     | C           |
| Rollback execution     | R              | R                       | R                 | I                     | I           |

**R** = Responsible, **A** = Accountable, **C** = Consulted, **I** = Informed

## Part 6: Go/No-Go Framework

Each phase gate requires explicit approval before proceeding.

### Phase Gate Criteria

| Gate | Phase Transition             | Go Criteria                                                     | No-Go Action              |
| ---- | ---------------------------- | --------------------------------------------------------------- | ------------------------- |
| G1   | Setup -> PoC                 | VPC online, IAM configured, connectivity verified               | Fix infrastructure issues |
| G2   | PoC -> Full Deploy           | PoC cluster healthy, latency acceptable, costs tracking         | Reassess architecture     |
| G3   | Full Deploy -> Data Migration | All clusters deployed, integration tests passing               | Debug failing clusters    |
| G4   | Data Migration -> Cutover    | Replication lag < 1s, data integrity confirmed, rollback tested | Fix replication issues    |
| G5   | Cutover -> Validation        | DNS switched, traffic flowing, error rate < 0.1%               | Execute rollback          |
| G6   | Validation -> Cleanup        | 1 week stable operation, costs within 15% of estimate          | Extend monitoring period  |

## Part 7: Post-Migration Monitoring

### 30-Day Post-Migration Plan

**Week 1 (Days 1-7)**: Intensive monitoring

- Check all Cloud Monitoring dashboards every 4 hours
- Compare latency/throughput to AWS baseline daily
- Review GCP costs daily vs projections
- Maintain AWS hot standby

**Week 2 (Days 8-14)**: Stabilization

- Reduce monitoring frequency to twice daily
- Begin decommissioning AWS hot standby (read-only mode)
- Address any performance tuning items
- Validate backup/restore procedures on GCP

**Weeks 3-4 (Days 15-30)**: Optimization

- Implement cost optimization opportunities from `estimation-infra.json`
- Right-size instances based on actual usage data
- Enable Committed Use Discounts for stable workloads
- Archive AWS resources and begin teardown
- Final cost reconciliation: actual vs projected

## Part 8: Decision Tree

### Cutover Decision Flowchart

```
START: All clusters deployed?
  NO -> Continue infrastructure deployment
  YES -> Data replication active?
    NO -> Start data migration
    YES -> Replication lag < 1 second?
      NO -> Wait for replication to catch up
      YES -> All integration tests passing?
        NO -> Fix failing tests
        YES -> Rollback procedure tested?
          NO -> Execute rollback drill
          YES -> READY FOR CUTOVER
            -> Execute cutover per strategy
            -> Monitor 24-48 hours
            -> Error rate < 0.1%?
              NO -> EXECUTE ROLLBACK
              YES -> CUTOVER SUCCESSFUL
                -> Begin 30-day monitoring
                -> Plan AWS teardown (Week 14)
```

## Part 9: Output Format

Generate `generation-infra.json` in `$MIGRATION_DIR/` with the following schema:

```json
{
  "phase": "generate",
  "generation_source": "infrastructure",
  "timestamp": "2026-04-12T14:30:00Z",
  "migration_plan": {
    "total_weeks": 12,
    "phases": [
      {
        "name": "Setup",
        "weeks": "1-2",
        "clusters_targeted": [],
        "key_activities": ["GCP project setup", "VPC provisioning", "IAM configuration"],
        "dependencies": [],
        "go_no_go_criteria": "VPC online, IAM configured, connectivity verified"
      }
    ],
    "services": [
      {
        "aws_service": "Fargate",
        "gcp_service": "Cloud Run",
        "migration_week": 5,
        "cluster_id": "compute_ecs_us-east-1_001",
        "estimated_effort_hours": 40,
        "data_migration_required": false,
        "human_expertise_required": false
      }
    ],
    "critical_path": [
      "VPC setup (Week 1)",
      "PoC deployment (Week 3-4)",
      "Database replication (Week 8-9)",
      "DNS cutover (Week 10-11)"
    ],
    "dependencies": [
      {
        "from_cluster": "networking_vpc_us-east-1_001",
        "to_cluster": "compute_ecs_us-east-1_001",
        "type": "must_precede"
      }
    ]
  },
  "risks": [
    {
      "category": "data_loss",
      "probability": "low",
      "impact": "critical",
      "mitigation": "Dual-write for 2 weeks; full backup before cutover; checksum validation",
      "phase_affected": "Data Migration"
    }
  ],
  "success_metrics": {
    "per_service": [
      {
        "service": "Cloud Run",
        "availability_target": "99.9%",
        "latency_target": "within 10% of AWS baseline",
        "cost_target": "within 15% of estimation"
      }
    ],
    "overall": {
      "data_integrity": "100%",
      "timeline_variance": "within 2 weeks",
      "rollback_rto": "< 1 hour"
    }
  },
  "rollback_procedures": {
    "trigger_conditions": [
      "Data integrity failure",
      "Performance regression > 20%",
      "Error rate > 1% sustained 15 min",
      "Cost overrun > 50%"
    ],
    "pre_cutover_rto": "< 1 hour",
    "post_cutover_rto": "2-4 hours",
    "rollback_window": "Reversible until 48 hours post-DNS cutover"
  },
  "go_no_go_criteria": [
    {
      "gate": "G1",
      "transition": "Setup to PoC",
      "criteria": "VPC online, IAM configured, connectivity verified"
    }
  ],
  "post_migration": {
    "monitoring_duration_days": 30,
    "aws_teardown_week": 14,
    "optimization_start_week": 15
  },
  "recommendation": {
    "approach": "Phased cluster-by-cluster migration",
    "confidence": "high",
    "key_risks": ["Data migration complexity", "Performance validation"],
    "estimated_total_effort_hours": 480
  }
}
```

## Output Validation Checklist

- `phase` is `"generate"`
- `generation_source` is `"infrastructure"`
- `migration_plan.total_weeks` is a positive integer (8-16 range)
- `migration_plan.phases` array has at least 4 entries (Setup, PoC, Infrastructure, Cutover, Validation -- plus Data Migration if data resources exist)
- `migration_plan.services` covers every service from `gcp-design.json`
- `migration_plan.critical_path` is non-empty
- `migration_plan.dependencies` reflect `aws-resource-clusters.json` creation_order
- `risks` array has at least 3 entries with probability, impact, mitigation
- `success_metrics` has both `per_service` and `overall` sections
- `rollback_procedures` has trigger conditions and RTO values
- `go_no_go_criteria` has at least 4 gates
- `post_migration` specifies monitoring duration and teardown timing
- All cluster IDs reference valid clusters from `aws-resource-clusters.json`
- Output is valid JSON

## Generate Phase Integration

The parent orchestrator (`generate.md`) uses `generation-infra.json` to:

1. Gate Stage 2 artifact generation -- `generate-artifacts-infra.md` requires this file
2. Provide timeline context to `generate-artifacts-docs.md` for MIGRATION_GUIDE.md
3. Set phase completion status in `.phase-status.json`
