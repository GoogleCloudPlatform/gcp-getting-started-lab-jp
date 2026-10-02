# j6-fargate-agentic-rag — input surface.

variable "region" {
  description = "Deployment region."
  type        = string
  default     = "ap-northeast-1"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD AutoTeardown tag (deploy.sh injects it from ~/.aws/journeys.env)."
  type        = string
}

variable "image_tag" {
  description = "Tag of the policy-copilot image in ECR."
  type        = string
  default     = "latest"
}

variable "answer_mode" {
  description = "\"pipeline\" = deterministic retrieval loop with no model call (runs in accounts with zero Bedrock quota); \"model\" = live google-adk agent over LiteLLM's bedrock/ route."
  type        = string
  default     = "pipeline"

  validation {
    condition     = contains(["pipeline", "model"], var.answer_mode)
    error_message = "answer_mode must be \"pipeline\" or \"model\"."
  }
}

variable "bedrock_model_id" {
  description = "Bedrock model the agent binds through LiteLLM (bedrock/<id>)."
  type        = string
  default     = "jp.anthropic.claude-sonnet-4-6"
}

variable "container_port" {
  description = "Port the copilot listens on inside the container."
  type        = number
  default     = 8080
}
