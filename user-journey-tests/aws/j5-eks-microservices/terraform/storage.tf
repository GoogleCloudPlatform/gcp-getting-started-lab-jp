# Booking persistence + container image registries.

resource "aws_dynamodb_table" "bookings" {
  name         = "ems-bookings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }
}

# One repository per microservice; images are built and pushed by
# scripts/deploy.sh and pulled by the node role (ECR read-only attachment).
resource "aws_ecr_repository" "catalog_api" {
  name         = "ems-catalog-api"
  force_delete = true # test bed: teardown removes the repo even with images in it

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "booking_api" {
  name         = "ems-booking-api"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
