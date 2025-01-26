locals {
  # Retrieve the secret from AWS Secrets Manager
  clean_energy_secrets = jsondecode(data.aws_secretsmanager_secret_version.clean_energy_secrets.secret_string)

  # Extract the API keys from the secret
  openweather_api_key = local.clean_energy_secrets["OPENWEATHER_API_KEY"]
  nrel_api_key         = local.clean_energy_secrets["NREL_API_KEY"]
  lambda_image_uri     = "${var.accountID}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.lambda_function_name}:latest"
}

# Data source to fetch the secret from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "clean_energy_secrets" {
  secret_id = "clean-energy-secrets"
}



# Create an IAM role for the Lambda function
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the basic execution policy to the role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "clean_energy_lambda" {
  function_name = "clean-energy-lambda"
  role          = aws_iam_role.lambda_exec_role.arn

  # Use the ECR image URI
  image_uri = "${var.accountID}.dkr.ecr.${var.aws_region}.amazonaws.com/clean-energy-lambda:latest"

  # Specify the package type as "Image"
  package_type = "Image"

  # Environment variables (if needed)
  environment {
    variables = {
      OPEN_WEATHER_API_KEY = local.openweather_api_key
      NREL_API_KEY         = local.nrel_api_key
    }
  }
}

# IAM Policy for Lambda to access S3 and CloudWatch
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "Policy for Lambda to access S3 and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# S3 Bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.s3_bucket_name
}

# Lambda Function
resource "aws_lambda_function" "my_lambda" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  # Use a Docker container image
  image_uri     = local.lambda_image_uri 
  package_type  = "Image"               

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.my_bucket.bucket
    }
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.my_lambda.function_name}"
  retention_in_days = var.cloudwatch_log_retention
}