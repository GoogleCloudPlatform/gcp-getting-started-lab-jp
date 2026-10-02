# Container registry for the fac-api image.

resource "aws_ecr_repository" "fac_api" {
  name         = "fac-api"
  force_delete = true # test bed: allow terraform destroy with images present

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "fac_api" {
  repository = aws_ecr_repository.fac_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
