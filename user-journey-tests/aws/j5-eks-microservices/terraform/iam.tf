# IAM for the cluster, the worker nodes, and the booking-api pod identity.
#
# The IRSA chain at the bottom is what lets the booking-api PODS (not the
# nodes) reach DynamoDB: OIDC provider -> role trust on the pod's service
# account -> eks.amazonaws.com/role-arn annotation on that service account
# (declared in ../k8s/booking-api.yaml, NOT here).

# ---- control plane role --------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "ems-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_eks" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---- worker node role ------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "ems-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---- IRSA: OIDC provider + booking-api pod role -----------------------------------

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint]
}

locals {
  # Issuer host/path without the scheme, as used in trust-policy condition keys.
  oidc_issuer = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

resource "aws_iam_role" "booking_irsa" {
  name = "ems-booking-irsa"

  # Only the booking-api service account in the ems namespace may assume
  # this role. catalog-api has no AWS permissions at all.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:ems:booking-api"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "booking_dynamodb" {
  name = "ems-booking-dynamodb"
  role = aws_iam_role.booking_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BookingsTableCrud"
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:DescribeTable",
      ]
      Resource = [aws_dynamodb_table.bookings.arn]
    }]
  })
}
