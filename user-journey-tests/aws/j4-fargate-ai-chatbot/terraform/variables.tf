variable "aws_region" {
  description = "Deployment region."
  type        = string
  default     = "ap-northeast-1"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD for the AutoTeardown tag (set by scripts/deploy.sh from ~/.aws/journeys.env)."
  type        = string
}

variable "image_tag" {
  description = "Tag of the fac-api image in ECR that the task definition points at."
  type        = string
  default     = "latest"
}

variable "llm_mode" {
  description = "Assistant mode: \"live\" (real model calls) or \"stub\" (deterministic canned replies)."
  type        = string
  default     = "live"

  validation {
    condition     = contains(["live", "stub"], var.llm_mode)
    error_message = "llm_mode must be \"live\" or \"stub\"."
  }
}

variable "model_id" {
  description = "Model / inference-profile id passed to the app. APAC cross-region profile for Nova Micro (id verified 2026-07)."
  type        = string
  default     = "apac.amazon.nova-micro-v1:0"
}

variable "bedrock_region" {
  description = "Region the app's model clients are constructed for."
  type        = string
  default     = "ap-northeast-1"
}

variable "app_port" {
  description = "Container listen port."
  type        = number
  default     = 8000
}
