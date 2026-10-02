# IAM: standard execution role + a task role scoped to what fac-api touches.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- execution role (image pull + log delivery) ------------------------------

resource "aws_iam_role" "execution" {
  name               = "fac-api-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- task role (what the app itself may call) --------------------------------

resource "aws_iam_role" "task" {
  name               = "fac-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "task_permissions" {
  # Model invocation. Resource is "*" because invocations through a
  # cross-region inference profile resolve to foundation-model ARNs in
  # whichever destination region serves the request — the ARNs vary by
  # inference profile and region, so the customer scoped by action instead.
  statement {
    sid = "InvokeModels"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = ["*"]
  }

  # Control-plane catalog read used by the /admin/aws-check dashboard.
  statement {
    sid       = "ListModels"
    actions   = ["bedrock:ListFoundationModels"]
    resources = ["*"]
  }

  statement {
    sid = "ConversationTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.conversations.arn]
  }

  statement {
    sid = "TranscriptObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.transcripts.arn}/*"]
  }

  statement {
    sid = "TranscriptBucket"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.transcripts.arn]
  }
}

resource "aws_iam_role_policy" "task_permissions" {
  name   = "fac-api-task-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}
