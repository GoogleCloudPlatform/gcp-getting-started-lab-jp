# AI/ML Services Design Rubric

**Applies to:** SageMaker (traditional ML), Rekognition, Textract, Translate

## Companion skill (google/skills)

Before applying this rubric or shaping the GCP-side configuration:

- **Vertex AI Gemini / Gemini API targets** (LLM workloads -- Bedrock or OpenAI being replaced, plus Vertex AI Agent Builder, Vertex AI Search & Grounding): read the latest version of **`gemini-api`** at `~/.claude/skills/gemini-api/SKILL.md` (fallback `~/.agents/skills/gemini-api/SKILL.md`). Use its canonical SDK setup, authentication, streaming, function-calling, and model-selection patterns. For conversation-style / interaction surfaces also consult **`gemini-interactions-api`** at the same paths.
- **Traditional ML on Vertex AI** (SageMaker Endpoints / Pipelines / AutoML, Cloud Vision, Document AI, Cloud Translation): there is currently **no** dedicated google/skill. Use this file directly.

This rubric is the AWS -> GCP **decision** layer. The google/skill is the **how** layer for the chosen GCP target. If a companion skill is not installed, fall back to this file and `ai-bedrock-to-vertex.md` / `ai-openai-to-vertex.md` as appropriate, and add a `warnings[]` entry per the protocol in `references/shared/companion-skills.md`.

## LLM Routing

If the detected AI workload is LLM-based (generative models), load the source-specific design reference instead of this file:

- If `ai-workload-profile.json` -> `summary.ai_source` = `"bedrock"`: load `ai-bedrock-to-vertex.md`
- If `ai-workload-profile.json` -> `summary.ai_source` = `"openai"`: load `ai-openai-to-vertex.md`
- If `ai-workload-profile.json` -> `summary.ai_source` = `"both"`: load both files
- If `ai-workload-profile.json` -> `summary.ai_source` = `"other"` or absent, OR if the workload is traditional ML (custom models, Rekognition, Textract): use the Vertex AI / Cloud Vision / Document AI rubric below.

---

## Signals (Decision Criteria)

### SageMaker (Endpoints / Models)

- **Custom model inference** -> Vertex AI Endpoints
- **Pre-built model APIs** -> GCP APIs (Cloud Vision, Document AI, Cloud Translation, etc.)
- **Batch prediction** -> Vertex AI Batch Prediction
- **Model catalog / hub** -> Vertex AI Model Garden (access to Gemini, Claude, Llama, Mistral, and 200+ open models)

### SageMaker Pipelines

- **ML training pipelines** -> Vertex AI Pipelines (Kubeflow-based)
- **Feature engineering** -> Vertex AI Feature Store
- **AutoML** -> Vertex AI AutoML (tabular, image, text, video)
- **Agent orchestration** -> Vertex AI Agent Builder (Agentspace) -- build, deploy, and manage AI agents with Google Workspace, Search, and enterprise data integration

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

- **Agent orchestration** -> Vertex AI Agent Builder (Agentspace) -- includes integration with Google Workspace, Google Search, and enterprise data connectors
- **Knowledge bases (RAG)** -> Vertex AI Search & Grounding -- native Grounding with Google Search, enterprise data sources
- **Guardrails** -> Vertex AI Safety Filters -- built-in content filtering on all Gemini models

### Key Vertex AI Platform Features

- **Vertex AI Model Garden** -- access to 200+ models including Gemini 3.1 Pro Preview (flagship), Gemini 2.5 Pro/Flash, Claude (partner), Llama 4, Mistral, DeepSeek, and more
- **Vertex AI Agent Builder** -- build and deploy AI agents with tool use, function calling, and multi-step reasoning
- **Vertex AI Search** -- enterprise search with grounding, citations, and ranking
- **Vertex AI Pipelines** -- ML workflow orchestration (Kubeflow-based)
- **Vertex AI Feature Store** -- centralized feature management for ML models

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: use alternative
2. **Operational Model**: Managed (Vertex AI) vs Custom (Compute Engine + training)?
   - Prefer managed
3. **User Preference**: From `preferences.json`: `design_constraints.cost_sensitivity` + `ai_constraints` (if present)
   - If cost-sensitive -> check Vertex AI preemptible VMs + AutoML
4. **Feature Parity**: Does AWS config need model type unavailable in GCP?
   - Example: PyTorch model -> Vertex AI (fully supported)
   - Example: TensorFlow model -> Vertex AI (fully supported, TensorFlow is Google-native)
5. **Cluster Context**: Are other compute resources running ML? Prefer Vertex AI affinity
6. **Simplicity**: Vertex AI endpoints (managed) > custom Compute Engine instances

## Examples

### Example 1: SageMaker Endpoint (PyTorch model)

- AWS: `aws_sagemaker_endpoint` (model_name="image-classifier", framework=PYTORCH)
- Signals: Custom model inference, PyTorch
- Criterion 1 (Eliminators): PASS (PyTorch supported)
- Criterion 2 (Operational Model): Vertex AI Endpoint (managed)
- -> **GCP: Vertex AI Endpoint (PyTorch container)**
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
- Criterion 2 (Operational Model): Vertex AI AutoML (managed)
- -> **GCP: Vertex AI AutoML Tabular (binary classification)**
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
  "rationale": "SageMaker custom model -> Vertex AI Endpoint (PyTorch supported)"
}
```
