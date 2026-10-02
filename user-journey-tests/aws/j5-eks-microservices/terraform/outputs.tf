# Outputs consumed by scripts/deploy.sh (kubeconfig, image push, manifest
# rendering) and scripts/teardown.sh.

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.main.version
}

output "ecr_catalog_repository_url" {
  value = aws_ecr_repository.catalog_api.repository_url
}

output "ecr_booking_repository_url" {
  value = aws_ecr_repository.booking_api.repository_url
}

output "booking_irsa_role_arn" {
  description = "Rendered into the booking-api ServiceAccount annotation by deploy.sh."
  value       = aws_iam_role.booking_irsa.arn
}

output "bookings_table_name" {
  value = aws_dynamodb_table.bookings.name
}

output "region" {
  value = var.aws_region
}
