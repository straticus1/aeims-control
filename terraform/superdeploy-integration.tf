# SuperDeploy Integration for AEIMS Ecosystem
# Provides unified deployment orchestration for aeims, aeims.app, aeimsLib, and aeims-control

locals {
  step_functions_arn_placeholder = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-superdeploy-workflow-${var.environment}"
}

# SuperDeploy API Gateway
resource "aws_api_gateway_rest_api" "superdeploy_api" {
  name        = "${var.project_name}-superdeploy-api-${var.environment}"
  description = "SuperDeploy API for AEIMS ecosystem orchestration"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-superdeploy-api-${var.environment}"
  }
}

# SuperDeploy Orchestrator Lambda
resource "aws_lambda_function" "superdeploy_orchestrator" {
  function_name = "${var.project_name}-superdeploy-orchestrator-${var.environment}"
  role          = aws_iam_role.superdeploy_orchestrator_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.superdeploy_orchestrator_zip.output_path
  source_code_hash = data.archive_file.superdeploy_orchestrator_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.superdeploy_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      ECS_CLUSTER_NAME   = aws_ecs_cluster.aeims_cluster.name
      STEP_FUNCTIONS_ARN = local.step_functions_arn_placeholder
      NOTIFICATION_TOPIC = aws_sns_topic.deployment_notifications.arn
      DEPLOYMENT_BUCKET  = aws_s3_bucket.deployment_artifacts.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-superdeploy-orchestrator-${var.environment}"
  }

  depends_on = [
    aws_ecs_cluster.aeims_cluster,
    aws_sns_topic.deployment_notifications,
    aws_s3_bucket.deployment_artifacts
  ]
}

data "archive_file" "superdeploy_orchestrator_zip" {
  type        = "zip"
  output_path = "/tmp/superdeploy_orchestrator.zip"
  source {
    content = templatefile("${path.module}/lambda/superdeploy_orchestrator.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Deployment Artifacts S3 Bucket
resource "aws_s3_bucket" "deployment_artifacts" {
  bucket = "${var.project_name}-deployment-artifacts-${var.environment}-${random_id.deployment_bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-deployment-artifacts-${var.environment}"
  }
}

resource "random_id" "deployment_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "deployment_artifacts_versioning" {
  bucket = aws_s3_bucket.deployment_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "deployment_artifacts_encryption" {
  bucket = aws_s3_bucket.deployment_artifacts.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.aeims_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Step Functions State Machine for Deployment Workflow
resource "aws_sfn_state_machine" "superdeploy_workflow" {
  name     = "${var.project_name}-superdeploy-workflow-${var.environment}"
  role_arn = aws_iam_role.superdeploy_step_functions_role.arn

  definition = jsonencode({
    Comment = "SuperDeploy workflow for AEIMS ecosystem"
    StartAt = "ValidateDeployment"
    States = {
      ValidateDeployment = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "validate"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "PrepareInfrastructure"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "DeploymentFailed"
          }
        ]
      }
      PrepareInfrastructure = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "prepare_infrastructure"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "RunDatabaseMigrations"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackInfrastructure"
          }
        ]
      }
      RunDatabaseMigrations = {
        Type     = "Task"
        Resource = aws_sfn_state_machine.db_migration_workflow.arn
        Next     = "DeployServices"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackMigrations"
          }
        ]
      }
      DeployServices = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "DeployAeimsCore"
            States = {
              DeployAeimsCore = {
                Type     = "Task"
                Resource = aws_lambda_function.superdeploy_orchestrator.arn
                Parameters = {
                  action                = "deploy_service"
                  service               = "aeims-core"
                  "deployment_config.$" = "$.deployment_config"
                }
                End = true
              }
            }
          },
          {
            StartAt = "DeployAeimsApp"
            States = {
              DeployAeimsApp = {
                Type     = "Task"
                Resource = aws_lambda_function.superdeploy_orchestrator.arn
                Parameters = {
                  action                = "deploy_service"
                  service               = "aeims-app"
                  "deployment_config.$" = "$.deployment_config"
                }
                End = true
              }
            }
          },
          {
            StartAt = "DeployAeimsLib"
            States = {
              DeployAeimsLib = {
                Type     = "Task"
                Resource = aws_lambda_function.superdeploy_orchestrator.arn
                Parameters = {
                  action                = "deploy_service"
                  service               = "aeims-lib"
                  "deployment_config.$" = "$.deployment_config"
                }
                End = true
              }
            }
          }
        ]
        Next = "ValidateDeployment"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackServices"
          }
        ]
      }
      ValidateServices = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "validate_services"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "UpdateLoadBalancer"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackServices"
          }
        ]
      }
      UpdateLoadBalancer = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "update_load_balancer"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "RunSmokeTests"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackLoadBalancer"
          }
        ]
      }
      RunSmokeTests = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "run_smoke_tests"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "DeploymentSuccess"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackAll"
          }
        ]
      }
      RollbackInfrastructure = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "rollback_infrastructure"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "DeploymentFailed"
      }
      RollbackMigrations = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "rollback_migrations"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "RollbackInfrastructure"
      }
      RollbackServices = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "rollback_services"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "RollbackMigrations"
      }
      RollbackLoadBalancer = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "rollback_load_balancer"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "RollbackServices"
      }
      RollbackAll = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "rollback_all"
          "deployment_config.$" = "$.deployment_config"
        }
        Next = "DeploymentFailed"
      }
      DeploymentSuccess = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "deployment_success"
          "deployment_config.$" = "$.deployment_config"
        }
        End = true
      }
      DeploymentFailed = {
        Type     = "Task"
        Resource = aws_lambda_function.superdeploy_orchestrator.arn
        Parameters = {
          action                = "deployment_failed"
          "deployment_config.$" = "$.deployment_config"
        }
        End = true
      }
    }
  })

  tags = {
    Name = "${var.project_name}-superdeploy-workflow-${var.environment}"
  }
}

# SNS Topic for Deployment Notifications
resource "aws_sns_topic" "deployment_notifications" {
  name = "${var.project_name}-deployment-notifications-${var.environment}"

  tags = {
    Name = "${var.project_name}-deployment-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "deployment_email_notification" {
  count = var.deployment_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.deployment_notifications.arn
  protocol  = "email"
  endpoint  = var.deployment_notification_email
}

# API Gateway Resources and Methods
resource "aws_api_gateway_resource" "superdeploy_deploy" {
  rest_api_id = aws_api_gateway_rest_api.superdeploy_api.id
  parent_id   = aws_api_gateway_rest_api.superdeploy_api.root_resource_id
  path_part   = "deploy"
}

resource "aws_api_gateway_method" "superdeploy_deploy_post" {
  rest_api_id   = aws_api_gateway_rest_api.superdeploy_api.id
  resource_id   = aws_api_gateway_resource.superdeploy_deploy.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "superdeploy_deploy_integration" {
  rest_api_id = aws_api_gateway_rest_api.superdeploy_api.id
  resource_id = aws_api_gateway_resource.superdeploy_deploy.id
  http_method = aws_api_gateway_method.superdeploy_deploy_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.superdeploy_orchestrator.invoke_arn
}

resource "aws_api_gateway_resource" "superdeploy_status" {
  rest_api_id = aws_api_gateway_rest_api.superdeploy_api.id
  parent_id   = aws_api_gateway_rest_api.superdeploy_api.root_resource_id
  path_part   = "status"
}

resource "aws_api_gateway_method" "superdeploy_status_get" {
  rest_api_id   = aws_api_gateway_rest_api.superdeploy_api.id
  resource_id   = aws_api_gateway_resource.superdeploy_status.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "superdeploy_status_integration" {
  rest_api_id = aws_api_gateway_rest_api.superdeploy_api.id
  resource_id = aws_api_gateway_resource.superdeploy_status.id
  http_method = aws_api_gateway_method.superdeploy_status_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.superdeploy_orchestrator.invoke_arn
}

resource "aws_api_gateway_deployment" "superdeploy_deployment" {
  depends_on = [
    aws_api_gateway_integration.superdeploy_deploy_integration,
    aws_api_gateway_integration.superdeploy_status_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.superdeploy_api.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "allow_api_gateway_superdeploy" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.superdeploy_orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.superdeploy_api.execution_arn}/*/*"
}

# IAM Roles

# SuperDeploy Orchestrator Role
resource "aws_iam_role" "superdeploy_orchestrator_role" {
  name = "${var.project_name}-superdeploy-orchestrator-role-${var.environment}"

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

resource "aws_iam_role_policy" "superdeploy_orchestrator_policy" {
  name = "${var.project_name}-superdeploy-orchestrator-policy-${var.environment}"
  role = aws_iam_role.superdeploy_orchestrator_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:ListTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elbv2:DescribeTargetGroups",
          "elbv2:DescribeTargetHealth",
          "elbv2:RegisterTargets",
          "elbv2:DeregisterTargets",
          "elbv2:ModifyTargetGroup",
          "elbv2:DescribeLoadBalancers"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deployment_artifacts.arn,
          "${aws_s3_bucket.deployment_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution",
          "states:DescribeExecution",
          "states:StopExecution"
        ]
        Resource = [
          aws_sfn_state_machine.superdeploy_workflow.arn,
          aws_sfn_state_machine.db_migration_workflow.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.deployment_notifications.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackResources",
          "cloudformation:DescribeStackEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "superdeploy_orchestrator_vpc_access" {
  role       = aws_iam_role.superdeploy_orchestrator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Step Functions Role
resource "aws_iam_role" "superdeploy_step_functions_role" {
  name = "${var.project_name}-superdeploy-step-functions-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "superdeploy_step_functions_policy" {
  name = "${var.project_name}-superdeploy-step-functions-policy-${var.environment}"
  role = aws_iam_role.superdeploy_step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.superdeploy_orchestrator.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = [
          aws_sfn_state_machine.db_migration_workflow.arn
        ]
      }
    ]
  })
}

# Security Group
resource "aws_security_group" "superdeploy_sg" {
  name_prefix = "${var.project_name}-superdeploy-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-superdeploy-sg-${var.environment}"
  }
}

# DynamoDB Table for Deployment State
resource "aws_dynamodb_table" "deployment_state" {
  name         = "${var.project_name}-deployment-state-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "deployment_id"

  attribute {
    name = "deployment_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name      = "status-timestamp-index"
    hash_key  = "status"
    range_key = "timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.aeims_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-deployment-state-${var.environment}"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "superdeploy_logs" {
  name              = "/aws/lambda/${var.project_name}-superdeploy-orchestrator-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-superdeploy-logs-${var.environment}"
  }
}

# Variables
variable "deployment_notification_email" {
  description = "Email address for deployment notifications"
  type        = string
  default     = ""
}

variable "enable_blue_green_deployment" {
  description = "Enable blue-green deployment strategy"
  type        = bool
  default     = true
}

variable "enable_canary_deployment" {
  description = "Enable canary deployment strategy"
  type        = bool
  default     = false
}

variable "deployment_timeout_minutes" {
  description = "Deployment timeout in minutes"
  type        = number
  default     = 30
}

# Outputs
output "superdeploy_api_url" {
  description = "SuperDeploy API Gateway URL"
  value       = "https://${aws_api_gateway_rest_api.superdeploy_api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

output "superdeploy_orchestrator_arn" {
  description = "SuperDeploy orchestrator Lambda function ARN"
  value       = aws_lambda_function.superdeploy_orchestrator.arn
}

output "superdeploy_workflow_arn" {
  description = "SuperDeploy workflow state machine ARN"
  value       = aws_sfn_state_machine.superdeploy_workflow.arn
}

output "deployment_artifacts_bucket" {
  description = "Deployment artifacts S3 bucket"
  value       = aws_s3_bucket.deployment_artifacts.bucket
}

output "deployment_state_table" {
  description = "Deployment state DynamoDB table"
  value       = aws_dynamodb_table.deployment_state.name
}