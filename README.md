Building Serverless Applications in AWS
===


## Table of Contents

[TOC]

## Introduction

Serverless web applications are among the most talked-about trends in the cloud engineering space and have been since the introduction of [AWS Lambda](https://aws.amazon.com/lambda/) back in 2014. Today, serverless architecture empowers teams to increase agility, scalability, and efficiency for customer-facing applications and critical workloads.

Of course, serverless web applications still run on servers, but many aspects of server management are [AWS’s](https://aws.amazon.com/) responsibility. You can focus on your application code and forget time-killing tasks like provisioning, configuring, and maintaining servers.

In this tutorial you will review two different scenarios of using AWS Lambda service:

1. *Uploading any type of binary files to S3 via API Gateway.*
2. *Deploying simple NodeJS application to AWS Lambda using Function URL.* 

Let's talk about main differencies between [API Gateway](https://aws.amazon.com/api-gateway/) and newly announced [Lambda Function URL](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html):

Function URLs are best for use cases where you must implement a single-function microservice with a public endpoint that doesn’t require the advanced functionality of API Gateway, such as request validation, throttling, custom authorizers, custom domain names, usage plans, or caching. For example, when you are implementing webhook handlers, form validators, mobile payment processing, advertisement placement, machine learning inference, and so on. It is also the simplest way to invoke your Lambda functions during research and development without leaving the Lambda console or integrating additional services.

Amazon API Gateway is a fully managed service that makes it easy for you to create, publish, maintain, monitor, and secure APIs at any scale. Use API Gateway to take advantage of capabilities like JWT/custom authorizers, request/response validation and transformation, usage plans, built-in AWS WAF support, and so on.

> Note: All values used in this tutorial are conditional.

Prerequisites
---

You will need:

* The [Terraform CLI](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started) (1.0.1+) installed.
* [An AWS account](https://aws.amazon.com/free/?all-free-tier.sort-by=item.additionalFields.SortRank&all-free-tier.sort-order=asc&awsf.Free%20Tier%20Types=*all&awsf.Free%20Tier%20Categories=*all).
* The [AWS CLI (2.0+)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed, and [configured for your AWS Account](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-config).

Scenario 1
---
#### Simple architecture
![](https://i.imgur.com/lf9D6MH.png)
Let's implement the given scenario:


#### Create and upload Lambda function archive

First, you need to create a directory:
```gherkin=
mkdir aws-lambda-gw && cd aws-lambda-gw
```
Define your provider:

```gherkin=
#provider.tf

provider "aws" {
  region = "us-east-1"
}   
```

#### Python application:
```gherkin=
#app.py

import logging
import base64
import boto3
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')

response  = {
    'statusCode': 200,
    'headers': {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': 'true'
    },
    'body': ''
}

def lambda_handler(event, context):

    file_name = event['headers']['file-name']
    file_content = base64.b64decode(event['body'])
    
    BUCKET_NAME = os.environ['BUCKET_NAME']

    try:
        s3_response = s3_client.put_object(Bucket=BUCKET_NAME, Key=file_name, Body=file_content)   
        logger.info('S3 Response: {}'.format(s3_response))
        response['body'] = 'Hello, your file has been uploaded'

        return response

    except Exception as e:
        raise IOError(e)    
```
The above is the simple Lambda function for use with API Gateway, which uploads your file to S3 bucket and returning a hard-coded "Hello your file has been uploaded!"
#### S3 bucket:

```gherkin=
#S3.tf

resource "aws_s3_bucket" "photo-bucket" {
  bucket        = "${var.name}-bucket-f"
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
```
#### Lambda function:
```gherkin=
#lambda.tf

data "archive_file" "zipit" {
  type        = "zip"
  source_file = "app.py"
  output_path = "tf_lambda.zip"
}

resource "aws_lambda_function" "test_lambda" {
  architectures                  = ["x86_64"]
  filename                       = "tf_lambda.zip"
  function_name                  = "${var.name}-lambda-function"
  role                           = aws_iam_role.iam_for_lambda.arn
  package_type                   = "Zip"
  reserved_concurrent_executions = "-1"
  handler                        = "app.lambda_handler"
  description                    = "Python pplication for uploading images to S3 bucket"
  source_code_hash               = data.archive_file.zipit.output_base64sha256
  runtime                        = "python3.8"
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
```
Each Lambda function must have an associated IAM role which dictates what access it has to other AWS services. The above configuration specifies a ```AWSLambdaBasicExecutionRole``` role and ```AmazonS3FullAccess``` managed policy attached.

#### API Gateway:
```gherkin=
#api-gateway.tf

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
```
Define variables:

```gherkin=
#variables.tf

variable "name" {
  default = "photo"
}
```
Don't forget to add ```.gitignore```:
```gherkin=
#.gitignore

**/.terraform/
.terraform.lock.hcl
*.tfplan
*.tfstate
*.tfstate.*
*.tfvars
*.backup
*.log
*.bak
.history
.DS_Store
crash.log
kubeconfig_*
```
Before you can work with a new configuration directory, it must be initialized using ```terraform init```, which in this case will install the AWS provider:
```gherkin=
terraform init

Initializing the backend...

Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Finding latest version of hashicorp/archive...
- Installing hashicorp/aws v4.11.0...
- Installed hashicorp/aws v4.11.0 (signed by HashiCorp)
- Installing hashicorp/archive v2.2.0...
- Installed hashicorp/archive v2.2.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```
Apply your configuration and respond to the confirmation prompt with a ```yes```:
```gherkin=
terraform apply

...

Plan: 23 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
```

Now, let's review our infrastucture in [AWS Management console](https://aws.amazon.com/console/):

First, check our S3 bucket. Go to [S3 Console](https://s3.console.aws.amazon.com/s3/buckets?region=us-east-1):

![](https://i.imgur.com/9c9g5P6.png)

You can get all the information about the bucket by clicking on it's name

Next, go to [AWS Lambda console](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions) and select created function:

![](https://i.imgur.com/6cEANVl.png)

Finally, to see our API, go to [API Gateway console](https://us-east-1.console.aws.amazon.com/apigateway/main/apis?region=us-east-1) and select it:

![](https://i.imgur.com/BfAmjLP.png)

#### Testing
To test our API or to interact with API we need the endpoint of API, so go to the stages section from the sidebar and get the endpoint of API.

API Endpoint looks like:

```https://xw0n4tuhn9.execute-api.us-west-1.amazonaws.com/test```

I am going to use POSTMAN to test API, you can use any other tool or you can also call the endpoint from your project’s front-end.

In postman, your request would be like API endpoint followed by resource name, in this case, resource name /upload , and method type is POST. In the body part of the request go to a binary section and select any binary file and pass the name of that file in header with file-name field (for front-end you need to pass file-name in header of API endpoint request) and fire a query.

![](https://i.imgur.com/Ne89mu9.png)

---

![](https://i.imgur.com/FAi97Xs.png)

---

![](https://i.imgur.com/eM0NLiL.png)


That’s it, you have configured successfully if you will get 200 Status code. You can go to S3 console and check file will be successfully uploaded:

![](https://i.imgur.com/hl47lSv.png)

Scenario 2
---

#### Architecture diagram

#### What are Lambda Function URLs?

Previously, if you wanted to expose a Lambda with an HTTP endpoint you would normally use the fully managed API Gateway service, this new feature will instead allow you to have an HTTPS URL that is directly connected to your Lambda function, cutting out the API Gateway middleman.
One great feature is the pricing. Lambda Function URLs are completely “free”. You’ll only ever be paying for the invocation and memory time, like a normal Lambda. This is one advantage over API Gateway which costs to integrate.
However, that doesn’t mean they’re a direct replacement for API Gateway. Instead, API Gateway provides more advanced features such as the ability of JWT/custom authorizers, request-response validation and transformation, usage plans, direct built-in AWS firewall support and more.

Let's start by creating a new branch:
```gherkin=
git checkout -b lambda-url aws-lambda-url
```
The name of the branch is optional, you can choose your own.

#### Define new directory:
```gherkin=
mkdir aws-lambda-url && cd aws-lambda-url
```
Copy the ```S3.tf; lambda.tf; .gitignore; variables.tf``` and ```provider.tf``` files from the ```main``` branch.

####  Make changes in ```lambda.tf``` file:

Add the [aws_lambda_function_url](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_url) resource
```gherkin=
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
```

And,
```gherkin=
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
```

#### Create a simple NodeJS application:

```gherkin=
#index.js

exports.handler = async (event) => {
    // TODO implement
    const response = {
        statusCode: 200,
        body: JSON.stringify('Hello from Lambda!'),
    };
    return response;
};
```


You can give an output to ```Function URL```.

```gherkin=
output "aws_lambda_function_url" {
  value = aws_lambda_function_url.test_url.function_url
}
```
Now, it's time to initialize new directory and apply the configuration:

```gherkin=
terraform init



Initializing the backend...

Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Finding latest version of hashicorp/archive...
- Installing hashicorp/aws v4.11.0...
- Installed hashicorp/aws v4.11.0 (signed by HashiCorp)
- Installing hashicorp/archive v2.2.0...
- Installed hashicorp/archive v2.2.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```
And,
```gherkin=
terraform apply

...

Plan: 11 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_lambda_funcion_url = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
```
As you can see, Terraform will apply 11 resources, because we don't use API Gateway. Also it will give an output of Function URL after implementation.

```gherkin=
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

aws_lambda_function_url = "https://7md4ohnwi7alkmzkct3vjmcb5m0jmdim.lambda-url.us-west-1.on.aws/"
```

Also you can access this URL directly from [AWS Lambda console](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions) and open it in your browser.

#### Test the function via [Postman](https://www.postman.com/) as in the first scenario:

![](https://i.imgur.com/QlDQEVX.png)

We allow all the methos in our ```aws_lambda_function_url``` resource, so you can choose any of available and test it.

Consclusion
===
In this guide you created an AWS Lambda function that produces a result compatible with Amazon API Gateway proxy resources and tested new [Lambda Function URL](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html).
Although the AWS Lambda function used in this guide is very simple. You can try out your own scenarios.
#### Cleaning Up
Once you are finished with this guide, you can destroy the example objects with Terraform.
```gherkin=
terraform destroy
```
Since the artifact zip files were created outside of Terraform, they must also be cleaned up outside of Terraform.

###### tags: `AWS Lambda` `Documentation` `Api Gateway` `Terraform` `S3` `Lambda Function URL`
