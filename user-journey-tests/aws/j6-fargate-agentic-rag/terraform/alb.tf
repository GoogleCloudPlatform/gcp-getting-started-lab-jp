# Public front door: one application load balancer, one HTTP listener,
# one target group health-checking the copilot's /healthz.

resource "aws_lb" "front" {
  name               = "arc-front"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.edge.id]
  subnets            = data.aws_subnets.this.ids
}

resource "aws_lb_target_group" "copilot" {
  name        = "arc-copilot"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.this.id

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 10 # test bed: fast drains over graceful long tails
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.front.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.copilot.arn
  }
}
