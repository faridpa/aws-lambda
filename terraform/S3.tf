resource "aws_s3_bucket" "photo-bucket" {
  bucket        = "${var.name}-bucket-faridp"
  force_destroy = true
  tags          = {}
}

resource "aws_s3_bucket_acl" "photo-bucket-acl" {
  bucket = aws_s3_bucket.photo-bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "photo-bucket-versioning" {
  bucket = aws_s3_bucket.photo-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "photo-bucket-encryption" {
  bucket = aws_s3_bucket.photo-bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "photo-bucket-lifecycle" {
  depends_on = [aws_s3_bucket_versioning.photo-bucket-versioning]
  bucket     = aws_s3_bucket.photo-bucket.bucket
  rule {
    id     = "expiry"
    status = "Enabled"
    expiration {
      days = 10
    }
    noncurrent_version_expiration {
      noncurrent_days = 10
    }
  }
}

resource "aws_s3_bucket_public_access_block" "photo-bucket-acls" {
  bucket                  = aws_s3_bucket.photo-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}