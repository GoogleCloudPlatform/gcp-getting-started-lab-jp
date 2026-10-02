variable "aws_region" {
  description = "Home region for the whole stack"
  type        = string
  default     = "ap-northeast-1"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD review marker stamped on every resource tag"
  type        = string
}

variable "lambda_build_dir" {
  description = "Directory containing per-function build dirs assembled by scripts/deploy.sh"
  type        = string
  default     = "../build"
}
