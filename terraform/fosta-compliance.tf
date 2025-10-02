# FOSTA Act Compliance for AEIMS
# Fight Online Sex Trafficking Act - Strict compliance implementation
# Prevents online facilitation of sex trafficking and prostitution

# FOSTA Compliance S3 Bucket
resource "aws_s3_bucket" "fosta_compliance" {
  bucket = "${var.project_name}-fosta-compliance-${var.environment}-${random_id.fosta_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-fosta-compliance-${var.environment}"
    Purpose   = "FOSTACompliance"
    DataClass = "AntiTrafficking"
    Retention = "indefinite"
  }
}

resource "random_id" "fosta_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "fosta_versioning" {
  bucket = aws_s3_bucket.fosta_compliance.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "fosta_encryption" {
  bucket = aws_s3_bucket.fosta_compliance.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.fosta_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# FOSTA KMS Key
resource "aws_kms_key" "fosta_key" {
  description             = "KMS key for FOSTA Act compliance data encryption"
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
        Sid    = "Allow FOSTA Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com",
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
    Name = "${var.project_name}-fosta-key-${var.environment}"
  }
}

resource "aws_kms_alias" "fosta_key_alias" {
  name          = "alias/${var.project_name}-fosta-key-${var.environment}"
  target_key_id = aws_kms_key.fosta_key.key_id
}

# Sex Trafficking Detection Lambda
resource "aws_lambda_function" "sex_trafficking_detector" {
  function_name = "${var.project_name}-sex-trafficking-detector-${var.environment}"
  role          = aws_iam_role.sex_trafficking_detector_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.sex_trafficking_detector_zip.output_path
  source_code_hash = data.archive_file.sex_trafficking_detector_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.fosta_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      FOSTA_BUCKET       = aws_s3_bucket.fosta_compliance.bucket
      FOSTA_KMS_KEY      = aws_kms_key.fosta_key.arn
      NOTIFICATION_TOPIC = aws_sns_topic.fosta_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-sex-trafficking-detector-${var.environment}"
  }
}

data "archive_file" "sex_trafficking_detector_zip" {
  type        = "zip"
  output_path = "/tmp/sex_trafficking_detector.zip"
  source {
    content = templatefile("${path.module}/lambda/sex_trafficking_detector.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# FOSTA Content Filter Lambda
resource "aws_lambda_function" "fosta_content_filter" {
  function_name = "${var.project_name}-fosta-content-filter-${var.environment}"
  role          = aws_iam_role.fosta_content_filter_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 1024

  filename         = data.archive_file.fosta_content_filter_zip.output_path
  source_code_hash = data.archive_file.fosta_content_filter_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.fosta_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      FOSTA_BUCKET       = aws_s3_bucket.fosta_compliance.bucket
      NOTIFICATION_TOPIC = aws_sns_topic.fosta_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-fosta-content-filter-${var.environment}"
  }
}

data "archive_file" "fosta_content_filter_zip" {
  type        = "zip"
  output_path = "/tmp/fosta_content_filter.zip"
  source {
    content = templatefile("${path.module}/lambda/fosta_content_filter.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# FOSTA Communication Monitor Lambda
resource "aws_lambda_function" "fosta_communication_monitor" {
  function_name = "${var.project_name}-fosta-communication-monitor-${var.environment}"
  role          = aws_iam_role.fosta_communication_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.fosta_communication_zip.output_path
  source_code_hash = data.archive_file.fosta_communication_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.fosta_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      FOSTA_BUCKET       = aws_s3_bucket.fosta_compliance.bucket
      NOTIFICATION_TOPIC = aws_sns_topic.fosta_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-fosta-communication-monitor-${var.environment}"
  }
}

data "archive_file" "fosta_communication_zip" {
  type        = "zip"
  output_path = "/tmp/fosta_communication.zip"
  source {
    content = templatefile("${path.module}/lambda/fosta_communication_monitor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# FOSTA Law Enforcement Reporter Lambda
resource "aws_lambda_function" "fosta_law_enforcement_reporter" {
  function_name = "${var.project_name}-fosta-law-enforcement-reporter-${var.environment}"
  role          = aws_iam_role.fosta_law_enforcement_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.fosta_law_enforcement_zip.output_path
  source_code_hash = data.archive_file.fosta_law_enforcement_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.fosta_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      PROJECT_NAME            = var.project_name
      FOSTA_BUCKET            = aws_s3_bucket.fosta_compliance.bucket
      NOTIFICATION_TOPIC      = aws_sns_topic.fosta_notifications.arn
      FBI_REPORTING_ENABLED   = var.enable_fbi_reporting
      NCMEC_REPORTING_ENABLED = var.enable_ncmec_reporting
    }
  }

  tags = {
    Name = "${var.project_name}-fosta-law-enforcement-reporter-${var.environment}"
  }
}

data "archive_file" "fosta_law_enforcement_zip" {
  type        = "zip"
  output_path = "/tmp/fosta_law_enforcement.zip"
  source {
    content = templatefile("${path.module}/lambda/fosta_law_enforcement_reporter.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# FOSTA Compliance Auditor Lambda
resource "aws_lambda_function" "fosta_compliance_auditor" {
  function_name = "${var.project_name}-fosta-compliance-auditor-${var.environment}"
  role          = aws_iam_role.fosta_auditor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.fosta_auditor_zip.output_path
  source_code_hash = data.archive_file.fosta_auditor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.fosta_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
      FOSTA_BUCKET = aws_s3_bucket.fosta_compliance.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-fosta-compliance-auditor-${var.environment}"
  }
}

data "archive_file" "fosta_auditor_zip" {
  type        = "zip"
  output_path = "/tmp/fosta_auditor.zip"
  source {
    content = templatefile("${path.module}/lambda/fosta_compliance_auditor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# SNS Topic for FOSTA Notifications
resource "aws_sns_topic" "fosta_notifications" {
  name              = "${var.project_name}-fosta-notifications-${var.environment}"
  kms_master_key_id = aws_kms_key.fosta_key.arn

  tags = {
    Name = "${var.project_name}-fosta-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "fosta_email_notification" {
  count = var.fosta_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.fosta_notifications.arn
  protocol  = "email"
  endpoint  = var.fosta_notification_email
}

# Emergency SNS Topic for Critical FOSTA Violations
resource "aws_sns_topic" "fosta_emergency_notifications" {
  name              = "${var.project_name}-fosta-emergency-notifications-${var.environment}"
  kms_master_key_id = aws_kms_key.fosta_key.arn

  tags = {
    Name = "${var.project_name}-fosta-emergency-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "fosta_emergency_email" {
  count = var.fosta_emergency_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.fosta_emergency_notifications.arn
  protocol  = "email"
  endpoint  = var.fosta_emergency_email
}

resource "aws_sns_topic_subscription" "fosta_emergency_sms" {
  count = var.fosta_emergency_phone != "" ? 1 : 0

  topic_arn = aws_sns_topic.fosta_emergency_notifications.arn
  protocol  = "sms"
  endpoint  = var.fosta_emergency_phone
}

# DynamoDB Tables for FOSTA Compliance

# Sex Trafficking Detection Logs
resource "aws_dynamodb_table" "sex_trafficking_detection_logs" {
  name         = "${var.project_name}-sex-trafficking-detection-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "detection_id"

  attribute {
    name = "detection_id"
    type = "S"
  }

  attribute {
    name = "detection_timestamp"
    type = "S"
  }

  attribute {
    name = "risk_score"
    type = "N"
  }

  attribute {
    name = "content_type"
    type = "S"
  }

  global_secondary_index {
    name      = "timestamp-risk-index"
    hash_key  = "detection_timestamp"
    range_key = "risk_score"
  }

  global_secondary_index {
    name      = "content-type-index"
    hash_key  = "content_type"
    range_key = "detection_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.fosta_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-sex-trafficking-detection-${var.environment}"
  }
}

# FOSTA Violation Reports
resource "aws_dynamodb_table" "fosta_violation_reports" {
  name         = "${var.project_name}-fosta-violation-reports-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "violation_id"

  attribute {
    name = "violation_id"
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
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name      = "severity-timestamp-index"
    hash_key  = "severity_level"
    range_key = "report_timestamp"
  }

  global_secondary_index {
    name      = "user-timestamp-index"
    hash_key  = "user_id"
    range_key = "report_timestamp"
  }

  global_secondary_index {
    name      = "status-timestamp-index"
    hash_key  = "status"
    range_key = "report_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.fosta_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-fosta-violation-reports-${var.environment}"
  }
}

# FOSTA Content Filter Logs
resource "aws_dynamodb_table" "fosta_content_filter_logs" {
  name         = "${var.project_name}-fosta-content-filter-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "filter_id"
  range_key    = "filter_timestamp"

  attribute {
    name = "filter_id"
    type = "S"
  }

  attribute {
    name = "filter_timestamp"
    type = "S"
  }

  attribute {
    name = "filter_action"
    type = "S"
  }

  attribute {
    name = "content_hash"
    type = "S"
  }

  global_secondary_index {
    name      = "action-timestamp-index"
    hash_key  = "filter_action"
    range_key = "filter_timestamp"
  }

  global_secondary_index {
    name      = "content-hash-index"
    hash_key  = "content_hash"
    range_key = "filter_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.fosta_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-fosta-content-filter-logs-${var.environment}"
  }
}

# FOSTA Communication Monitoring Logs
resource "aws_dynamodb_table" "fosta_communication_logs" {
  name         = "${var.project_name}-fosta-communication-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "communication_id"
  range_key    = "monitor_timestamp"

  attribute {
    name = "communication_id"
    type = "S"
  }

  attribute {
    name = "monitor_timestamp"
    type = "S"
  }

  attribute {
    name = "participants"
    type = "S"
  }

  attribute {
    name = "risk_assessment"
    type = "S"
  }

  global_secondary_index {
    name      = "participants-timestamp-index"
    hash_key  = "participants"
    range_key = "monitor_timestamp"
  }

  global_secondary_index {
    name      = "risk-timestamp-index"
    hash_key  = "risk_assessment"
    range_key = "monitor_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.fosta_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-fosta-communication-logs-${var.environment}"
  }
}

# IAM Roles and Policies

# Sex Trafficking Detector Role
resource "aws_iam_role" "sex_trafficking_detector_role" {
  name = "${var.project_name}-sex-trafficking-detector-role-${var.environment}"

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

resource "aws_iam_role_policy" "sex_trafficking_detector_policy" {
  name = "${var.project_name}-sex-trafficking-detector-policy-${var.environment}"
  role = aws_iam_role.sex_trafficking_detector_role.id

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
          "textract:DetectDocumentText",
          "comprehend:DetectSentiment",
          "comprehend:DetectKeyPhrases",
          "comprehend:DetectEntities"
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
          aws_dynamodb_table.sex_trafficking_detection_logs.arn,
          "${aws_dynamodb_table.sex_trafficking_detection_logs.arn}/index/*"
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
          "${aws_s3_bucket.fosta_compliance.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.fosta_notifications.arn,
          aws_sns_topic.fosta_emergency_notifications.arn
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
          aws_kms_key.fosta_key.arn
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

# FOSTA Content Filter Role
resource "aws_iam_role" "fosta_content_filter_role" {
  name = "${var.project_name}-fosta-content-filter-role-${var.environment}"

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

resource "aws_iam_role_policy" "fosta_content_filter_policy" {
  name = "${var.project_name}-fosta-content-filter-policy-${var.environment}"
  role = aws_iam_role.fosta_content_filter_role.id

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
          aws_dynamodb_table.fosta_content_filter_logs.arn,
          "${aws_dynamodb_table.fosta_content_filter_logs.arn}/index/*",
          aws_dynamodb_table.fosta_violation_reports.arn,
          "${aws_dynamodb_table.fosta_violation_reports.arn}/index/*"
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
          "${aws_s3_bucket.fosta_compliance.arn}/*",
          "${aws_s3_bucket.aeims_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.fosta_notifications.arn,
          aws_sns_topic.fosta_emergency_notifications.arn
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

# FOSTA Communication Monitor Role
resource "aws_iam_role" "fosta_communication_role" {
  name = "${var.project_name}-fosta-communication-role-${var.environment}"

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

resource "aws_iam_role_policy" "fosta_communication_policy" {
  name = "${var.project_name}-fosta-communication-policy-${var.environment}"
  role = aws_iam_role.fosta_communication_role.id

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
          aws_dynamodb_table.fosta_communication_logs.arn,
          "${aws_dynamodb_table.fosta_communication_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.fosta_compliance.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.fosta_notifications.arn
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

# FOSTA Law Enforcement Reporter Role
resource "aws_iam_role" "fosta_law_enforcement_role" {
  name = "${var.project_name}-fosta-law-enforcement-role-${var.environment}"

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

resource "aws_iam_role_policy" "fosta_law_enforcement_policy" {
  name = "${var.project_name}-fosta-law-enforcement-policy-${var.environment}"
  role = aws_iam_role.fosta_law_enforcement_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.fosta_violation_reports.arn,
          "${aws_dynamodb_table.fosta_violation_reports.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.fosta_compliance.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.fosta_notifications.arn,
          aws_sns_topic.fosta_emergency_notifications.arn
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

# FOSTA Auditor Role
resource "aws_iam_role" "fosta_auditor_role" {
  name = "${var.project_name}-fosta-auditor-role-${var.environment}"

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

resource "aws_iam_role_policy" "fosta_auditor_policy" {
  name = "${var.project_name}-fosta-auditor-policy-${var.environment}"
  role = aws_iam_role.fosta_auditor_role.id

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
          aws_dynamodb_table.sex_trafficking_detection_logs.arn,
          "${aws_dynamodb_table.sex_trafficking_detection_logs.arn}/index/*",
          aws_dynamodb_table.fosta_violation_reports.arn,
          "${aws_dynamodb_table.fosta_violation_reports.arn}/index/*",
          aws_dynamodb_table.fosta_content_filter_logs.arn,
          "${aws_dynamodb_table.fosta_content_filter_logs.arn}/index/*",
          aws_dynamodb_table.fosta_communication_logs.arn,
          "${aws_dynamodb_table.fosta_communication_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.fosta_compliance.arn}/*"
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
resource "aws_iam_role_policy_attachment" "sex_trafficking_detector_vpc_access" {
  role       = aws_iam_role.sex_trafficking_detector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fosta_content_filter_vpc_access" {
  role       = aws_iam_role.fosta_content_filter_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fosta_communication_vpc_access" {
  role       = aws_iam_role.fosta_communication_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fosta_law_enforcement_vpc_access" {
  role       = aws_iam_role.fosta_law_enforcement_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fosta_auditor_vpc_access" {
  role       = aws_iam_role.fosta_auditor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group
resource "aws_security_group" "fosta_sg" {
  name_prefix = "${var.project_name}-fosta-sg-"
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
    Name = "${var.project_name}-fosta-sg-${var.environment}"
  }
}

# CloudWatch Event Rules for FOSTA monitoring

# Real-time content monitoring for FOSTA violations
resource "aws_cloudwatch_event_rule" "fosta_content_monitoring" {
  name        = "${var.project_name}-fosta-content-monitoring-${var.environment}"
  description = "Monitor all content for FOSTA violations"

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
    Name = "${var.project_name}-fosta-content-monitoring-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "fosta_sex_trafficking_target" {
  rule      = aws_cloudwatch_event_rule.fosta_content_monitoring.name
  target_id = "FOSTASexTraffickingTarget"
  arn       = aws_lambda_function.sex_trafficking_detector.arn
}

resource "aws_cloudwatch_event_target" "fosta_content_filter_target" {
  rule      = aws_cloudwatch_event_rule.fosta_content_monitoring.name
  target_id = "FOSTAContentFilterTarget"
  arn       = aws_lambda_function.fosta_content_filter.arn
}

resource "aws_lambda_permission" "allow_eventbridge_fosta_sex_trafficking" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sex_trafficking_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fosta_content_monitoring.arn
}

resource "aws_lambda_permission" "allow_eventbridge_fosta_content_filter" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fosta_content_filter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fosta_content_monitoring.arn
}

# Hourly FOSTA compliance audit
resource "aws_cloudwatch_event_rule" "fosta_compliance_audit" {
  name                = "${var.project_name}-fosta-compliance-audit-${var.environment}"
  description         = "Hourly FOSTA compliance audit"
  schedule_expression = "rate(1 hour)"

  tags = {
    Name = "${var.project_name}-fosta-compliance-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "fosta_audit_target" {
  rule      = aws_cloudwatch_event_rule.fosta_compliance_audit.name
  target_id = "FOSTAAuditTarget"
  arn       = aws_lambda_function.fosta_compliance_auditor.arn

  input = jsonencode({
    action = "hourly_audit"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_fosta_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fosta_compliance_auditor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fosta_compliance_audit.arn
}

# Emergency response for critical FOSTA violations
resource "aws_cloudwatch_event_rule" "fosta_emergency_response" {
  name                = "${var.project_name}-fosta-emergency-response-${var.environment}"
  description         = "Emergency response for critical FOSTA violations"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name = "${var.project_name}-fosta-emergency-response-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "fosta_emergency_target" {
  rule      = aws_cloudwatch_event_rule.fosta_emergency_response.name
  target_id = "FOSTAEmergencyTarget"
  arn       = aws_lambda_function.fosta_law_enforcement_reporter.arn

  input = jsonencode({
    action = "emergency_check"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_fosta_emergency" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fosta_law_enforcement_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fosta_emergency_response.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "fosta_logs" {
  for_each = toset([
    "sex-trafficking-detector",
    "fosta-content-filter",
    "fosta-communication-monitor",
    "fosta-law-enforcement-reporter",
    "fosta-compliance-auditor"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2555 # 7 years for compliance
  kms_key_id        = aws_kms_key.fosta_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Alarms for FOSTA Compliance
resource "aws_cloudwatch_metric_alarm" "fosta_critical_violations" {
  alarm_name          = "${var.project_name}-fosta-critical-violations-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Critical FOSTA violations detected"

  dimensions = {
    FunctionName = aws_lambda_function.fosta_law_enforcement_reporter.function_name
  }

  alarm_actions = [
    aws_sns_topic.fosta_emergency_notifications.arn
  ]

  tags = {
    Name = "${var.project_name}-fosta-critical-violations-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "fosta_detection_failures" {
  alarm_name          = "${var.project_name}-fosta-detection-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "FOSTA detection system failures"

  dimensions = {
    FunctionName = aws_lambda_function.sex_trafficking_detector.function_name
  }

  alarm_actions = [aws_sns_topic.fosta_notifications.arn]

  tags = {
    Name = "${var.project_name}-fosta-detection-failures-alarm-${var.environment}"
  }
}

# Variables for FOSTA compliance
variable "fosta_notification_email" {
  description = "Email address for FOSTA compliance notifications"
  type        = string
  default     = ""
}

variable "fosta_emergency_email" {
  description = "Emergency email for critical FOSTA violations"
  type        = string
  default     = ""
}

variable "fosta_emergency_phone" {
  description = "Emergency phone number for critical FOSTA violations"
  type        = string
  default     = ""
}

variable "enable_fbi_reporting" {
  description = "Enable automatic FBI reporting for FOSTA violations"
  type        = bool
  default     = true
}

variable "enable_ncmec_reporting" {
  description = "Enable automatic NCMEC reporting for FOSTA violations"
  type        = bool
  default     = true
}

variable "fosta_detection_threshold" {
  description = "Confidence threshold for FOSTA violation detection (0-100)"
  type        = number
  default     = 80
}

variable "enable_zero_tolerance_mode" {
  description = "Enable zero tolerance mode for FOSTA violations"
  type        = bool
  default     = true
}

variable "auto_content_removal" {
  description = "Automatically remove content flagged for FOSTA violations"
  type        = bool
  default     = true
}

# Outputs
output "fosta_compliance_bucket" {
  description = "S3 bucket for FOSTA compliance"
  value       = aws_s3_bucket.fosta_compliance.bucket
}

output "sex_trafficking_detector_arn" {
  description = "Sex trafficking detector Lambda function ARN"
  value       = aws_lambda_function.sex_trafficking_detector.arn
}

output "fosta_content_filter_arn" {
  description = "FOSTA content filter Lambda function ARN"
  value       = aws_lambda_function.fosta_content_filter.arn
}

output "fosta_communication_monitor_arn" {
  description = "FOSTA communication monitor Lambda function ARN"
  value       = aws_lambda_function.fosta_communication_monitor.arn
}

output "fosta_law_enforcement_reporter_arn" {
  description = "FOSTA law enforcement reporter Lambda function ARN"
  value       = aws_lambda_function.fosta_law_enforcement_reporter.arn
}

output "fosta_notifications_topic_arn" {
  description = "SNS topic for FOSTA notifications"
  value       = aws_sns_topic.fosta_notifications.arn
}

output "fosta_emergency_notifications_topic_arn" {
  description = "SNS topic for FOSTA emergency notifications"
  value       = aws_sns_topic.fosta_emergency_notifications.arn
}

output "fosta_kms_key_arn" {
  description = "KMS key ARN for FOSTA encryption"
  value       = aws_kms_key.fosta_key.arn
}

output "sex_trafficking_detection_table" {
  description = "DynamoDB table for sex trafficking detection logs"
  value       = aws_dynamodb_table.sex_trafficking_detection_logs.name
}

output "fosta_violation_reports_table" {
  description = "DynamoDB table for FOSTA violation reports"
  value       = aws_dynamodb_table.fosta_violation_reports.name
}

output "fosta_content_filter_logs_table" {
  description = "DynamoDB table for FOSTA content filter logs"
  value       = aws_dynamodb_table.fosta_content_filter_logs.name
}

output "fosta_communication_logs_table" {
  description = "DynamoDB table for FOSTA communication logs"
  value       = aws_dynamodb_table.fosta_communication_logs.name
}