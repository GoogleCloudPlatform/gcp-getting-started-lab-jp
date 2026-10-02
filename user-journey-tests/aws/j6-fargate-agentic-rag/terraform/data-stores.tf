# State: the Postgres knowledge base (full-text + trigram indexes, built by
# policyapi.bootstrap) and the DynamoDB conversation log (item per turn).

resource "aws_db_subnet_group" "kb" {
  name       = "arc-kb"
  subnet_ids = data.aws_subnets.this.ids
}

resource "random_password" "kb" {
  length  = 28
  special = false
}

resource "aws_db_instance" "kb" {
  identifier     = "arc-kb"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "policykb"
  username = "copilot"
  password = random_password.kb.result

  db_subnet_group_name   = aws_db_subnet_group.kb.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  skip_final_snapshot = true  # test bed
  deletion_protection = false # test bed
}

resource "aws_secretsmanager_secret" "kb" {
  name                    = "arc/kb/connection"
  description             = "Knowledge-base connection JSON for the policy copilot"
  recovery_window_in_days = 0 # test bed: allow immediate re-create
}

resource "aws_secretsmanager_secret_version" "kb" {
  secret_id = aws_secretsmanager_secret.kb.id
  secret_string = jsonencode({
    host     = aws_db_instance.kb.address
    port     = 5432
    user     = "copilot"
    password = random_password.kb.result
    dbname   = "policykb"
  })
}

resource "aws_dynamodb_table" "conversations" {
  name         = "arc-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "conversation_id"
  range_key    = "turn_at"

  attribute {
    name = "conversation_id"
    type = "S"
  }

  attribute {
    name = "turn_at"
    type = "N"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
