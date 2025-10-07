# Mann Act Compliance for AEIMS - 18 USC § 2421-2424
# Implements monitoring and prevention of interstate transportation for prostitution
# Complies with The White-Slave Traffic Act (Mann Act) requirements

# Mann Act Compliance S3 Bucket
resource "aws_s3_bucket" "mann_act_compliance" {
  bucket = "${var.project_name}-mann-act-compliance-${var.environment}-${random_id.mann_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-mann-act-compliance-${var.environment}"
    Purpose   = "MannActCompliance"
    DataClass = "AntiTrafficking"
    Retention = "indefinite"
  }
}

resource "random_id" "mann_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "mann_act_versioning" {
  bucket = aws_s3_bucket.mann_act_compliance.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mann_act_encryption" {
  bucket = aws_s3_bucket.mann_act_compliance.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mann_act_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Mann Act KMS Key
resource "aws_kms_key" "mann_act_key" {
  description             = "KMS key for Mann Act compliance data encryption"
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
        Sid    = "Allow Mann Act Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com",
            "sns.amazonaws.com"
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
    Name = "${var.project_name}-mann-act-key-${var.environment}"
  }
}

resource "aws_kms_alias" "mann_act_key_alias" {
  name          = "alias/${var.project_name}-mann-act-key-${var.environment}"
  target_key_id = aws_kms_key.mann_act_key.key_id
}

# Anti-Trafficking Content Monitor Lambda
resource "aws_lambda_function" "anti_trafficking_monitor" {
  function_name = "${var.project_name}-anti-trafficking-monitor-${var.environment}"
  role          = aws_iam_role.anti_trafficking_monitor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.anti_trafficking_monitor_zip.output_path
  source_code_hash = data.archive_file.anti_trafficking_monitor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.mann_act_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      MANN_ACT_BUCKET    = aws_s3_bucket.mann_act_compliance.bucket
      MANN_ACT_KMS_KEY   = aws_kms_key.mann_act_key.arn
      NOTIFICATION_TOPIC = aws_sns_topic.mann_act_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-anti-trafficking-monitor-${var.environment}"
  }
}

data "archive_file" "anti_trafficking_monitor_zip" {
  type        = "zip"
  output_path = "/tmp/anti_trafficking_monitor.zip"
  source {
    content = templatefile("${path.module}/lambda/anti_trafficking_monitor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Interstate Activity Tracker Lambda
resource "aws_lambda_function" "interstate_activity_tracker" {
  function_name = "${var.project_name}-interstate-activity-tracker-${var.environment}"
  role          = aws_iam_role.interstate_tracker_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.interstate_tracker_zip.output_path
  source_code_hash = data.archive_file.interstate_tracker_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.mann_act_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      PROJECT_NAME        = var.project_name
      MANN_ACT_BUCKET     = aws_s3_bucket.mann_act_compliance.bucket
      GEOLOCATION_API_KEY = var.geolocation_api_key
    }
  }

  tags = {
    Name = "${var.project_name}-interstate-activity-tracker-${var.environment}"
  }
}

data "archive_file" "interstate_tracker_zip" {
  type        = "zip"
  output_path = "/tmp/interstate_tracker.zip"
  source {
    content = templatefile("${path.module}/lambda/interstate_activity_tracker.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Suspicious Activity Reporter Lambda
resource "aws_lambda_function" "suspicious_activity_reporter" {
  function_name = "${var.project_name}-suspicious-activity-reporter-${var.environment}"
  role          = aws_iam_role.suspicious_activity_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.suspicious_activity_zip.output_path
  source_code_hash = data.archive_file.suspicious_activity_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.mann_act_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      PROJECT_NAME            = var.project_name
      MANN_ACT_BUCKET         = aws_s3_bucket.mann_act_compliance.bucket
      NOTIFICATION_TOPIC      = aws_sns_topic.mann_act_notifications.arn
      NCMEC_REPORTING_ENABLED = var.enable_ncmec_reporting
    }
  }

  tags = {
    Name = "${var.project_name}-suspicious-activity-reporter-${var.environment}"
  }
}

data "archive_file" "suspicious_activity_zip" {
  type        = "zip"
  output_path = "/tmp/suspicious_activity.zip"
  source {
    content = templatefile("${path.module}/lambda/suspicious_activity_reporter.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Mann Act Compliance Auditor Lambda
resource "aws_lambda_function" "mann_act_auditor" {
  function_name = "${var.project_name}-mann-act-auditor-${var.environment}"
  role          = aws_iam_role.mann_act_auditor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.mann_act_auditor_zip.output_path
  source_code_hash = data.archive_file.mann_act_auditor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.mann_act_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT     = var.environment
      PROJECT_NAME    = var.project_name
      MANN_ACT_BUCKET = aws_s3_bucket.mann_act_compliance.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-mann-act-auditor-${var.environment}"
  }
}

data "archive_file" "mann_act_auditor_zip" {
  type        = "zip"
  output_path = "/tmp/mann_act_auditor.zip"
  source {
    content = templatefile("${path.module}/lambda/mann_act_auditor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# SNS Topic for Mann Act Notifications
resource "aws_sns_topic" "mann_act_notifications" {
  name              = "${var.project_name}-mann-act-notifications-${var.environment}"
  kms_master_key_id = aws_kms_key.mann_act_key.arn

  tags = {
    Name = "${var.project_name}-mann-act-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "mann_act_email_notification" {
  count = var.mann_act_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.mann_act_notifications.arn
  protocol  = "email"
  endpoint  = var.mann_act_notification_email
}

# DynamoDB Tables for Mann Act Compliance

# Anti-Trafficking Content Logs
resource "aws_dynamodb_table" "anti_trafficking_logs" {
  name         = "${var.project_name}-anti-trafficking-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "content_id"
  range_key    = "analysis_timestamp"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "analysis_timestamp"
    type = "S"
  }

  attribute {
    name = "risk_level"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "risk-level-index"
    hash_key  = "risk_level"
    range_key = "analysis_timestamp"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "user-timestamp-index"
    hash_key  = "user_id"
    range_key = "analysis_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.mann_act_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-anti-trafficking-logs-${var.environment}"
  }
}

# Interstate Activity Tracking
resource "aws_dynamodb_table" "interstate_activity_tracking" {
  name         = "${var.project_name}-interstate-activity-tracking-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "activity_timestamp"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "activity_timestamp"
    type = "S"
  }

  attribute {
    name = "origin_state"
    type = "S"
  }

  attribute {
    name = "destination_state"
    type = "S"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "origin-state-index"
    hash_key  = "origin_state"
    range_key = "activity_timestamp"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "destination-state-index"
    hash_key  = "destination_state"
    range_key = "activity_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.mann_act_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-interstate-activity-tracking-${var.environment}"
  }
}

# Suspicious Activity Reports
resource "aws_dynamodb_table" "suspicious_activity_reports" {
  name         = "${var.project_name}-suspicious-activity-reports-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "report_id"

  attribute {
    name = "report_id"
    type = "S"
  }

  attribute {
    name = "report_timestamp"
    type = "S"
  }

  attribute {
    name = "severity_level"
    type = "S"
  }

  attribute {
    name = "reported_user_id"
    type = "S"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "severity-timestamp-index"
    hash_key  = "severity_level"
    range_key = "report_timestamp"
  }

  global_secondary_index {
    projection_type = "ALL"
    name      = "user-timestamp-index"
    hash_key  = "reported_user_id"
    range_key = "report_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.mann_act_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-suspicious-activity-reports-${var.environment}"
  }
}

# IAM Roles and Policies

# Anti-Trafficking Monitor Role
resource "aws_iam_role" "anti_trafficking_monitor_role" {
  name = "${var.project_name}-anti-trafficking-monitor-role-${var.environment}"

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

resource "aws_iam_role_policy" "anti_trafficking_monitor_policy" {
  name = "${var.project_name}-anti-trafficking-monitor-policy-${var.environment}"
  role = aws_iam_role.anti_trafficking_monitor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectModerationLabels",
          "rekognition:DetectText",
          "textract:DetectDocumentText",
          "comprehend:DetectSentiment",
          "comprehend:DetectKeyPhrases"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.anti_trafficking_logs.arn,
          "${aws_dynamodb_table.anti_trafficking_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.mann_act_compliance.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.mann_act_notifications.arn
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
          aws_kms_key.mann_act_key.arn
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

# Interstate Activity Tracker Role
resource "aws_iam_role" "interstate_tracker_role" {
  name = "${var.project_name}-interstate-tracker-role-${var.environment}"

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

resource "aws_iam_role_policy" "interstate_tracker_policy" {
  name = "${var.project_name}-interstate-tracker-policy-${var.environment}"
  role = aws_iam_role.interstate_tracker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.interstate_activity_tracking.arn,
          "${aws_dynamodb_table.interstate_activity_tracking.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.mann_act_compliance.arn}/*"
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

# Suspicious Activity Reporter Role
resource "aws_iam_role" "suspicious_activity_role" {
  name = "${var.project_name}-suspicious-activity-role-${var.environment}"

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

resource "aws_iam_role_policy" "suspicious_activity_policy" {
  name = "${var.project_name}-suspicious-activity-policy-${var.environment}"
  role = aws_iam_role.suspicious_activity_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.suspicious_activity_reports.arn,
          "${aws_dynamodb_table.suspicious_activity_reports.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.mann_act_compliance.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.mann_act_notifications.arn
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Mann Act Auditor Role
resource "aws_iam_role" "mann_act_auditor_role" {
  name = "${var.project_name}-mann-act-auditor-role-${var.environment}"

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

resource "aws_iam_role_policy" "mann_act_auditor_policy" {
  name = "${var.project_name}-mann-act-auditor-policy-${var.environment}"
  role = aws_iam_role.mann_act_auditor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.anti_trafficking_logs.arn,
          "${aws_dynamodb_table.anti_trafficking_logs.arn}/index/*",
          aws_dynamodb_table.interstate_activity_tracking.arn,
          "${aws_dynamodb_table.interstate_activity_tracking.arn}/index/*",
          aws_dynamodb_table.suspicious_activity_reports.arn,
          "${aws_dynamodb_table.suspicious_activity_reports.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.mann_act_compliance.arn}/*"
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

# Attach VPC access policies
resource "aws_iam_role_policy_attachment" "anti_trafficking_monitor_vpc_access" {
  role       = aws_iam_role.anti_trafficking_monitor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "interstate_tracker_vpc_access" {
  role       = aws_iam_role.interstate_tracker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "suspicious_activity_vpc_access" {
  role       = aws_iam_role.suspicious_activity_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "mann_act_auditor_vpc_access" {
  role       = aws_iam_role.mann_act_auditor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group
resource "aws_security_group" "mann_act_sg" {
  name_prefix = "${var.project_name}-mann-act-sg-"
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
    Name = "${var.project_name}-mann-act-sg-${var.environment}"
  }
}

# CloudWatch Event Rules for Mann Act monitoring

# Content monitoring for trafficking indicators
resource "aws_cloudwatch_event_rule" "anti_trafficking_content_monitor" {
  name        = "${var.project_name}-anti-trafficking-content-monitor-${var.environment}"
  description = "Monitor content for trafficking indicators"

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
    Name = "${var.project_name}-anti-trafficking-content-monitor-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "anti_trafficking_monitor_target" {
  rule      = aws_cloudwatch_event_rule.anti_trafficking_content_monitor.name
  target_id = "AntiTraffickingMonitorTarget"
  arn       = aws_lambda_function.anti_trafficking_monitor.arn
}

resource "aws_lambda_permission" "allow_eventbridge_anti_trafficking" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anti_trafficking_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.anti_trafficking_content_monitor.arn
}

# Daily Mann Act compliance audit
resource "aws_cloudwatch_event_rule" "mann_act_compliance_audit" {
  name                = "${var.project_name}-mann-act-compliance-audit-${var.environment}"
  description         = "Daily Mann Act compliance audit"
  schedule_expression = "cron(0 10 * * ? *)" # Daily at 10 AM

  tags = {
    Name = "${var.project_name}-mann-act-compliance-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "mann_act_audit_target" {
  rule      = aws_cloudwatch_event_rule.mann_act_compliance_audit.name
  target_id = "MannActAuditTarget"
  arn       = aws_lambda_function.mann_act_auditor.arn

  input = jsonencode({
    action = "daily_audit"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_mann_act_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mann_act_auditor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mann_act_compliance_audit.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "mann_act_logs" {
  for_each = toset([
    "anti-trafficking-monitor",
    "interstate-activity-tracker",
    "suspicious-activity-reporter",
    "mann-act-auditor"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2557 # 7 years for compliance
  kms_key_id        = aws_kms_key.mann_act_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Alarms for Mann Act Compliance
resource "aws_cloudwatch_metric_alarm" "anti_trafficking_monitor_failures" {
  alarm_name          = "${var.project_name}-anti-trafficking-monitor-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "Anti-trafficking monitor failures"

  dimensions = {
    FunctionName = aws_lambda_function.anti_trafficking_monitor.function_name
  }

  alarm_actions = [aws_sns_topic.mann_act_notifications.arn]

  tags = {
    Name = "${var.project_name}-anti-trafficking-monitor-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "suspicious_activity_high_volume" {
  alarm_name          = "${var.project_name}-suspicious-activity-high-volume-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = "3600" # 1 hour
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "High volume of suspicious activity reports"

  dimensions = {
    FunctionName = aws_lambda_function.suspicious_activity_reporter.function_name
  }

  alarm_actions = [aws_sns_topic.mann_act_notifications.arn]

  tags = {
    Name = "${var.project_name}-suspicious-activity-volume-alarm-${var.environment}"
  }
}

# Variables for Mann Act compliance
variable "mann_act_notification_email" {
  description = "Email address for Mann Act compliance notifications"
  type        = string
  default     = ""
}

# Note: enable_ncmec_reporting variable is defined in fosta-compliance.tf

variable "trafficking_detection_threshold" {
  description = "Confidence threshold for trafficking detection (0-100)"
  type        = number
  default     = 75
}

variable "interstate_tracking_enabled" {
  description = "Enable interstate activity tracking"
  type        = bool
  default     = true
}

variable "suspicious_activity_auto_report" {
  description = "Automatically report high-risk suspicious activity"
  type        = bool
  default     = true
}

# Outputs
output "mann_act_compliance_bucket" {
  description = "S3 bucket for Mann Act compliance"
  value       = aws_s3_bucket.mann_act_compliance.bucket
}

output "anti_trafficking_monitor_arn" {
  description = "Anti-trafficking monitor Lambda function ARN"
  value       = aws_lambda_function.anti_trafficking_monitor.arn
}

output "interstate_activity_tracker_arn" {
  description = "Interstate activity tracker Lambda function ARN"
  value       = aws_lambda_function.interstate_activity_tracker.arn
}

output "suspicious_activity_reporter_arn" {
  description = "Suspicious activity reporter Lambda function ARN"
  value       = aws_lambda_function.suspicious_activity_reporter.arn
}

output "mann_act_notifications_topic_arn" {
  description = "SNS topic for Mann Act notifications"
  value       = aws_sns_topic.mann_act_notifications.arn
}

output "mann_act_kms_key_arn" {
  description = "KMS key ARN for Mann Act encryption"
  value       = aws_kms_key.mann_act_key.arn
}

output "anti_trafficking_logs_table" {
  description = "DynamoDB table for anti-trafficking logs"
  value       = aws_dynamodb_table.anti_trafficking_logs.name
}

output "interstate_activity_tracking_table" {
  description = "DynamoDB table for interstate activity tracking"
  value       = aws_dynamodb_table.interstate_activity_tracking.name
}

output "suspicious_activity_reports_table" {
  description = "DynamoDB table for suspicious activity reports"
  value       = aws_dynamodb_table.suspicious_activity_reports.name
}
