output "api_endpoint" {
  description = "Public base URL of the task-reminder API"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "exports_bucket" {
  value = aws_s3_bucket.exports.bucket
}
