# EKS control plane + managed node group. Workloads are NOT defined here —
# they live in ../k8s/ (see README.md, "Dual-layer convention").

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version # 1.35, standard support (verified 2026-07)

  # Standard support only — extended support bills ~6x the control-plane rate
  # once the minor version ages out, which this test bed must never do.
  upgrade_policy {
    support_type = "STANDARD"
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    # Default-VPC subnets (data sources; this stack never creates VPC pieces).
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks,
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "ems-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = data.aws_subnets.default.ids

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND" # lab account: Spot is denied; never change this

  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count
    min_size     = var.node_count
  }

  update_config {
    max_unavailable = 1
  }

  # Nodes need these policies attached before they can join the cluster, and
  # they must remain attached until after the group is destroyed.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
