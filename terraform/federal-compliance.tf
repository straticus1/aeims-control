# Federal Compliance for AEIMS - 18 USC 2257 and Content Moderation
# Implements comprehensive content moderation, age verification, and regulatory compliance

# Content Moderation S3 Bucket
resource "aws_s3_bucket" "content_moderation" {
  bucket = "${var.project_name}-content-moderation-${var.environment}-${random_id.moderation_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-content-moderation-${var.environment}"
    Purpose   = "FederalCompliance"
    DataClass = "ContentModeration"
    Retention = "7years"
  }
}

resource "random_id" "moderation_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "moderation_versioning" {
  bucket = aws_s3_bucket.content_moderation.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "moderation_encryption" {
  bucket = aws_s3_bucket.content_moderation.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.federal_compliance_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Federal Compliance KMS Key
resource "aws_kms_key" "federal_compliance_key" {
  description             = "KMS key for Federal compliance data encryption"
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
        Sid    = "Allow Federal Compliance Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "rekognition.amazonaws.com",
            "textract.amazonaws.com",
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
    Name = "${var.project_name}-federal-compliance-key-${var.environment}"
  }
}

resource "aws_kms_alias" "federal_compliance_key_alias" {
  name          = "alias/${var.project_name}-federal-compliance-key-${var.environment}"
  target_key_id = aws_kms_key.federal_compliance_key.key_id
}

# Content Moderation Lambda
resource "aws_lambda_function" "content_moderator" {
  function_name = "${var.project_name}-content-moderator-${var.environment}"
  role          = aws_iam_role.content_moderator_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.content_moderator_zip.output_path
  source_code_hash = data.archive_file.content_moderator_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.content_moderator_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      MODERATION_BUCKET  = aws_s3_bucket.content_moderation.bucket
      COMPLIANCE_KMS_KEY = aws_kms_key.federal_compliance_key.arn
      REKOGNITION_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-content-moderator-${var.environment}"
  }
}

data "archive_file" "content_moderator_zip" {
  type        = "zip"
  output_path = "/tmp/content_moderator.zip"
  source {
    content = templatefile("${path.module}/lambda/content_moderator.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Age Verification Lambda
resource "aws_lambda_function" "age_verifier" {
  function_name = "${var.project_name}-age-verifier-${var.environment}"
  role          = aws_iam_role.age_verifier_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.age_verifier_zip.output_path
  source_code_hash = data.archive_file.age_verifier_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.age_verifier_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      COMPLIANCE_BUCKET  = aws_s3_bucket.content_moderation.bucket
      COMPLIANCE_KMS_KEY = aws_kms_key.federal_compliance_key.arn
    }
  }

  tags = {
    Name = "${var.project_name}-age-verifier-${var.environment}"
  }
}

data "archive_file" "age_verifier_zip" {
  type        = "zip"
  output_path = "/tmp/age_verifier.zip"
  source {
    content = templatefile("${path.module}/lambda/age_verifier.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Record Keeping Lambda for 18 USC 2257
resource "aws_lambda_function" "record_keeper" {
  function_name = "${var.project_name}-record-keeper-${var.environment}"
  role          = aws_iam_role.record_keeper_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.record_keeper_zip.output_path
  source_code_hash = data.archive_file.record_keeper_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.record_keeper_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      RECORDS_BUCKET     = aws_s3_bucket.content_moderation.bucket
      COMPLIANCE_KMS_KEY = aws_kms_key.federal_compliance_key.arn
    }
  }

  tags = {
    Name = "${var.project_name}-record-keeper-${var.environment}"
  }
}

data "archive_file" "record_keeper_zip" {
  type        = "zip"
  output_path = "/tmp/record_keeper.zip"
  source {
    content = templatefile("${path.module}/lambda/record_keeper.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# IAM Roles and Policies

# Content Moderator Role
resource "aws_iam_role" "content_moderator_role" {
  name = "${var.project_name}-content-moderator-role-${var.environment}"

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

resource "aws_iam_role_policy" "content_moderator_policy" {
  name = "${var.project_name}-content-moderator-policy-${var.environment}"
  role = aws_iam_role.content_moderator_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectModerationLabels",
          "rekognition:DetectText",
          "rekognition:DetectFaces",
          "rekognition:RecognizeCelebrities",
          "rekognition:DetectLabels"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.content_moderation.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.content_moderation.arn,
          aws_s3_bucket.aeims_assets.arn
        ]
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
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.federal_compliance_key.arn,
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

resource "aws_iam_role_policy_attachment" "content_moderator_vpc_access" {
  role       = aws_iam_role.content_moderator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Age Verifier Role
resource "aws_iam_role" "age_verifier_role" {
  name = "${var.project_name}-age-verifier-role-${var.environment}"

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

resource "aws_iam_role_policy" "age_verifier_policy" {
  name = "${var.project_name}-age-verifier-policy-${var.environment}"
  role = aws_iam_role.age_verifier_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument",
          "textract:AnalyzeID"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:CompareFaces",
          "rekognition:DetectFaces"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.content_moderation.arn}/*"
        ]
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
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.federal_compliance_key.arn
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

resource "aws_iam_role_policy_attachment" "age_verifier_vpc_access" {
  role       = aws_iam_role.age_verifier_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Record Keeper Role
resource "aws_iam_role" "record_keeper_role" {
  name = "${var.project_name}-record-keeper-role-${var.environment}"

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

resource "aws_iam_role_policy" "record_keeper_policy" {
  name = "${var.project_name}-record-keeper-policy-${var.environment}"
  role = aws_iam_role.record_keeper_role.id

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
          aws_s3_bucket.content_moderation.arn,
          "${aws_s3_bucket.content_moderation.arn}/*"
        ]
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
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.federal_compliance_key.arn
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

resource "aws_iam_role_policy_attachment" "record_keeper_vpc_access" {
  role       = aws_iam_role.record_keeper_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Groups
resource "aws_security_group" "content_moderator_sg" {
  name_prefix = "${var.project_name}-content-moderator-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "${var.project_name}-content-moderator-sg-${var.environment}"
  }
}

resource "aws_security_group" "age_verifier_sg" {
  name_prefix = "${var.project_name}-age-verifier-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "${var.project_name}-age-verifier-sg-${var.environment}"
  }
}

resource "aws_security_group" "record_keeper_sg" {
  name_prefix = "${var.project_name}-record-keeper-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "${var.project_name}-record-keeper-sg-${var.environment}"
  }
}

# DynamoDB Table for Compliance Records
resource "aws_dynamodb_table" "compliance_records" {
  name         = "${var.project_name}-compliance-records-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "record_id"
  range_key    = "record_type"

  attribute {
    name = "record_id"
    type = "S"
  }

  attribute {
    name = "record_type"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "user-index"
    hash_key  = "user_id"
    range_key = "timestamp"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "type-timestamp-index"
    hash_key  = "record_type"
    range_key = "timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.federal_compliance_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-compliance-records-${var.environment}"
  }
}

# EventBridge Rules for Content Processing
resource "aws_cloudwatch_event_rule" "content_upload_rule" {
  name        = "${var.project_name}-content-upload-${var.environment}"
  description = "Trigger content moderation on upload"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.aeims_assets.bucket]
      }
    }
  })

  tags = {
    Name = "${var.project_name}-content-upload-rule-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "content_moderation_target" {
  rule      = aws_cloudwatch_event_rule.content_upload_rule.name
  target_id = "ContentModerationTarget"
  arn       = aws_lambda_function.content_moderator.arn
}

resource "aws_lambda_permission" "allow_eventbridge_content_moderation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.content_moderator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.content_upload_rule.arn
}

# Schedule for compliance audits
resource "aws_cloudwatch_event_rule" "compliance_audit_schedule" {
  name                = "${var.project_name}-compliance-audit-${var.environment}"
  description         = "Scheduled compliance audit"
  schedule_expression = "cron(0 1 * * ? *)" # Daily at 1 AM

  tags = {
    Name = "${var.project_name}-compliance-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "compliance_audit_target" {
  rule      = aws_cloudwatch_event_rule.compliance_audit_schedule.name
  target_id = "ComplianceAuditTarget"
  arn       = aws_lambda_function.record_keeper.arn

  input = jsonencode({
    action = "audit_compliance"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_compliance_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.record_keeper.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.compliance_audit_schedule.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "federal_compliance_logs" {
  for_each = toset([
    "content-moderator",
    "age-verifier",
    "record-keeper"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2557 # 7 years for compliance
  kms_key_id        = aws_kms_key.federal_compliance_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "content_moderation_failures" {
  alarm_name          = "${var.project_name}-content-moderation-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Content moderation failures"

  dimensions = {
    FunctionName = aws_lambda_function.content_moderator.function_name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-content-moderation-alarm-${var.environment}"
  }
}

# Variables for Federal Compliance
variable "age_verification_required" {
  description = "Require age verification for content creation"
  type        = bool
  default     = true
}

variable "content_moderation_threshold" {
  description = "Confidence threshold for content moderation (0-100)"
  type        = number
  default     = 80
}

variable "record_keeping_retention_years" {
  description = "Record keeping retention period in years"
  type        = number
  default     = 7
}

# Outputs
output "content_moderation_bucket" {
  description = "S3 bucket for content moderation"
  value       = aws_s3_bucket.content_moderation.bucket
}

output "content_moderator_arn" {
  description = "Content moderator Lambda function ARN"
  value       = aws_lambda_function.content_moderator.arn
}

output "age_verifier_arn" {
  description = "Age verifier Lambda function ARN"
  value       = aws_lambda_function.age_verifier.arn
}

output "compliance_records_table" {
  description = "DynamoDB table for compliance records"
  value       = aws_dynamodb_table.compliance_records.name
}

output "federal_compliance_kms_key_arn" {
  description = "KMS key ARN for Federal compliance encryption"
  value       = aws_kms_key.federal_compliance_key.arn
}
