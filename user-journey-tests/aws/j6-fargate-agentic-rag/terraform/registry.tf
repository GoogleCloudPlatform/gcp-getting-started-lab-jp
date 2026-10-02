# Container registry for the copilot image.

resource "aws_ecr_repository" "copilot" {
  name         = "arc-policy-copilot"
  force_delete = true # test bed: terraform destroy works with images present

  image_scanning_configuration {
    scan_on_push = true
  }
}
