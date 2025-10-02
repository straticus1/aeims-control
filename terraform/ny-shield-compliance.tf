# NY SHIELD Act Compliance for AEIMS
# Implements data breach notification, security requirements, and privacy protections

# Data Breach Response S3 Bucket
resource "aws_s3_bucket" "breach_response" {
  bucket = "${var.project_name}-breach-response-${var.environment}-${random_id.breach_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-breach-response-${var.environment}"
    Purpose   = "NYSHIELDCompliance"
    DataClass = "BreachResponse"
    Retention = "indefinite"
  }
}

resource "random_id" "breach_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "breach_response_versioning" {
  bucket = aws_s3_bucket.breach_response.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "breach_response_encryption" {
  bucket = aws_s3_bucket.breach_response.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.ny_shield_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# NY SHIELD Act specific KMS Key
resource "aws_kms_key" "ny_shield_key" {
  description             = "KMS key for NY SHIELD Act compliance"
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
        Sid    = "Allow NY SHIELD Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "sns.amazonaws.com",
            "ses.amazonaws.com"
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
    Name = "${var.project_name}-ny-shield-key-${var.environment}"
  }
}

resource "aws_kms_alias" "ny_shield_key_alias" {
  name          = "alias/${var.project_name}-ny-shield-key-${var.environment}"
  target_key_id = aws_kms_key.ny_shield_key.key_id
}

# Breach Detection Lambda
resource "aws_lambda_function" "breach_detector" {
  function_name = "${var.project_name}-breach-detector-${var.environment}"
  role          = aws_iam_role.breach_detector_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.breach_detector_zip.output_path
  source_code_hash = data.archive_file.breach_detector_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.breach_detector_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      BREACH_BUCKET      = aws_s3_bucket.breach_response.bucket
      NY_SHIELD_KMS_KEY  = aws_kms_key.ny_shield_key.arn
      NOTIFICATION_TOPIC = aws_sns_topic.breach_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-breach-detector-${var.environment}"
  }
}

data "archive_file" "breach_detector_zip" {
  type        = "zip"
  output_path = "/tmp/breach_detector.zip"
  source {
    content = templatefile("${path.module}/lambda/breach_detector.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Privacy Rights Lambda
resource "aws_lambda_function" "privacy_rights" {
  function_name = "${var.project_name}-privacy-rights-${var.environment}"
  role          = aws_iam_role.privacy_rights_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.privacy_rights_zip.output_path
  source_code_hash = data.archive_file.privacy_rights_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.privacy_rights_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      PROJECT_NAME      = var.project_name
      BREACH_BUCKET     = aws_s3_bucket.breach_response.bucket
      NY_SHIELD_KMS_KEY = aws_kms_key.ny_shield_key.arn
    }
  }

  tags = {
    Name = "${var.project_name}-privacy-rights-${var.environment}"
  }
}

data "archive_file" "privacy_rights_zip" {
  type        = "zip"
  output_path = "/tmp/privacy_rights.zip"
  source {
    content = templatefile("${path.module}/lambda/privacy_rights.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Security Monitoring Lambda
resource "aws_lambda_function" "security_monitor" {
  function_name = "${var.project_name}-security-monitor-${var.environment}"
  role          = aws_iam_role.security_monitor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.security_monitor_zip.output_path
  source_code_hash = data.archive_file.security_monitor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.security_monitor_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      BREACH_BUCKET      = aws_s3_bucket.breach_response.bucket
      NOTIFICATION_TOPIC = aws_sns_topic.breach_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-security-monitor-${var.environment}"
  }
}

data "archive_file" "security_monitor_zip" {
  type        = "zip"
  output_path = "/tmp/security_monitor.zip"
  source {
    content = templatefile("${path.module}/lambda/security_monitor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# SNS Topic for Breach Notifications
resource "aws_sns_topic" "breach_notifications" {
  name              = "${var.project_name}-breach-notifications-${var.environment}"
  kms_master_key_id = aws_kms_key.ny_shield_key.arn

  tags = {
    Name = "${var.project_name}-breach-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "breach_email_notification" {
  count = var.breach_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.breach_notifications.arn
  protocol  = "email"
  endpoint  = var.breach_notification_email
}

# IAM Roles and Policies

# Breach Detector Role
resource "aws_iam_role" "breach_detector_role" {
  name = "${var.project_name}-breach-detector-role-${var.environment}"

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

resource "aws_iam_role_policy" "breach_detector_policy" {
  name = "${var.project_name}-breach-detector-policy-${var.environment}"
  role = aws_iam_role.breach_detector_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
          "cloudtrail:LookupEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "guardduty:GetDetector",
          "guardduty:ListDetectors",
          "guardduty:GetFindings",
          "guardduty:ListFindings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "securityhub:GetFindings",
          "securityhub:BatchImportFindings"
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
          aws_s3_bucket.breach_response.arn,
          "${aws_s3_bucket.breach_response.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.breach_notifications.arn
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
          aws_kms_key.ny_shield_key.arn
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

resource "aws_iam_role_policy_attachment" "breach_detector_vpc_access" {
  role       = aws_iam_role.breach_detector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Privacy Rights Role
resource "aws_iam_role" "privacy_rights_role" {
  name = "${var.project_name}-privacy-rights-role-${var.environment}"

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

resource "aws_iam_role_policy" "privacy_rights_policy" {
  name = "${var.project_name}-privacy-rights-policy-${var.environment}"
  role = aws_iam_role.privacy_rights_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.compliance_records.arn,
          "${aws_dynamodb_table.compliance_records.arn}/index/*"
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
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.breach_response.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.ny_shield_key.arn
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

resource "aws_iam_role_policy_attachment" "privacy_rights_vpc_access" {
  role       = aws_iam_role.privacy_rights_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Monitor Role
resource "aws_iam_role" "security_monitor_role" {
  name = "${var.project_name}-security-monitor-role-${var.environment}"

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

resource "aws_iam_role_policy" "security_monitor_policy" {
  name = "${var.project_name}-security-monitor-policy-${var.environment}"
  role = aws_iam_role.security_monitor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "config:GetComplianceDetailsByConfigRule",
          "config:GetResourceConfigHistory",
          "config:DescribeConfigRules"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "inspector2:ListFindings",
          "inspector2:GetFindings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:DescribeDBParameterGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.breach_response.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.breach_notifications.arn
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

resource "aws_iam_role_policy_attachment" "security_monitor_vpc_access" {
  role       = aws_iam_role.security_monitor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Groups
resource "aws_security_group" "breach_detector_sg" {
  name_prefix = "${var.project_name}-breach-detector-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-breach-detector-sg-${var.environment}"
  }
}

resource "aws_security_group" "privacy_rights_sg" {
  name_prefix = "${var.project_name}-privacy-rights-sg-"
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
    Name = "${var.project_name}-privacy-rights-sg-${var.environment}"
  }
}

resource "aws_security_group" "security_monitor_sg" {
  name_prefix = "${var.project_name}-security-monitor-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-security-monitor-sg-${var.environment}"
  }
}

# CloudWatch Event Rules for NY SHIELD monitoring
resource "aws_cloudwatch_event_rule" "breach_detection_schedule" {
  name                = "${var.project_name}-breach-detection-${var.environment}"
  description         = "Scheduled breach detection monitoring"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name = "${var.project_name}-breach-detection-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "breach_detection_target" {
  rule      = aws_cloudwatch_event_rule.breach_detection_schedule.name
  target_id = "BreachDetectionTarget"
  arn       = aws_lambda_function.breach_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge_breach_detection" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breach_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.breach_detection_schedule.arn
}

resource "aws_cloudwatch_event_rule" "security_audit_schedule" {
  name                = "${var.project_name}-security-audit-${var.environment}"
  description         = "Daily security compliance audit"
  schedule_expression = "cron(0 6 * * ? *)" # Daily at 6 AM

  tags = {
    Name = "${var.project_name}-security-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "security_audit_target" {
  rule      = aws_cloudwatch_event_rule.security_audit_schedule.name
  target_id = "SecurityAuditTarget"
  arn       = aws_lambda_function.security_monitor.arn

  input = jsonencode({
    action = "daily_audit"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_security_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_audit_schedule.arn
}

# GuardDuty findings to trigger breach detection
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings-${var.environment}"
  description = "Capture GuardDuty findings for breach detection"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [7.0, 8.0, 8.5, 9.0, 9.5, 10.0] # High severity findings
    }
  })

  tags = {
    Name = "${var.project_name}-guardduty-findings-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_findings_target" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyFindingsTarget"
  arn       = aws_lambda_function.breach_detector.arn

  input_transformer {
    input_paths = {
      severity = "$.detail.severity"
      type     = "$.detail.type"
      finding  = "$.detail"
    }
    input_template = jsonencode({
      action   = "guardduty_finding"
      severity = "<severity>"
      type     = "<type>"
      finding  = "<finding>"
    })
  }
}

resource "aws_lambda_permission" "allow_eventbridge_guardduty" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breach_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ny_shield_logs" {
  for_each = toset([
    "breach-detector",
    "privacy-rights",
    "security-monitor"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2555 # 7 years for compliance
  kms_key_id        = aws_kms_key.ny_shield_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# Variables for NY SHIELD Act compliance
variable "breach_notification_email" {
  description = "Email address for breach notifications"
  type        = string
  default     = ""
}

variable "ny_shield_notification_timeline_hours" {
  description = "Timeline for NY SHIELD Act notifications in hours"
  type        = number
  default     = 72 # 72 hours as required by NY SHIELD Act
}

variable "enable_automatic_breach_detection" {
  description = "Enable automatic breach detection"
  type        = bool
  default     = true
}

# Outputs
output "breach_response_bucket" {
  description = "S3 bucket for breach response"
  value       = aws_s3_bucket.breach_response.bucket
}

output "breach_detector_arn" {
  description = "Breach detector Lambda function ARN"
  value       = aws_lambda_function.breach_detector.arn
}

output "privacy_rights_arn" {
  description = "Privacy rights Lambda function ARN"
  value       = aws_lambda_function.privacy_rights.arn
}

output "breach_notifications_topic_arn" {
  description = "SNS topic for breach notifications"
  value       = aws_sns_topic.breach_notifications.arn
}

output "ny_shield_kms_key_arn" {
  description = "KMS key ARN for NY SHIELD Act encryption"
  value       = aws_kms_key.ny_shield_key.arn
}