resource "aws_api_gateway_rest_api" "test_api" {
  name                         = "${var.name}-api-gw"
  api_key_source               = "HEADER"
  disable_execute_api_endpoint = "false"
  description                  = "This is my API for demonstration purposes"
  minimum_compression_size     = "-1"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  binary_media_types = ["*/*"]
}

resource "aws_api_gateway_resource" "test_api_gw" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  parent_id   = aws_api_gateway_rest_api.test_api.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "method-post" {
  api_key_required = "false"
  rest_api_id      = aws_api_gateway_rest_api.test_api.id
  resource_id      = aws_api_gateway_resource.test_api_gw.id
  http_method      = "POST"
  authorization    = "NONE"
}

resource "aws_api_gateway_method" "method-options" {
  api_key_required = "false"
  rest_api_id      = aws_api_gateway_rest_api.test_api.id
  resource_id      = aws_api_gateway_resource.test_api_gw.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
}


resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.test_api.id
  resource_id             = aws_api_gateway_resource.test_api_gw.id
  http_method             = aws_api_gateway_method.method-post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.test_lambda.invoke_arn
  connection_type         = "INTERNET"
  content_handling        = "CONVERT_TO_TEXT"
  passthrough_behavior    = "WHEN_NO_MATCH"
  timeout_milliseconds    = "29000"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  resource_id = aws_api_gateway_resource.test_api_gw.id
  http_method = aws_api_gateway_method.method-options.http_method
  //type                    = "AWS_PROXY"
  uri                  = aws_lambda_function.test_lambda.invoke_arn
  connection_type      = "INTERNET"
  passthrough_behavior = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }

  timeout_milliseconds = "29000"
  type                 = "MOCK"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.test_api.execution_arn}/*/POST/upload"
}

resource "aws_api_gateway_deployment" "testdeploy" {
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.options_integration,
  ]
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.test_api.body))
  }
  rest_api_id = aws_api_gateway_rest_api.test_api.id
}

resource "aws_api_gateway_stage" "test-stage" {
  cache_cluster_enabled = "false"
  deployment_id         = aws_api_gateway_deployment.testdeploy.id
  rest_api_id           = aws_api_gateway_rest_api.test_api.id
  stage_name            = "test"
  xray_tracing_enabled  = "false"
}


resource "aws_api_gateway_method_response" "options_method_response" {
  http_method = aws_api_gateway_method.method-options.http_method
  resource_id = aws_api_gateway_resource.test_api_gw.id

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "false"
    "method.response.header.Access-Control-Allow-Methods" = "false"
    "method.response.header.Access-Control-Allow-Origin"  = "false"
  }

  rest_api_id = aws_api_gateway_rest_api.test_api.id
  status_code = "200"
}

resource "aws_api_gateway_method_response" "post_method_response" {
  http_method = aws_api_gateway_method.method-post.http_method
  resource_id = aws_api_gateway_resource.test_api_gw.id

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "false"
  }
  rest_api_id = aws_api_gateway_rest_api.test_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "options_integration_method" {
  http_method = aws_api_gateway_method.method-options.http_method
  resource_id = aws_api_gateway_resource.test_api_gw.id

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  rest_api_id = aws_api_gateway_rest_api.test_api.id
  status_code = aws_api_gateway_method_response.options_method_response.status_code
}

resource "aws_api_gateway_integration_response" "post_integration_response" {
  http_method = aws_api_gateway_method.method-post.http_method
  resource_id = aws_api_gateway_resource.test_api_gw.id

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  rest_api_id = aws_api_gateway_rest_api.test_api.id
  status_code = aws_api_gateway_method_response.post_method_response.status_code
}

/*resource "aws_api_gateway_model" "error_model" {
  content_type = "application/json"
  description  = "This is a default error schema model"
  name         = "${var.name}Error"
  rest_api_id  = aws_api_gateway_rest_api.test_api.id
  schema       = "{\n  \"$schema\" : \"http://json-schema.org/draft-04/schema#\",\n  \"title\" : \"Error Schema\",\n  \"type\" : \"object\",\n  \"properties\" : {\n    \"message\" : { \"type\" : \"string\" }\n  }\n}"
}

resource "aws_api_gateway_model" "empty_model" {
  content_type = "application/json"
  description  = "This is a default empty schema model"
  name         = "${var.name}Empty"
  rest_api_id  = aws_api_gateway_rest_api.test_api.id
  schema       = "{\n  \"$schema\": \"http://json-schema.org/draft-04/schema#\",\n  \"title\" : \"Empty Schema\",\n  \"type\" : \"object\"\n}"
}*/