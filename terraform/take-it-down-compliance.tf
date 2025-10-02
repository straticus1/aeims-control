# TAKE IT DOWN Act Compliance for AEIMS
# Implements non-consensual intimate image (NCII) detection, reporting, and removal
# Complies with federal TAKE IT DOWN Act requirements

# TAKE IT DOWN S3 Bucket
resource "aws_s3_bucket" "take_it_down_compliance" {
  bucket = "${var.project_name}-take-it-down-compliance-${var.environment}-${random_id.tid_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-take-it-down-compliance-${var.environment}"
    Purpose   = "TAKEITDOWNCompliance"
    DataClass = "NCII"
    Retention = "indefinite"
  }
}

resource "random_id" "tid_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "take_it_down_versioning" {
  bucket = aws_s3_bucket.take_it_down_compliance.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "take_it_down_encryption" {
  bucket = aws_s3_bucket.take_it_down_compliance.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.take_it_down_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# TAKE IT DOWN KMS Key
resource "aws_kms_key" "take_it_down_key" {
  description             = "KMS key for TAKE IT DOWN Act compliance"
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
        Sid    = "Allow TAKE IT DOWN Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com",
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
    Name = "${var.project_name}-take-it-down-key-${var.environment}"
  }
}

resource "aws_kms_alias" "take_it_down_key_alias" {
  name          = "alias/${var.project_name}-take-it-down-key-${var.environment}"
  target_key_id = aws_kms_key.take_it_down_key.key_id
}

# NCII Detection Lambda
resource "aws_lambda_function" "ncii_detector" {
  function_name = "${var.project_name}-ncii-detector-${var.environment}"
  role          = aws_iam_role.ncii_detector_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.ncii_detector_zip.output_path
  source_code_hash = data.archive_file.ncii_detector_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.take_it_down_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT      = var.environment
      PROJECT_NAME     = var.project_name
      TID_BUCKET       = aws_s3_bucket.take_it_down_compliance.bucket
      TID_KMS_KEY      = aws_kms_key.take_it_down_key.arn
      PHOTODNA_API_KEY = var.photodna_api_key
    }
  }

  tags = {
    Name = "${var.project_name}-ncii-detector-${var.environment}"
  }
}

data "archive_file" "ncii_detector_zip" {
  type        = "zip"
  output_path = "/tmp/ncii_detector.zip"
  source {
    content = templatefile("${path.module}/lambda/ncii_detector.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Takedown Request Handler Lambda
resource "aws_lambda_function" "takedown_handler" {
  function_name = "${var.project_name}-takedown-handler-${var.environment}"
  role          = aws_iam_role.takedown_handler_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.takedown_handler_zip.output_path
  source_code_hash = data.archive_file.takedown_handler_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.take_it_down_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      TID_BUCKET         = aws_s3_bucket.take_it_down_compliance.bucket
      NOTIFICATION_TOPIC = aws_sns_topic.takedown_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-takedown-handler-${var.environment}"
  }
}

data "archive_file" "takedown_handler_zip" {
  type        = "zip"
  output_path = "/tmp/takedown_handler.zip"
  source {
    content = templatefile("${path.module}/lambda/takedown_handler.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# NCII Hash Database Manager Lambda
resource "aws_lambda_function" "ncii_hash_manager" {
  function_name = "${var.project_name}-ncii-hash-manager-${var.environment}"
  role          = aws_iam_role.ncii_hash_manager_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.ncii_hash_manager_zip.output_path
  source_code_hash = data.archive_file.ncii_hash_manager_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.take_it_down_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
      TID_BUCKET   = aws_s3_bucket.take_it_down_compliance.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-ncii-hash-manager-${var.environment}"
  }
}

data "archive_file" "ncii_hash_manager_zip" {
  type        = "zip"
  output_path = "/tmp/ncii_hash_manager.zip"
  source {
    content = templatefile("${path.module}/lambda/ncii_hash_manager.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# TAKE IT DOWN Compliance Auditor Lambda
resource "aws_lambda_function" "tid_compliance_auditor" {
  function_name = "${var.project_name}-tid-compliance-auditor-${var.environment}"
  role          = aws_iam_role.tid_auditor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.tid_auditor_zip.output_path
  source_code_hash = data.archive_file.tid_auditor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.take_it_down_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
      TID_BUCKET   = aws_s3_bucket.take_it_down_compliance.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-tid-compliance-auditor-${var.environment}"
  }
}

data "archive_file" "tid_auditor_zip" {
  type        = "zip"
  output_path = "/tmp/tid_auditor.zip"
  source {
    content = templatefile("${path.module}/lambda/tid_compliance_auditor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# SNS Topic for Takedown Notifications
resource "aws_sns_topic" "takedown_notifications" {
  name              = "${var.project_name}-takedown-notifications-${var.environment}"
  kms_master_key_id = aws_kms_key.take_it_down_key.arn

  tags = {
    Name = "${var.project_name}-takedown-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "takedown_email_notification" {
  count = var.takedown_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.takedown_notifications.arn
  protocol  = "email"
  endpoint  = var.takedown_notification_email
}

# DynamoDB Tables for TAKE IT DOWN Compliance

# NCII Hash Database
resource "aws_dynamodb_table" "ncii_hash_database" {
  name         = "${var.project_name}-ncii-hash-database-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "image_hash"

  attribute {
    name = "image_hash"
    type = "S"
  }

  attribute {
    name = "hash_type"
    type = "S"
  }

  attribute {
    name = "created_timestamp"
    type = "S"
  }

  global_secondary_index {
    name      = "hash-type-index"
    hash_key  = "hash_type"
    range_key = "created_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.take_it_down_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-ncii-hash-database-${var.environment}"
  }
}

# Takedown Requests
resource "aws_dynamodb_table" "takedown_requests" {
  name         = "${var.project_name}-takedown-requests-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "submitted_timestamp"
    type = "S"
  }

  attribute {
    name = "content_hash"
    type = "S"
  }

  global_secondary_index {
    name      = "status-timestamp-index"
    hash_key  = "status"
    range_key = "submitted_timestamp"
  }

  global_secondary_index {
    name     = "content-hash-index"
    hash_key = "content_hash"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.take_it_down_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-takedown-requests-${var.environment}"
  }
}

# NCII Detection Logs
resource "aws_dynamodb_table" "ncii_detection_logs" {
  name         = "${var.project_name}-ncii-detection-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "content_id"
  range_key    = "detection_timestamp"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "detection_timestamp"
    type = "S"
  }

  attribute {
    name = "detection_result"
    type = "S"
  }

  global_secondary_index {
    name      = "result-timestamp-index"
    hash_key  = "detection_result"
    range_key = "detection_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.take_it_down_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-ncii-detection-logs-${var.environment}"
  }
}

# IAM Roles and Policies

# NCII Detector Role
resource "aws_iam_role" "ncii_detector_role" {
  name = "${var.project_name}-ncii-detector-role-${var.environment}"

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

resource "aws_iam_role_policy" "ncii_detector_policy" {
  name = "${var.project_name}-ncii-detector-policy-${var.environment}"
  role = aws_iam_role.ncii_detector_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectModerationLabels",
          "rekognition:DetectFaces",
          "rekognition:SearchImagesByImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.ncii_hash_database.arn,
          "${aws_dynamodb_table.ncii_hash_database.arn}/index/*",
          aws_dynamodb_table.ncii_detection_logs.arn,
          "${aws_dynamodb_table.ncii_detection_logs.arn}/index/*"
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
          "${aws_s3_bucket.take_it_down_compliance.arn}/*",
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
          aws_kms_key.take_it_down_key.arn
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

# Takedown Handler Role
resource "aws_iam_role" "takedown_handler_role" {
  name = "${var.project_name}-takedown-handler-role-${var.environment}"

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

resource "aws_iam_role_policy" "takedown_handler_policy" {
  name = "${var.project_name}-takedown-handler-policy-${var.environment}"
  role = aws_iam_role.takedown_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.takedown_requests.arn,
          "${aws_dynamodb_table.takedown_requests.arn}/index/*",
          aws_dynamodb_table.ncii_hash_database.arn
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
          "${aws_s3_bucket.take_it_down_compliance.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.takedown_notifications.arn
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

# NCII Hash Manager Role
resource "aws_iam_role" "ncii_hash_manager_role" {
  name = "${var.project_name}-ncii-hash-manager-role-${var.environment}"

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

resource "aws_iam_role_policy" "ncii_hash_manager_policy" {
  name = "${var.project_name}-ncii-hash-manager-policy-${var.environment}"
  role = aws_iam_role.ncii_hash_manager_role.id

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
          aws_dynamodb_table.ncii_hash_database.arn,
          "${aws_dynamodb_table.ncii_hash_database.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.take_it_down_compliance.arn}/*"
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

# TID Auditor Role
resource "aws_iam_role" "tid_auditor_role" {
  name = "${var.project_name}-tid-auditor-role-${var.environment}"

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

resource "aws_iam_role_policy" "tid_auditor_policy" {
  name = "${var.project_name}-tid-auditor-policy-${var.environment}"
  role = aws_iam_role.tid_auditor_role.id

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
          aws_dynamodb_table.takedown_requests.arn,
          "${aws_dynamodb_table.takedown_requests.arn}/index/*",
          aws_dynamodb_table.ncii_detection_logs.arn,
          "${aws_dynamodb_table.ncii_detection_logs.arn}/index/*",
          aws_dynamodb_table.ncii_hash_database.arn,
          "${aws_dynamodb_table.ncii_hash_database.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.take_it_down_compliance.arn}/*"
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
resource "aws_iam_role_policy_attachment" "ncii_detector_vpc_access" {
  role       = aws_iam_role.ncii_detector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "takedown_handler_vpc_access" {
  role       = aws_iam_role.takedown_handler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ncii_hash_manager_vpc_access" {
  role       = aws_iam_role.ncii_hash_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "tid_auditor_vpc_access" {
  role       = aws_iam_role.tid_auditor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group
resource "aws_security_group" "take_it_down_sg" {
  name_prefix = "${var.project_name}-take-it-down-sg-"
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
    Name = "${var.project_name}-take-it-down-sg-${var.environment}"
  }
}

# CloudWatch Event Rules for TAKE IT DOWN monitoring

# Content upload monitoring for NCII detection
resource "aws_cloudwatch_event_rule" "ncii_content_upload" {
  name        = "${var.project_name}-ncii-content-upload-${var.environment}"
  description = "Trigger NCII detection on content upload"

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
    Name = "${var.project_name}-ncii-content-upload-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "ncii_detection_target" {
  rule      = aws_cloudwatch_event_rule.ncii_content_upload.name
  target_id = "NCIIDetectionTarget"
  arn       = aws_lambda_function.ncii_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge_ncii_detection" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ncii_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ncii_content_upload.arn
}

# Daily TAKE IT DOWN compliance audit
resource "aws_cloudwatch_event_rule" "tid_compliance_audit" {
  name                = "${var.project_name}-tid-compliance-audit-${var.environment}"
  description         = "Daily TAKE IT DOWN compliance audit"
  schedule_expression = "cron(0 9 * * ? *)" # Daily at 9 AM

  tags = {
    Name = "${var.project_name}-tid-compliance-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "tid_compliance_audit_target" {
  rule      = aws_cloudwatch_event_rule.tid_compliance_audit.name
  target_id = "TIDComplianceAuditTarget"
  arn       = aws_lambda_function.tid_compliance_auditor.arn

  input = jsonencode({
    action = "daily_audit"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_tid_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tid_compliance_auditor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tid_compliance_audit.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "take_it_down_logs" {
  for_each = toset([
    "ncii-detector",
    "takedown-handler",
    "ncii-hash-manager",
    "tid-compliance-auditor"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2555 # 7 years for compliance
  kms_key_id        = aws_kms_key.take_it_down_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Alarms for TAKE IT DOWN
resource "aws_cloudwatch_metric_alarm" "ncii_detection_failures" {
  alarm_name          = "${var.project_name}-ncii-detection-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "NCII detection failures"

  dimensions = {
    FunctionName = aws_lambda_function.ncii_detector.function_name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-ncii-detection-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "takedown_processing_failures" {
  alarm_name          = "${var.project_name}-takedown-processing-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Takedown request processing failures"

  dimensions = {
    FunctionName = aws_lambda_function.takedown_handler.function_name
  }

  alarm_actions = [aws_sns_topic.takedown_notifications.arn]

  tags = {
    Name = "${var.project_name}-takedown-processing-alarm-${var.environment}"
  }
}

# Variables for TAKE IT DOWN compliance
variable "takedown_notification_email" {
  description = "Email address for takedown notifications"
  type        = string
  default     = ""
}

variable "photodna_api_key" {
  description = "PhotoDNA API key for NCII detection"
  type        = string
  default     = ""
  sensitive   = true
}

variable "takedown_response_time_hours" {
  description = "Required response time for takedown requests in hours"
  type        = number
  default     = 24
}

variable "enable_proactive_ncii_scanning" {
  description = "Enable proactive NCII scanning of all uploaded content"
  type        = bool
  default     = true
}

variable "ncii_detection_confidence_threshold" {
  description = "Confidence threshold for NCII detection (0-100)"
  type        = number
  default     = 85
}

# Outputs
output "take_it_down_bucket" {
  description = "S3 bucket for TAKE IT DOWN compliance"
  value       = aws_s3_bucket.take_it_down_compliance.bucket
}

output "ncii_detector_arn" {
  description = "NCII detector Lambda function ARN"
  value       = aws_lambda_function.ncii_detector.arn
}

output "takedown_handler_arn" {
  description = "Takedown handler Lambda function ARN"
  value       = aws_lambda_function.takedown_handler.arn
}

output "ncii_hash_manager_arn" {
  description = "NCII hash manager Lambda function ARN"
  value       = aws_lambda_function.ncii_hash_manager.arn
}

output "takedown_notifications_topic_arn" {
  description = "SNS topic for takedown notifications"
  value       = aws_sns_topic.takedown_notifications.arn
}

output "take_it_down_kms_key_arn" {
  description = "KMS key ARN for TAKE IT DOWN encryption"
  value       = aws_kms_key.take_it_down_key.arn
}

output "ncii_hash_database_table" {
  description = "DynamoDB table for NCII hash database"
  value       = aws_dynamodb_table.ncii_hash_database.name
}

output "takedown_requests_table" {
  description = "DynamoDB table for takedown requests"
  value       = aws_dynamodb_table.takedown_requests.name
}

output "ncii_detection_logs_table" {
  description = "DynamoDB table for NCII detection logs"
  value       = aws_dynamodb_table.ncii_detection_logs.name
}