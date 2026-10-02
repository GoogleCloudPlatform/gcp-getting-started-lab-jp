# Three functions share one code layout: scripts/deploy.sh assembles
# ${var.lambda_build_dir}/<fn>/ containing app.py (the handler) plus
# aws_clients.py copied from app/shared/. Zips are rebuilt on every apply.

locals {
  functions = {
    tasks_api = {
      name        = "${local.prefix}tasks-api"
      description = "Task-reminder HTTP API (behind API Gateway)"
    }
    export_worker = {
      name        = "${local.prefix}export-worker"
      description = "Nightly task export to S3"
    }
    cleanup_legacy = {
      name        = "${local.prefix}cleanup-legacy"
      description = "Purges completed tasks older than 90 days (manual invoke)"
    }
  }
}

data "archive_file" "fn" {
  for_each    = local.functions
  type        = "zip"
  source_dir  = "${var.lambda_build_dir}/${each.key}"
  output_path = "${var.lambda_build_dir}/${each.key}.zip"
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${each.value.name}"
  retention_in_days = 14
}

resource "aws_iam_role" "fn" {
  for_each = local.functions
  name     = "${each.value.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Log groups are pre-created above, so the functions only ever need to write
# streams into their own group — no wildcard CreateLogGroup grant.
resource "aws_iam_role_policy" "fn_logs" {
  for_each = local.functions
  name     = "${each.value.name}-logs"
  role     = aws_iam_role.fn[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteOwnLogGroup"
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        aws_cloudwatch_log_group.fn[each.key].arn,
        "${aws_cloudwatch_log_group.fn[each.key].arn}:*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "tasks_api" {
  name = "sta-tasks-api-data"
  role = aws_iam_role.fn["tasks_api"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TableCrud"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Scan", "dynamodb:Query", "dynamodb:DescribeTable"]
        Resource = [aws_dynamodb_table.tasks.arn, "${aws_dynamodb_table.tasks.arn}/index/*"]
      },
      {
        Sid      = "BucketPing"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.exports.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "export_worker" {
  name = "sta-export-worker-data"
  role = aws_iam_role.fn["export_worker"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TableRead"
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:DescribeTable"]
        Resource = [aws_dynamodb_table.tasks.arn, "${aws_dynamodb_table.tasks.arn}/index/*"]
      },
      {
        Sid      = "ExportWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.exports.arn}/exports/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "cleanup_legacy" {
  name = "sta-cleanup-legacy-data"
  role = aws_iam_role.fn["cleanup_legacy"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "TablePurge"
      Effect   = "Allow"
      Action   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
      Resource = [aws_dynamodb_table.tasks.arn, "${aws_dynamodb_table.tasks.arn}/index/*"]
    }]
  })
}

resource "aws_lambda_function" "fn" {
  for_each         = local.functions
  function_name    = each.value.name
  description      = each.value.description
  role             = aws_iam_role.fn[each.key].arn
  runtime          = "python3.12" # (verified 2026-07: supported into 2028)
  handler          = "app.handler"
  memory_size      = 256
  timeout          = 30
  filename         = data.archive_file.fn[each.key].output_path
  source_code_hash = data.archive_file.fn[each.key].output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tasks.name
      BUCKET     = aws_s3_bucket.exports.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn]
}
