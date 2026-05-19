# Messaging Services Design Rubric

**Applies to:** SNS, SQS, EventBridge, Step Functions

**Quick lookup (no rubric):** Check `fast-path.md` first (none of these are in Direct Mappings -- all go through rubric -> `inferred`)

## Companion skill (google/skills)

There is currently **no** dedicated google/skill for Pub/Sub, Cloud Tasks, Eventarc, Cloud Scheduler, or Workflows. Use this file directly for messaging-specific configuration.

When the chosen target needs to invoke or be invoked by a Cloud Run service or Cloud Run job (e.g. Pub/Sub push -> Cloud Run, Eventarc -> Cloud Run, Cloud Tasks HTTP target -> Cloud Run), consult **`cloud-run-basics`** for the receiving-side configuration (Eventarc trigger setup, OIDC auth, concurrency tuning) per `references/shared/companion-skills.md`.

## Eliminators (Hard Blockers)

| AWS Service    | GCP        | Blocker                                                                                                       |
| -------------- | ---------- | ------------------------------------------------------------------------------------------------------------- |
| SQS FIFO       | Pub/Sub    | Exactly-once delivery required -> Pub/Sub with exactly-once delivery (supported on pull subscriptions)        |
| SQS            | Cloud Tasks| Multiple consumers needed -> Pub/Sub (Cloud Tasks is single-consumer)                                         |
| Step Functions | Workflows  | >365 steps in a single execution -> consider breaking into sub-workflows                                      |

## Signals (Decision Criteria)

### SNS (Simple Notification Service)

- **Fan-out / broadcast to multiple subscribers** -> Pub/Sub (topic with multiple subscriptions)
- **SMS/Email notifications** -> Pub/Sub + Cloud Run functions or Cloud Run service (trigger notification via Twilio/SendGrid)
- **FIFO ordering** -> Pub/Sub with ordering keys (per-key ordering guarantee)

### SQS (Simple Queue Service)

- **Single consumer, work queue** -> Pub/Sub with pull subscription (durable, at-least-once)
- **Single consumer, HTTP callback** -> Cloud Tasks (task-based, with rate limiting and retry)
- **FIFO queue, exactly-once** -> Pub/Sub with exactly-once delivery (pull subscription only)
- **Delay queue** -> Cloud Tasks with scheduled dispatch time (native delay support)
- **Dead letter queue** -> Pub/Sub dead-letter topic (automatic forwarding after N failed deliveries)

### EventBridge

- **Event routing from multiple sources** -> Eventarc (event routing with filters)
- **Scheduled events (cron)** -> Cloud Scheduler (cron-based job scheduling)
- **Custom event bus** -> Eventarc with custom channels
- **Schema registry** -> Eventarc does not have a built-in schema registry; use Pub/Sub schema validation

### Step Functions

- **Orchestration of multiple services** -> Workflows (serverless workflow orchestration)
- **Long-running workflows (up to 1 year)** -> Workflows (supports long-running executions)
- **Parallel execution** -> Workflows parallel steps
- **Human approval steps** -> Workflows with Cloud Run callback endpoint
- **Express Workflows (high-volume, short)** -> Workflows (no separate express tier; Workflows is always serverless)

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: switch
2. **Operational Model**: Managed (Pub/Sub, Cloud Tasks, Workflows) vs Custom?
   - Prefer managed -- all GCP messaging services are fully managed
3. **User Preference**: From `preferences.json`: `design_constraints.availability`?
   - Pub/Sub is global and multi-zone by default -- no special config needed for HA
   - If ordering or exactly-once delivery required -> Pub/Sub with ordering keys (see Eliminators)
4. **Feature Parity**: Does AWS config need features unavailable in GCP?
   - Example: SQS visibility timeout -> Pub/Sub ack deadline (similar concept)
   - Example: SNS message filtering -> Pub/Sub subscription filters
5. **Cluster Context**: Are other resources using Pub/Sub/Cloud Tasks? Match if possible
6. **Simplicity**: Pub/Sub (unified pub/sub + queue) vs separate services

## Key Architectural Difference: Pub/Sub Unifies SNS + SQS

GCP Pub/Sub serves as both a publish/subscribe system (like SNS) and a durable message queue (like SQS). A single Pub/Sub topic with multiple subscriptions replaces the common AWS pattern of SNS -> SQS fan-out.

| AWS Pattern                    | GCP Equivalent                                    |
| ------------------------------ | ------------------------------------------------- |
| SNS topic (broadcast)          | Pub/Sub topic                                     |
| SQS queue (single consumer)    | Pub/Sub topic + pull subscription                 |
| SNS -> SQS fan-out             | Pub/Sub topic + multiple pull subscriptions        |
| SNS FIFO + SQS FIFO            | Pub/Sub topic with ordering keys + exactly-once   |
| SQS + Lambda trigger           | Pub/Sub + Eventarc/push delivery to Cloud Run     |
| EventBridge rule               | Eventarc trigger                                  |
| Step Functions state machine   | Workflows definition                              |

## Examples

### Example 1: SNS Topic (broadcast)

- AWS: `aws_sns_topic` (name="user-events", fifo_topic=false)
- Signals: Broadcast events, multiple subscribers likely
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): Pub/Sub (managed)
- -> **GCP: Pub/Sub Topic (standard, with multiple subscriptions)**
- Note: Pub/Sub natively supports message retention (up to 31 days), unlike SNS which requires SQS for durability.
- Confidence: `inferred`

### Example 2: SQS Queue (work queue)

- AWS: `aws_sqs_queue` (name="task-queue", visibility_timeout_seconds=60, message_retention_seconds=345600)
- Signals: Work queue, single consumer, retry
- Criterion 1 (Eliminators): PASS
- -> **GCP: Pub/Sub Topic + Pull Subscription (ack_deadline=60s, message_retention=4d)**
- Confidence: `inferred`

### Example 3: SQS Queue (delayed tasks)

- AWS: `aws_sqs_queue` (name="delayed-tasks", delay_seconds=300)
- Signals: Delayed execution, HTTP callback pattern
- Criterion 1 (Eliminators): Delay required -> Cloud Tasks preferred
- -> **GCP: Cloud Tasks Queue (rate_limits, retry_config, scheduled dispatch)**
- Confidence: `inferred`

### Example 4: EventBridge (event routing)

- AWS: `aws_cloudwatch_event_rule` (schedule_expression="rate(5 minutes)", event_pattern=...)
- Signals: Scheduled + event-driven routing
- -> **GCP: Cloud Scheduler (cron) + Eventarc (event routing)**
- Note: Split into two services -- Cloud Scheduler for cron triggers, Eventarc for event-based routing
- Confidence: `inferred`

### Example 5: Step Functions (orchestration)

- AWS: `aws_sfn_state_machine` (definition=ASL JSON, type="STANDARD")
- Signals: Multi-step orchestration, long-running
- -> **GCP: Workflows (YAML-based workflow definition)**
- Note: Workflows uses YAML syntax instead of ASL JSON. Migration requires rewriting the state machine definition.
- Confidence: `inferred`

## Output Schema

```json
{
  "aws_type": "aws_sns_topic",
  "aws_address": "user-events",
  "aws_config": {
    "fifo_topic": false,
    "subscribers": 3
  },
  "gcp_service": "Pub/Sub",
  "gcp_config": {
    "topic_name": "user-events",
    "subscriptions": 3,
    "message_retention_duration": "604800s"
  },
  "confidence": "inferred",
  "rationale": "SNS with multiple subscribers -> Pub/Sub topic with multiple subscriptions (fan-out pattern)"
}
```
