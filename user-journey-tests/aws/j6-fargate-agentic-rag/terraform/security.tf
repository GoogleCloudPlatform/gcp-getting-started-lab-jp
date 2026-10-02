# Security groups: internet -> ALB :80 -> tasks :8080 -> Postgres :5432.
# Each hop admits exactly the previous hop and nothing else.

resource "aws_security_group" "edge" {
  name        = "arc-edge"
  description = "arc: public HTTP into the load balancer"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "edge_http" {
  security_group_id = aws_security_group.edge.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "edge_out" {
  security_group_id            = aws_security_group.edge.id
  description                  = "to the copilot tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.workload.id
}

resource "aws_security_group" "workload" {
  name        = "arc-workload"
  description = "arc: copilot tasks"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "workload_from_edge" {
  security_group_id            = aws_security_group.workload.id
  description                  = "app port from the load balancer only"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.edge.id
}

resource "aws_vpc_security_group_egress_rule" "workload_out" {
  security_group_id = aws_security_group.workload.id
  description       = "AWS APIs, ECR pulls, Bedrock, Postgres"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "database" {
  name        = "arc-database"
  description = "arc: knowledge base, reachable from copilot tasks only"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_workload" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the copilot tasks"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.workload.id
}
