# ECS Fargate: cluster, logs, security group, task definition, service.

resource "aws_ecs_cluster" "fac" {
  name = "fac-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "fac" {
  cluster_name       = aws_ecs_cluster.fac.name
  capacity_providers = ["FARGATE"] # on-demand only

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "fac_api" {
  name              = "/ecs/fac-api"
  retention_in_days = 14
}

resource "aws_security_group" "fac_api" {
  name        = "fac-api-sg"
  description = "fac-api task: API port ingress, all egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "API clients"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound (AWS APIs, image pull)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "fac_api" {
  family                   = "fac-api"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "fac-api"
      image     = "${aws_ecr_repository.fac_api.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "TABLE_NAME", value = aws_dynamodb_table.conversations.name },
        { name = "BUCKET", value = aws_s3_bucket.transcripts.bucket },
        { name = "MODEL_ID", value = var.model_id },
        { name = "BEDROCK_REGION", value = var.bedrock_region },
        { name = "LLM_MODE", value = var.llm_mode },
        { name = "PORT", value = tostring(var.app_port) },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.fac_api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "fac-api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "fac_api" {
  name            = "fac-api-service"
  cluster         = aws_ecs_cluster.fac.id
  task_definition = aws_ecs_task_definition.fac_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.fac_api.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy.task_permissions]
}
