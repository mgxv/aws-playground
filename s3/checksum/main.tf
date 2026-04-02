terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "6.39.0"
        }
    }
}

resource "aws_s3_bucket" "default" {
}

resource "aws_s3_object" "default" {
    bucket      = aws_s3_bucket.default.id
    key         = "demo.txt"
    source      = "demo.txt"
    etag        = filemd5("demo.txt")
    checksum_algorithm = "SHA256"
    source_hash = filesha256("demo.txt")
}