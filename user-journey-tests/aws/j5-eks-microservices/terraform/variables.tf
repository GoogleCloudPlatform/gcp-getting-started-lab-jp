variable "aws_region" {
  description = "Deployment region."
  type        = string
  default     = "ap-northeast-1"
}

variable "autoteardown_date" {
  description = "YYYY-MM-DD for the AutoTeardown tag (set by scripts/deploy.sh from ~/.aws/journeys.env)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. The k8s manifests and deploy scripts assume the default."
  type        = string
  default     = "ems-cluster"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version (standard support as of 2026-07, verified)."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "Worker node instance type. Lab account: small on-demand classes only."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Fixed node count (min = max = desired; no autoscaler in this stack)."
  type        = number
  default     = 2
}
