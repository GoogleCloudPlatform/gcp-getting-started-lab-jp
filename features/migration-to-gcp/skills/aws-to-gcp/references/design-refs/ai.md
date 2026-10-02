# AI/ML Services Design Rubric

**Applies to:** SageMaker (traditional ML), Rekognition, Textract, Translate

## Companion skill (google/skills)

Before applying this rubric or shaping the GCP-side configuration:

- **Gemini on the Gemini Enterprise Agent Platform (GEAP, formerly Vertex AI) / Gemini API targets** (LLM workloads -- Bedrock or OpenAI being replaced, plus Agent Search & Grounding): read the latest version of **`gemini-api`** at `~/.claude/skills/gemini-api/SKILL.md` (fallback `~/.agents/skills/gemini-api/SKILL.md`). Use its canonical SDK setup, authentication, streaming, function-calling, and model-selection patterns. For conversation-style / interaction surfaces also consult **`gemini-interactions-api`** at the same paths.
- **Traditional ML on the Agent Platform** (SageMaker Endpoints / Pipelines / AutoML, Cloud Vision, Document AI, Cloud Translation): there is currently **no** dedicated google/skill. Use this file directly.

This rubric is the AWS -> GCP **decision** layer. The google/skill is the **how** layer for the chosen GCP target. If a companion skill is not installed, fall back to this file and `ai-bedrock-to-agent-platform.md` / `ai-openai-to-agent-platform.md` as appropriate, and add a `warnings[]` entry per the protocol in `references/shared/companion-skills.md`.

## LLM Routing

If the detected AI workload is LLM-based (generative models), load the source-specific design reference instead of this file:

- If `ai-workload-profile.json` -> `summary.ai_source` = `"bedrock"`: load `ai-bedrock-to-agent-platform.md`
- If `ai-workload-profile.json` -> `summary.ai_source` = `"openai"`: load `ai-openai-to-agent-platform.md`
- If `ai-workload-profile.json` -> `summary.ai_source` = `"both"`: load both files
- If `ai-workload-profile.json` -> `summary.ai_source` = `"other"` or absent, OR if the workload is traditional ML (custom models, Rekognition, Textract): use the Agent Platform / Cloud Vision / Document AI rubric below.

Agent workloads (`summary.agent_workloads_detected` true) are placed separately by `design-ai.md` Part 4B via `agent-runtime.md` — this file covers model/API targets only.

---

## Signals (Decision Criteria)

### SageMaker (Endpoints / Models)

- **Custom model inference** -> GEAP Endpoints
- **Pre-built model APIs** -> GCP APIs (Cloud Vision, Document AI, Cloud Translation, etc.)
- **Batch prediction** -> GEAP Batch Inference
- **Model catalog / hub** -> GEAP Model Garden (access to Gemini, Claude, Llama, Mistral, and 200+ open models)

### SageMaker Pipelines

- **ML training pipelines** -> GEAP Pipelines (Kubeflow-based)
- **Feature engineering** -> Feature Store on GEAP
- **AutoML** -> AutoML on GEAP (tabular, image, text, video)
- **Agent orchestration** -> Google ADK agents on Agent Runtime (custom agents; see `agent-runtime.md`) or Gemini Enterprise (business agent hub) -- build, deploy, and manage AI agents with Google Workspace, Search, and enterprise data integration

### Rekognition

- **Image classification, object detection** -> Cloud Vision API (image analysis)
- **Face detection/comparison** -> Cloud Vision API (face detection)
- **Video analysis** -> Cloud Video Intelligence API

### Textract

- **Document OCR** -> Document AI (more powerful for structured/unstructured docs)
- **Form extraction** -> Document AI (form parser, specialized processors)
- **Table extraction** -> Document AI (table extraction)

### Amazon Translate

- **Text translation** -> Cloud Translation API (Advanced or Basic)

### Bedrock Agents / Knowledge Bases

- **Agent orchestration** -> Google ADK agents on Agent Runtime (custom; see `agent-runtime.md`) or Gemini Enterprise (business agent hub) -- includes integration with Google Workspace, Google Search, and enterprise data connectors
- **Knowledge bases (RAG)** -> Agent Search & Grounding -- native Grounding with Google Search, enterprise data sources
- **Guardrails** -> Agent Platform safety filters -- built-in content filtering on all Gemini models

### Key Agent Platform Features

- **GEAP Model Garden** -- access to 200+ models including Gemini 3.1 Pro Preview (flagship), Gemini 2.5 Pro/Flash, Claude (partner), Llama 4, Mistral, DeepSeek, and more
- **Agent Runtime + Google ADK** -- build and deploy AI agents with tool use, function calling, and multi-step reasoning
- **Agent Search** -- enterprise search with grounding, citations, and ranking
- **GEAP Pipelines** -- ML workflow orchestration (Kubeflow-based)
- **Feature Store on GEAP** -- centralized feature management for ML models

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: use alternative
2. **Operational Model**: Managed (Agent Platform) vs Custom (Compute Engine + training)?
   - Prefer managed
3. **User Preference**: From `preferences.json`: `ai_constraints` (if present); infer cost sensitivity from `design_constraints.aws_monthly_spend` (there is no `cost_sensitivity` key — Clarify never writes one)
   - If cost-sensitive -> check Agent Platform preemptible VMs + AutoML
4. **Feature Parity**: Does AWS config need model type unavailable in GCP?
   - Example: PyTorch model -> Agent Platform (fully supported)
   - Example: TensorFlow model -> Agent Platform (fully supported, TensorFlow is Google-native)
5. **Cluster Context**: Are other compute resources running ML? Prefer Agent Platform affinity
6. **Simplicity**: GEAP Endpoints (managed) > custom Compute Engine instances

## Examples

### Example 1: SageMaker Endpoint (PyTorch model)

- AWS: `aws_sagemaker_endpoint` (model_name="image-classifier", framework=PYTORCH)
- Signals: Custom model inference, PyTorch
- Criterion 1 (Eliminators): PASS (PyTorch supported)
- Criterion 2 (Operational Model): GEAP Endpoint (managed)
- -> **GCP: GEAP Endpoint (PyTorch container)**
- Confidence: `inferred`

### Example 2: Rekognition (image analysis)

- AWS: Rekognition API (feature=LABELS, image_source=S3)
- Signals: Pre-built API
- -> **GCP: Cloud Vision API (label detection) or Document AI (if document OCR)**
- Confidence: `inferred`

### Example 3: SageMaker Autopilot (AutoML)

- AWS: SageMaker Autopilot (problem_type=BINARY_CLASSIFICATION)
- Signals: AutoML training pipeline, classification
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): AutoML on GEAP (managed)
- -> **GCP: AutoML on GEAP, Tabular (binary classification)**
- Confidence: `inferred`

### Example 4: Textract (document extraction)

- AWS: Textract (AnalyzeDocument, feature_types=[FORMS, TABLES])
- Signals: Document form and table extraction
- -> **GCP: Document AI (form parser processor)**
- Confidence: `inferred`

## Output Schema

```json
{
  "aws_type": "aws_sagemaker_endpoint",
  "aws_address": "image-classifier-v2",
  "aws_config": {
    "framework": "PYTORCH",
    "instance_type": "ml.m5.large"
  },
  "gcp_service": "Vertex AI",
  "gcp_config": {
    "endpoint_name": "image-classifier-v2",
    "machine_type": "n1-standard-4",
    "container_image": "pytorch:1.9"
  },
  "confidence": "inferred",
  "rationale": "SageMaker custom model -> GEAP Endpoint (PyTorch supported)"
}
```
