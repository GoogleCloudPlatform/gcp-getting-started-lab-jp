# The copilot itself: ECS on Fargate, one task, fronted by the ALB.
# IAM lives here too — the roles exist only for this service.

resource "aws_ecs_cluster" "arc" {
  name = "arc"
}

resource "aws_cloudwatch_log_group" "copilot" {
  name              = "/arc/policy-copilot"
  retention_in_days = 14
}

data "aws_iam_policy_document" "assume_ecs_task" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pull_and_log" {
  name               = "arc-copilot-pull-and-log"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_task.json
}

resource "aws_iam_role_policy_attachment" "pull_and_log" {
  role       = aws_iam_role.pull_and_log.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "copilot" {
  name               = "arc-copilot-runtime"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_task.json
}

data "aws_iam_policy_document" "copilot_runtime" {
  statement {
    sid = "ConversationLog"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.conversations.arn]
  }

  statement {
    sid = "KnowledgeBaseCredentials"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.kb.arn]
  }

  statement {
    # "model" answer mode: LiteLLM's bedrock/ route signs with these
    # task-role credentials. Harmless in pipeline mode.
    sid = "BedrockInvoke"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "copilot_runtime" {
  name   = "arc-copilot-runtime"
  role   = aws_iam_role.copilot.id
  policy = data.aws_iam_policy_document.copilot_runtime.json
}

resource "aws_ecs_task_definition" "copilot" {
  family                   = "arc-policy-copilot"
  cpu                      = "1024"
  memory                   = "2048"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.pull_and_log.arn
  task_role_arn            = aws_iam_role.copilot.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "copilot"
      image     = "${aws_ecr_repository.copilot.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        { containerPort = var.container_port, protocol = "tcp" }
      ]

      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "AWS_DEFAULT_REGION", value = var.region },
        { name = "ANSWER_MODE", value = var.answer_mode },
        { name = "BEDROCK_MODEL_ID", value = var.bedrock_model_id },
        { name = "CONVERSATIONS_TABLE", value = aws_dynamodb_table.conversations.name },
        { name = "KB_SECRET_ARN", value = aws_secretsmanager_secret.kb.arn },
        { name = "KB_HOST", value = aws_db_instance.kb.address },
        { name = "KB_DATABASE", value = "policykb" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.copilot.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "copilot"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "copilot" {
  name            = "arc-policy-copilot"
  cluster         = aws_ecs_cluster.arc.id
  task_definition = aws_ecs_task_definition.copilot.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 90

  network_configuration {
    subnets         = data.aws_subnets.this.ids
    security_groups = [aws_security_group.workload.id]
    # Default VPC, no NAT: the public IP is the egress path to ECR, Secrets
    # Manager, DynamoDB and Bedrock. Inbound stays SG-gated to the ALB.
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.copilot.arn
    container_name   = "copilot"
    container_port   = var.container_port
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy.copilot_runtime,
  ]
}
