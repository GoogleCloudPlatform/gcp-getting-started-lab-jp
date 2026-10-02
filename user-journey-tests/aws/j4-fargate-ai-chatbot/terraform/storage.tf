# Conversation store + transcript archive bucket.

resource "aws_dynamodb_table" "conversations" {
  name         = "fac-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "conversation_id"
  range_key    = "ts"

  attribute {
    name = "conversation_id"
    type = "S"
  }

  attribute {
    name = "ts"
    type = "N"
  }
}

resource "aws_s3_bucket" "transcripts" {
  bucket        = "fac-transcripts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # test bed: allow terraform destroy with objects present
}

resource "aws_s3_bucket_public_access_block" "transcripts" {
  bucket = aws_s3_bucket.transcripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transcripts" {
  bucket = aws_s3_bucket.transcripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transcripts" {
  bucket = aws_s3_bucket.transcripts.id

  rule {
    id     = "expire-transcripts-90d"
    status = "Enabled"

    filter {
      prefix = "transcripts/"
    }

    expiration {
      days = 90
    }
  }
}
