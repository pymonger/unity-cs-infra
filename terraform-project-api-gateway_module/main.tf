# REST API Gateway
resource "aws_api_gateway_rest_api" "rest_api" {
  name        = "unity-${var.project}-${var.venue}-rest-api-gateway"
  description = "Unity ${var.project}-${var.venue} Project REST API Gateway"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "api-gateway-stage" {
  deployment_id = aws_api_gateway_deployment.api-gateway-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  stage_name    = "default"
}


# REST API Gateway root level OPTIONS method (to allow deployment with at least one method)
resource "aws_api_gateway_method" "root_level_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  resource_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# REST API Gateway root level GET method mock integration
resource "aws_api_gateway_integration" "root_level_get_method_mock_integration" {
  rest_api_id          = aws_api_gateway_rest_api.rest_api.id
  resource_id          = aws_api_gateway_rest_api.rest_api.root_resource_id
  http_method          = aws_api_gateway_method.root_level_options_method.http_method
  type                 = "MOCK"
}

# REST API ID SSM Param for other resources to modify rest api
resource "aws_ssm_parameter" "api_gateway_rest_api_id_parameter" {
  name       = format("/unity/cs/routing/api-gateway/rest-api-id-2")
  type       = "String"
  overwrite  = true
  value      = aws_api_gateway_rest_api.rest_api.id
  depends_on = [aws_api_gateway_rest_api.rest_api]
}

# Download the Unity CS Common Auth Lambda deployment zip file
resource "null_resource" "download_lambda_zip" {
  provisioner "local-exec" {
    command = "wget --no-check-certificate ${var.unity_cs_lambda_authorizer_zip_path}  -O ucs-common-lambda-auth.zip"
  }
}

# CloudWatch Log Group for Unity CS Common Auth Lambda
resource "aws_cloudwatch_log_group" "cs_common_lambda_auth_log_group" {
  name              = "/aws/lambda/${var.deployment_name}-${var.unity_cs_lambda_authorizer_function_name}"
  retention_in_days = 14
}

resource "aws_ssm_parameter" "invoke_role_arn" {
  name  = var.ssm_param_api_gateway_cs_lambda_authorizer_invoke_role_arn
  overwrite = true
  type  = "String"
  value = aws_iam_role.iam_for_lambda_auth.arn
}

#Unity shared serive account id
data "aws_ssm_parameter" "shared_service_account_id"{
  name = var.ssm_account_id
}

#Unity shared serive account region
data "aws_ssm_parameter" "shared_service_region"{
  name = var.ssm_region
}

# Unity CS Common Lambda Authorizer Allowed Cognito Client ID List (Command Seperated)
data "aws_ssm_parameter" "api_gateway_cs_lambda_authorizer_cognito_client_id_list" {
  name = var.ssm_param_api_gateway_cs_lambda_authorizer_cognito_client_id_list
}

# Unity CS Common Lambda Authorizer Allowed Cognito User Pool ID
data "aws_ssm_parameter" "api_gateway_cs_lambda_authorizer_cognito_user_pool_id" {
  name = "arn:aws:ssm:${data.aws_ssm_parameter.shared_service_region.value}:${data.aws_ssm_parameter.shared_service_account_id.value}:parameter/unity/cs/routing/venue-api-gateway/cs-lambda-authorizer-cognito-user-pool-id"
}

# Unity CS Common Lambda Authorizer Allowed Cognito User Groups List (Command Seperated)
data "aws_ssm_parameter" "api_gateway_cs_lambda_authorizer_cognito_user_groups_list" {
  name = "arn:aws:ssm:${data.aws_ssm_parameter.shared_service_region.value}:${data.aws_ssm_parameter.shared_service_account_id.value}:parameter/unity/cs/routing/venue-api-gateway/cs-lambda-authorizer-cognito-user-groups-list"
}

# IAM Policy Document for Assume Role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "apigateway.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM Policy Document for Inline Policy
data "aws_iam_policy_document" "inline_policy" {
  statement {
    actions   = ["logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "lambda:InvokeFunction"]
    resources = ["*"]
  }
}

# The Policy for Permission Boundary
data "aws_iam_policy" "mcp_operator_policy" {
  name = "mcp-tenantOperator-AMI-APIG"
}

# IAM Role for Lambda Authorizer
resource "aws_iam_role" "iam_for_lambda_auth" {
  name = "${var.deployment_name}-iam_for_lambda_auth"
  inline_policy {
    name   = "unity-cs-lambda-auth-inline-policy"
    policy = data.aws_iam_policy_document.inline_policy.json
  } 
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = data.aws_iam_policy.mcp_operator_policy.arn
}

# Unity CS Common Auth Lambda
resource "aws_lambda_function" "cs_common_lambda_auth" {
  filename      = "ucs-common-lambda-auth.zip"
  function_name = "${var.deployment_name}-${var.unity_cs_lambda_authorizer_function_name}"
  role          = aws_iam_role.iam_for_lambda_auth.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  depends_on = [null_resource.download_lambda_zip]

  environment {
    variables = {
      COGNITO_CLIENT_ID_LIST = data.aws_ssm_parameter.api_gateway_cs_lambda_authorizer_cognito_client_id_list.value
      COGNITO_USER_POOL_ID = data.aws_ssm_parameter.api_gateway_cs_lambda_authorizer_cognito_user_pool_id.value
      COGNITO_GROUPS_ALLOWED = data.aws_ssm_parameter.api_gateway_cs_lambda_authorizer_cognito_user_groups_list.value
    }
  }
}

# Unity CS Common Auth Lambda Authorizer (in API Gateway)
resource "aws_api_gateway_authorizer" "unity_cs_common_authorizer" {
  name                              = "Unity_CS_Common_Authorizer"
  rest_api_id                       = aws_api_gateway_rest_api.rest_api.id
  authorizer_uri                    = aws_lambda_function.cs_common_lambda_auth.invoke_arn
  authorizer_credentials            = aws_iam_role.iam_for_lambda_auth.arn
  authorizer_result_ttl_in_seconds  = 0
  identity_source                   = "method.request.header.Authorization"
depends_on = [aws_lambda_function.cs_common_lambda_auth, aws_api_gateway_rest_api.rest_api]
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api-gateway-deployment" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  stage_name  = var.rest_api_stage
  depends_on = [aws_api_gateway_integration.root_level_get_method_mock_integration]
}


resource "aws_ssm_parameter" "api_gateway_uri" {
  name = "/unity/cs/management/api-gateway/gateway-uri"
  overwrite = true
  type = "String"
  value = "https://${aws_api_gateway_rest_api.rest_api.id}.execute-api.${data.aws_ssm_parameter.shared_service_region.value}.amazonaws.com/${aws_api_gateway_stage.api-gateway-stage.stage_name}"
}


# Updater to add the API Heath Check Routing
# ------------------------------------------

resource "aws_lb" "internal_lb" {
  name               = "internal_lb"
  internal           = true
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id = var.privatesubnets
  }
}

resource "aws_api_gateway_vpc_link" "example" {
  name        = "vpc_link"
  description = "VPC Link for Internal API Gateway"
  target_arns = [aws_lb.internal_lb.arn]
}
