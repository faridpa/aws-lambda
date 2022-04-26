data "archive_file" "zipit" {
  type        = "zip"
  source_file = "index.js"
  output_path = "function.zip"
}

resource "aws_lambda_function" "test_lambda" {
  architectures                  = ["x86_64"]
  filename                       = "function.zip"
  function_name                  = "${var.name}-lambda-function"
  role                           = aws_iam_role.iam_for_lambda.arn
  package_type                   = "Zip"
  reserved_concurrent_executions = "-1"
  handler                        = "index.handler"
  description                    = "Simple nodejs app"
  source_code_hash               = data.archive_file.zipit.output_base64sha256
  runtime                        = "nodejs14.x"
  timeout                        = "3"
  tracing_config {
    mode = "PassThrough"
  }
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.photo-bucket.bucket
    }
  }
}

resource "aws_lambda_function_url" "test_url" {
  function_name      = aws_lambda_function.test_lambda.function_name
  authorization_type = "NONE"
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "${var.name}-lambda-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.name}-lambda-s3-role"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ],
        Resource = [
          "${aws_s3_bucket.photo-bucket.arn}",
          "${aws_s3_bucket.photo-bucket.arn}/*"
        ],
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "AWSLambdaBasicExecutionRole" {
  name = "${var.name}-lambda-logs-role"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup"
        ],
        Resource = [
          "arn:aws:logs:us-west-1:030421842412:*",
        ],
        Effect = "Allow"
      },
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:us-west-1:030421842412:log-group:/aws/lambda/${aws_lambda_function.test_lambda.function_name}:*"
        ],
        Effect = "Allow"
      }
    ]
  })
}