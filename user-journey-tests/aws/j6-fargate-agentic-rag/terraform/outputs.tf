# Everything the deploy/bootstrap/smoke scripts need to find the estate.

output "front_url" {
  value = "http://${aws_lb.front.dns_name}"
}

output "image_repo" {
  value = aws_ecr_repository.copilot.repository_url
}

output "cluster" {
  value = aws_ecs_cluster.arc.name
}

output "service" {
  value = aws_ecs_service.copilot.name
}

output "task_family" {
  value = aws_ecs_task_definition.copilot.family
}

output "workload_security_group" {
  value = aws_security_group.workload.id
}

output "subnets" {
  value = data.aws_subnets.this.ids
}

output "kb_endpoint" {
  value = aws_db_instance.kb.address
}

output "conversations_table" {
  value = aws_dynamodb_table.conversations.name
}
