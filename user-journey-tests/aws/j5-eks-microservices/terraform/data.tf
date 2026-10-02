# Account identity + the DEFAULT VPC. This configuration never creates or
# deletes VPCs/subnets — it only references what the account already has.

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# The cluster's OIDC issuer TLS certificate — needed to register the issuer
# as an IAM OIDC identity provider so pod service accounts can assume IAM
# roles (IRSA). See iam.tf.
data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
