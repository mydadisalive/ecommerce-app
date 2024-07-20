terraform {
  backend "remote" {
    organization = "avicii-corp"
    workspaces {
      name = "ecommerce-app"
    }
  }
}

provider "aws" {
  region = "il-central-1"
}

# Function to compute ETag for files
locals {
  index_etag = filemd5("${path.module}/../frontend/index.html")
  error_etag = filemd5("${path.module}/../frontend/error.html")
  css_etags  = { for k, v in fileset("${path.module}/../frontend/css", "**/*") : k => filemd5("${path.module}/../frontend/css/${k}") }
  image_etags = { for k, v in fileset("${path.module}/../frontend/images", "**/*") : k => filemd5("${path.module}/../frontend/images/${k}") }
}

# S3 Bucket for Frontend
resource "aws_s3_bucket" "frontend" {
  bucket = "ecommerce-frontend-bucket-unique-12345"
  tags = {
    Name        = "ecommerce-frontend"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  content_type = "text/html"
  etag         = local.index_etag
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "error.html"
  source       = "${path.module}/../frontend/error.html"
  content_type = "text/html"
  etag         = local.error_etag
}

resource "aws_s3_object" "css_files" {
  for_each     = local.css_etags
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "css/${each.key}"
  source       = "${path.module}/../frontend/css/${each.key}"
  content_type = "text/css"
  etag         = each.value
}

resource "aws_s3_object" "image_files" {
  for_each     = local.image_etags
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "images/${each.key}"
  source       = "${path.module}/../frontend/images/${each.key}"
  content_type = lookup({
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "png"  = "image/png",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml"
  }, substr(each.key, length(each.key) - 3, 3), "application/octet-stream")
  etag         = each.value
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_public_access" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Lambda Function for Backend
resource "aws_lambda_function" "backend" {
  filename         = "${path.module}/../backend/lambda_function.zip"
  function_name    = "ecommerce-backend"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda_function.zip")
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "ecommerce-api"
  description = "E-commerce API"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_method" "root_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "products_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "POST"
  authorization = "NONE"
}

# Create GET method for /products resource
resource "aws_api_gateway_method" "products_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "GET"
  authorization = "NONE"
}

# Method Response for root method
resource "aws_api_gateway_method_response" "root_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.root_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Method Response for products method
resource "aws_api_gateway_method_response" "products_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.products_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Method Response for GET /products
resource "aws_api_gateway_method_response" "products_get_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.products_get_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = aws_api_gateway_method.root_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.backend.invoke_arn
}

resource "aws_api_gateway_integration" "products_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.products_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.backend.invoke_arn
}

# Integration for GET /products
resource "aws_api_gateway_integration" "products_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.products_get_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.backend.invoke_arn
}

# Integration Response for root integration
resource "aws_api_gateway_integration_response" "root_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.root_method.http_method
  status_code = aws_api_gateway_method_response.root_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }
}

# Integration Response for products integration
resource "aws_api_gateway_integration_response" "products_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.products_method.http_method
  status_code = aws_api_gateway_method_response.products_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.products_integration
  ]
}

# Integration Response for GET /products
resource "aws_api_gateway_integration_response" "products_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.products_get_method.http_method
  status_code = aws_api_gateway_method_response.products_get_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.products_get_integration
  ]
}

# Add CORS OPTIONS method to the root resource
resource "aws_api_gateway_method" "options_root_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = aws_api_gateway_method.options_root_method.http_method
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_root_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.options_root_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_root_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.options_root_method.http_method
  status_code = aws_api_gateway_method_response.options_root_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.options_root_integration
  ]
}

# Add CORS OPTIONS method to the products resource
resource "aws_api_gateway_method" "options_products_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_products_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.products.id
  http_method             = aws_api_gateway_method.options_products_method.http_method
  type                    = "MOCK"
  integration_http_method = "OPTIONS"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_products_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.options_products_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_products_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.products.id
  http_method = aws_api_gateway_method.options_products_method.http_method
  status_code = aws_api_gateway_method_response.options_products_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.options_products_integration
  ]
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  # Add a stage description to force new deployments
  description = "New deployment for GET and OPTIONS methods on /products"

  depends_on = [
    aws_api_gateway_integration.root_integration,
    aws_api_gateway_integration.products_integration,
    aws_api_gateway_integration.options_root_integration,
    aws_api_gateway_integration.options_products_integration,
    aws_api_gateway_integration.products_get_integration,
  ]
}

output "website_url" {
  value = "http://${aws_s3_bucket.frontend.website_endpoint}"
}

output "api_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "products_api_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}/products"
}
