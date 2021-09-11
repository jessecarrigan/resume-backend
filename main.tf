terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }
  required_version = "~> 1.0"
}

provider "aws" {
  region                  = "us-west-2"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "cli"
}

# Lambda bucket
resource "random_pet" "lambda_bucket_name" {
  prefix = "resume-views"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id

  acl           = "private"
  force_destroy = true
}

data "archive_file" "lambda_resume_views" {
  type = "zip"

  source_dir  = "${path.module}/resume-views"
  output_path = "${path.module}/resume-views.zip"
}

resource "aws_s3_bucket_object" "lambda_resume_views" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "resume-views.zip"
  source = data.archive_file.lambda_resume_views.output_path

  etag = filemd5(data.archive_file.lambda_resume_views.output_path)
}

# Lambda function
resource "aws_lambda_function" "resume_views" {
  function_name = "ResumeViews"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_bucket_object.lambda_resume_views.key

  runtime = "python3.8"
  handler = "app.handler"

  source_code_hash = data.archive_file.lambda_resume_views.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "resume_views" {
  name = "/aws/lambda/${aws_lambda_function.resume_views.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# API Gateway

resource "aws_apigatewayv2_api" "lambda" {
  name          = "resume_views_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "resume_views_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "resume_views" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.resume_views.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_resume_views" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /views"
  target    = "integrations/${aws_apigatewayv2_integration.resume_views.id}"
}

resource "aws_apigatewayv2_route" "post_resume_views" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /views"
  target    = "integrations/${aws_apigatewayv2_integration.resume_views.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_views.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

# DynamoDB

resource "aws_dynamodb_table" "resume_views_table" {
  name         = "resume-views"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role_policy" "dynamodb_lambda_policy" {
  name = "dynamodb-lambda-policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        "Resource" : "${aws_dynamodb_table.resume_views_table.arn}"
      }
    ]
  })
}
