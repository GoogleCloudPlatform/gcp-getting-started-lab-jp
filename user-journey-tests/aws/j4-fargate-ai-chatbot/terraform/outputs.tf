output "ecr_repository_url" {
  description = "Push target for the fac-api image."
  value       = aws_ecr_repository.fac_api.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.fac.name
}

output "service_name" {
  value = aws_ecs_service.fac_api.name
}

output "table_name" {
  value = aws_dynamodb_table.conversations.name
}

output "bucket_name" {
  value = aws_s3_bucket.transcripts.bucket
}

output "security_group_id" {
  value = aws_security_group.fac_api.id
}

output "region" {
  value = var.aws_region
}
