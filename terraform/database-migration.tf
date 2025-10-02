# Database Migration Automation for AEIMS
# Handles database schema migrations and data migrations

# Lambda function for database migrations
resource "aws_lambda_function" "db_migration" {
  function_name = "${var.project_name}-db-migration-${var.environment}"
  role          = aws_iam_role.db_migration_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900 # 15 minutes

  filename         = data.archive_file.db_migration_zip.output_path
  source_code_hash = data.archive_file.db_migration_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.db_migration_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.db_migration_vpc_access,
    aws_cloudwatch_log_group.db_migration_logs
  ]

  tags = {
    Name = "${var.project_name}-db-migration-${var.environment}"
  }
}

# Lambda deployment package
data "archive_file" "db_migration_zip" {
  type        = "zip"
  output_path = "/tmp/db_migration.zip"
  source {
    content = templatefile("${path.module}/lambda/db_migration.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
  source {
    content  = file("${path.module}/lambda/requirements.txt")
    filename = "requirements.txt"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "db_migration_role" {
  name = "${var.project_name}-db-migration-role-${var.environment}"

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

# Lambda VPC access policy
resource "aws_iam_role_policy_attachment" "db_migration_vpc_access" {
  role       = aws_iam_role.db_migration_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for database access
resource "aws_iam_role_policy" "db_migration_policy" {
  name = "${var.project_name}-db-migration-policy-${var.environment}"
  role = aws_iam_role.db_migration_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          for secret in values(aws_secretsmanager_secret.database_secrets) : secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.db_migration_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.db_migration_bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security group for Lambda
resource "aws_security_group" "db_migration_sg" {
  name_prefix = "${var.project_name}-db-migration-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_db_sg.id]
  }

  egress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_db_sg.id]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-migration-sg-${var.environment}"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "db_migration_logs" {
  name              = "/aws/lambda/${var.project_name}-db-migration-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-db-migration-logs-${var.environment}"
  }
}

# S3 bucket for migration scripts and backups
resource "aws_s3_bucket" "db_migration_bucket" {
  bucket = "${var.project_name}-db-migrations-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-db-migrations-${var.environment}"
  }
}

resource "aws_s3_bucket_versioning" "db_migration_versioning" {
  bucket = aws_s3_bucket.db_migration_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "db_migration_encryption" {
  bucket = aws_s3_bucket.db_migration_bucket.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.aeims_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Step Functions for migration workflow
resource "aws_sfn_state_machine" "db_migration_workflow" {
  name     = "${var.project_name}-db-migration-workflow-${var.environment}"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Database migration workflow for AEIMS"
    StartAt = "PreMigrationBackup"
    States = {
      PreMigrationBackup = {
        Type     = "Task"
        Resource = aws_lambda_function.db_migration.arn
        Parameters = {
          action    = "backup"
          timestamp = "$$.Execution.StartTime"
        }
        Next = "RunMigrations"
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
            Next        = "MigrationFailed"
          }
        ]
      }
      RunMigrations = {
        Type     = "Task"
        Resource = aws_lambda_function.db_migration.arn
        Parameters = {
          action    = "migrate"
          timestamp = "$$.Execution.StartTime"
        }
        Next = "ValidateMigration"
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
            Next        = "RollbackMigration"
          }
        ]
      }
      ValidateMigration = {
        Type     = "Task"
        Resource = aws_lambda_function.db_migration.arn
        Parameters = {
          action    = "validate"
          timestamp = "$$.Execution.StartTime"
        }
        Next = "MigrationSuccess"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RollbackMigration"
          }
        ]
      }
      RollbackMigration = {
        Type     = "Task"
        Resource = aws_lambda_function.db_migration.arn
        Parameters = {
          action    = "rollback"
          timestamp = "$$.Execution.StartTime"
        }
        Next = "MigrationFailed"
      }
      MigrationSuccess = {
        Type = "Succeed"
      }
      MigrationFailed = {
        Type  = "Fail"
        Cause = "Migration workflow failed"
      }
    }
  })

  tags = {
    Name = "${var.project_name}-db-migration-workflow-${var.environment}"
  }
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-step-functions-role-${var.environment}"

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

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-step-functions-policy-${var.environment}"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.db_migration.arn
        ]
      }
    ]
  })
}

# EventBridge rule for scheduled migrations
resource "aws_cloudwatch_event_rule" "db_migration_schedule" {
  count = var.enable_scheduled_migrations ? 1 : 0

  name                = "${var.project_name}-db-migration-schedule-${var.environment}"
  description         = "Trigger database migrations on schedule"
  schedule_expression = var.migration_schedule

  tags = {
    Name = "${var.project_name}-db-migration-schedule-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "db_migration_target" {
  count = var.enable_scheduled_migrations ? 1 : 0

  rule      = aws_cloudwatch_event_rule.db_migration_schedule[0].name
  target_id = "DbMigrationTarget"
  arn       = aws_sfn_state_machine.db_migration_workflow.arn
  role_arn  = aws_iam_role.eventbridge_role[0].arn

  input = jsonencode({
    source    = "eventbridge"
    scheduled = true
  })
}

# IAM role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  count = var.enable_scheduled_migrations ? 1 : 0

  name = "${var.project_name}-eventbridge-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  count = var.enable_scheduled_migrations ? 1 : 0

  name = "${var.project_name}-eventbridge-policy-${var.environment}"
  role = aws_iam_role.eventbridge_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# CloudWatch alarms for migration monitoring
resource "aws_cloudwatch_metric_alarm" "migration_failures" {
  alarm_name          = "${var.project_name}-migration-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors failed database migrations"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.db_migration_workflow.arn
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-migration-alarm-${var.environment}"
  }
}

# Variables
variable "enable_scheduled_migrations" {
  description = "Enable scheduled database migrations"
  type        = bool
  default     = false
}

variable "migration_schedule" {
  description = "Cron expression for migration schedule"
  type        = string
  default     = "cron(0 2 * * SUN *)" # Weekly on Sunday at 2 AM
}

# Outputs
output "migration_lambda_arn" {
  description = "Database migration Lambda function ARN"
  value       = aws_lambda_function.db_migration.arn
}

output "migration_workflow_arn" {
  description = "Database migration workflow ARN"
  value       = aws_sfn_state_machine.db_migration_workflow.arn
}

output "migration_bucket_name" {
  description = "S3 bucket for migration scripts"
  value       = aws_s3_bucket.db_migration_bucket.bucket
}