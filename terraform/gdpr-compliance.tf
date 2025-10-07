# GDPR Compliance and Audit Logging for AEIMS
# Implements comprehensive data protection, audit trails, and compliance monitoring

# Audit Trail S3 Bucket
resource "aws_s3_bucket" "audit_logs" {
  bucket = "${var.project_name}-audit-logs-${var.environment}-${random_id.audit_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-audit-logs-${var.environment}"
    Purpose   = "GDPR Compliance"
    DataClass = "Audit"
    Retention = "7years"
  }
}

resource "random_id" "audit_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "audit_versioning" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_encryption" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.gdpr_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_lifecycle" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    id     = "audit_log_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    transition {
      days          = 2555 # 7 years
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2922 # 8 years (7 years + 1 year buffer)
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# GDPR-specific KMS Key
resource "aws_kms_key" "gdpr_key" {
  description             = "KMS key for GDPR compliance data encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow GDPR Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "cloudtrail.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-gdpr-key-${var.environment}"
  }
}

resource "aws_kms_alias" "gdpr_key_alias" {
  name          = "alias/${var.project_name}-gdpr-key-${var.environment}"
  target_key_id = aws_kms_key.gdpr_key.key_id
}

# CloudTrail for comprehensive audit logging
resource "aws_cloudtrail" "gdpr_audit_trail" {
  name           = "${var.project_name}-gdpr-audit-trail-${var.environment}"
  s3_bucket_name = aws_s3_bucket.audit_logs.bucket

  event_selector {
    read_write_type                  = "All"
    include_management_events        = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.aeims_assets.arn}/*"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  kms_key_id                    = aws_kms_key.gdpr_key.arn
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = {
    Name = "${var.project_name}-gdpr-audit-trail-${var.environment}"
  }
}

# Data Subject Access Request Lambda
resource "aws_lambda_function" "dsar_processor" {
  function_name = "${var.project_name}-dsar-processor-${var.environment}"
  role          = aws_iam_role.dsar_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900

  filename         = data.archive_file.dsar_zip.output_path
  source_code_hash = data.archive_file.dsar_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.dsar_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
      AUDIT_BUCKET = aws_s3_bucket.audit_logs.bucket
      GDPR_KMS_KEY = aws_kms_key.gdpr_key.arn
    }
  }

  tags = {
    Name = "${var.project_name}-dsar-processor-${var.environment}"
  }
}

data "archive_file" "dsar_zip" {
  type        = "zip"
  output_path = "/tmp/dsar_processor.zip"
  source {
    content = templatefile("${path.module}/lambda/dsar_processor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# IAM role for DSAR Lambda
resource "aws_iam_role" "dsar_role" {
  name = "${var.project_name}-dsar-role-${var.environment}"

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

resource "aws_iam_role_policy" "dsar_policy" {
  name = "${var.project_name}-dsar-policy-${var.environment}"
  role = aws_iam_role.dsar_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
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
          "${aws_s3_bucket.audit_logs.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.gdpr_key.arn,
          aws_kms_key.aeims_key.arn
        ]
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

resource "aws_iam_role_policy_attachment" "dsar_vpc_access" {
  role       = aws_iam_role.dsar_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security group for DSAR Lambda
resource "aws_security_group" "dsar_sg" {
  name_prefix = "${var.project_name}-dsar-sg-"
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
    Name = "${var.project_name}-dsar-sg-${var.environment}"
  }
}

# Data Retention Policy Lambda
resource "aws_lambda_function" "data_retention" {
  function_name = "${var.project_name}-data-retention-${var.environment}"
  role          = aws_iam_role.data_retention_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900

  filename         = data.archive_file.data_retention_zip.output_path
  source_code_hash = data.archive_file.data_retention_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.data_retention_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
      AUDIT_BUCKET = aws_s3_bucket.audit_logs.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-data-retention-${var.environment}"
  }
}

data "archive_file" "data_retention_zip" {
  type        = "zip"
  output_path = "/tmp/data_retention.zip"
  source {
    content = templatefile("${path.module}/lambda/data_retention.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# IAM role for data retention Lambda
resource "aws_iam_role" "data_retention_role" {
  name = "${var.project_name}-data-retention-role-${var.environment}"

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

resource "aws_iam_role_policy" "data_retention_policy" {
  name = "${var.project_name}-data-retention-policy-${var.environment}"
  role = aws_iam_role.data_retention_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
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
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.audit_logs.arn,
          "${aws_s3_bucket.audit_logs.arn}/*",
          aws_s3_bucket.aeims_assets.arn,
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
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

resource "aws_iam_role_policy_attachment" "data_retention_vpc_access" {
  role       = aws_iam_role.data_retention_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security group for data retention Lambda
resource "aws_security_group" "data_retention_sg" {
  name_prefix = "${var.project_name}-data-retention-sg-"
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
    Name = "${var.project_name}-data-retention-sg-${var.environment}"
  }
}

# EventBridge rules for scheduled GDPR tasks
resource "aws_cloudwatch_event_rule" "dsar_schedule" {
  name                = "${var.project_name}-dsar-schedule-${var.environment}"
  description         = "Process pending DSAR requests"
  schedule_expression = "rate(1 hour)"

  tags = {
    Name = "${var.project_name}-dsar-schedule-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "dsar_target" {
  rule      = aws_cloudwatch_event_rule.dsar_schedule.name
  target_id = "DSARTarget"
  arn       = aws_lambda_function.dsar_processor.arn
}

resource "aws_lambda_permission" "allow_eventbridge_dsar" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dsar_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dsar_schedule.arn
}

resource "aws_cloudwatch_event_rule" "data_retention_schedule" {
  name                = "${var.project_name}-data-retention-schedule-${var.environment}"
  description         = "Automated data retention cleanup"
  schedule_expression = "cron(0 2 * * ? *)" # Daily at 2 AM

  tags = {
    Name = "${var.project_name}-data-retention-schedule-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "data_retention_target" {
  rule      = aws_cloudwatch_event_rule.data_retention_schedule.name
  target_id = "DataRetentionTarget"
  arn       = aws_lambda_function.data_retention.arn
}

resource "aws_lambda_permission" "allow_eventbridge_retention" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_retention.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_retention_schedule.arn
}

# Consent Management DynamoDB Table
resource "aws_dynamodb_table" "consent_management" {
  name         = "${var.project_name}-consent-management-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "consent_type"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "consent_type"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "timestamp-index"
    hash_key  = "consent_type"
    range_key = "timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.gdpr_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-consent-management-${var.environment}"
  }
}

# CloudWatch Log Groups with encryption
resource "aws_cloudwatch_log_group" "gdpr_logs" {
  for_each = toset([
    "dsar-processor",
    "data-retention",
    "consent-management"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2557 # 7 years
  kms_key_id        = aws_kms_key.gdpr_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Metrics and Alarms
resource "aws_cloudwatch_metric_alarm" "dsar_processing_failures" {
  alarm_name          = "${var.project_name}-dsar-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors DSAR processing failures"

  dimensions = {
    FunctionName = aws_lambda_function.dsar_processor.function_name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-dsar-alarm-${var.environment}"
  }
}

# Variables for GDPR configuration
variable "gdpr_retention_days" {
  description = "Default data retention period in days"
  type        = number
  default     = 2555 # 7 years
}

variable "dsar_processing_sla_hours" {
  description = "SLA for DSAR processing in hours"
  type        = number
  default     = 720 # 30 days
}

# Outputs
output "audit_bucket_name" {
  description = "S3 bucket for audit logs"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "dsar_processor_arn" {
  description = "DSAR processor Lambda function ARN"
  value       = aws_lambda_function.dsar_processor.arn
}

output "consent_table_name" {
  description = "DynamoDB table for consent management"
  value       = aws_dynamodb_table.consent_management.name
}

output "gdpr_kms_key_arn" {
  description = "KMS key ARN for GDPR encryption"
  value       = aws_kms_key.gdpr_key.arn
}
