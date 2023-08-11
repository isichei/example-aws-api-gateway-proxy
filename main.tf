provider "aws" {
  region = "eu-west-2"
}

### LAMBDAS
resource "aws_iam_role" "lambda_role" {
  name = "proxy-lambda-role"

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


# Attach a basic IAM policy to the role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Create a ZIP archive containing your Go binary
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "bin/bootstrap"
  output_path = "lambda-zips/aws-lambda-go.zip"
}

# Create the Lambda function
resource "aws_lambda_function" "proxy_lambda" {
  function_name    = "aws-proxy-lambda"
  filename         = data.archive_file.lambda_zip.output_path
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = "go1.x"
  timeout          = 10
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
}

### AWS API GATEWAY DEFINITIONS

# Define the rest API
resource "aws_api_gateway_rest_api" "app_rest_api" {
  name        = "proxy-api"
  description = "API Gateway Proxy test"
}

# Allow the API GW to invoke our lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy_lambda.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.app_rest_api.execution_arn}/*/*/*"
}

# Define root resource response (lets only allow GET)
resource "aws_api_gateway_method" "root_method" {
  rest_api_id   = aws_api_gateway_rest_api.app_rest_api.id
  resource_id   = aws_api_gateway_rest_api.app_rest_api.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

# Integrate our single monolith lambda to the GET / method of our API Gateway
resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.app_rest_api.id
  resource_id             = aws_api_gateway_rest_api.app_rest_api.root_resource_id
  http_method             = aws_api_gateway_method.root_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.proxy_lambda.invoke_arn
}

# Now create a Proxy Resource to handle all other requests
resource "aws_api_gateway_resource" "proxy_resource" {
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.app_rest_api.id
  parent_id   = aws_api_gateway_rest_api.app_rest_api.root_resource_id
}

# Attach a method to the proxy resource to allow ANY http request
resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.app_rest_api.id
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

# Attach our same lambda to the proxy resource
resource "aws_api_gateway_integration" "proxy_integration" {
  rest_api_id             = aws_api_gateway_rest_api.app_rest_api.id
  resource_id             = aws_api_gateway_resource.proxy_resource.id
  http_method             = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.proxy_lambda.invoke_arn
}

### API DEPLOYMENT ###
resource "aws_api_gateway_stage" "app_stage" {
  deployment_id = aws_api_gateway_deployment.app_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.app_rest_api.id
  stage_name    = "dev"
}

# resource "aws_api_gateway_deployment" "app_deployment" {
#   rest_api_id       = aws_api_gateway_rest_api.app_rest_api.id

#   triggers = {
#     redeployment = sha1(jsonencode(aws_api_gateway_rest_api.app_rest_api.body))
#   }
#   lifecycle {
#     create_before_destroy = true
#   }
#   depends_on = [
#     aws_api_gateway_method.root_method,
#     aws_api_gateway_integration.root_integration,
#     aws_api_gateway_resource.proxy_resource,
#     aws_api_gateway_method.proxy_method,
#     aws_api_gateway_integration.proxy_integration
#   ]
# }

resource "aws_api_gateway_deployment" "app_deployment" {
  rest_api_id = aws_api_gateway_rest_api.app_rest_api.id
  description = "Deployed at ${timestamp()}"
  triggers = {

    redeployment = sha1(jsonencode([
      aws_api_gateway_method.root_method.id,
      aws_api_gateway_integration.root_integration.id,
      aws_api_gateway_resource.proxy_resource.id,
      aws_api_gateway_method.proxy_method.id,
      aws_api_gateway_integration.proxy_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

