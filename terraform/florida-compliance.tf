# Florida Compliance for AEIMS - HB 3, Florida Statute § 847.011, and § 847.01
# Implements age verification, geolocation-based controls, and obscenity law compliance

# Florida Compliance S3 Bucket
resource "aws_s3_bucket" "florida_compliance" {
  bucket = "${var.project_name}-florida-compliance-${var.environment}-${random_id.florida_bucket_suffix.hex}"

  tags = {
    Name      = "${var.project_name}-florida-compliance-${var.environment}"
    Purpose   = "FloridaCompliance"
    DataClass = "FloridaHB3"
    Retention = "7years"
  }
}

resource "random_id" "florida_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "florida_compliance_versioning" {
  bucket = aws_s3_bucket.florida_compliance.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "florida_compliance_encryption" {
  bucket = aws_s3_bucket.florida_compliance.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.florida_compliance_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# Florida Compliance KMS Key
resource "aws_kms_key" "florida_compliance_key" {
  description             = "KMS key for Florida compliance data encryption"
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
        Sid    = "Allow Florida Compliance Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com"
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
    Name = "${var.project_name}-florida-compliance-key-${var.environment}"
  }
}

resource "aws_kms_alias" "florida_compliance_key_alias" {
  name          = "alias/${var.project_name}-florida-compliance-key-${var.environment}"
  target_key_id = aws_kms_key.florida_compliance_key.key_id
}

# Florida HB 3 Age Verification Lambda
resource "aws_lambda_function" "florida_age_verifier" {
  function_name = "${var.project_name}-florida-age-verifier-${var.environment}"
  role          = aws_iam_role.florida_age_verifier_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.florida_age_verifier_zip.output_path
  source_code_hash = data.archive_file.florida_age_verifier_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.florida_compliance_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      PROJECT_NAME        = var.project_name
      COMPLIANCE_BUCKET   = aws_s3_bucket.florida_compliance.bucket
      FLORIDA_KMS_KEY     = aws_kms_key.florida_compliance_key.arn
      GEOLOCATION_API_KEY = var.geolocation_api_key
    }
  }

  tags = {
    Name = "${var.project_name}-florida-age-verifier-${var.environment}"
  }
}

data "archive_file" "florida_age_verifier_zip" {
  type        = "zip"
  output_path = "/tmp/florida_age_verifier.zip"
  source {
    content = templatefile("${path.module}/lambda/florida_age_verifier.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Geolocation and Access Control Lambda
resource "aws_lambda_function" "florida_geolocation_controller" {
  function_name = "${var.project_name}-florida-geolocation-controller-${var.environment}"
  role          = aws_iam_role.florida_geolocation_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.florida_geolocation_zip.output_path
  source_code_hash = data.archive_file.florida_geolocation_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.florida_compliance_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      PROJECT_NAME        = var.project_name
      COMPLIANCE_BUCKET   = aws_s3_bucket.florida_compliance.bucket
      GEOLOCATION_API_KEY = var.geolocation_api_key
    }
  }

  tags = {
    Name = "${var.project_name}-florida-geolocation-controller-${var.environment}"
  }
}

data "archive_file" "florida_geolocation_zip" {
  type        = "zip"
  output_path = "/tmp/florida_geolocation.zip"
  source {
    content = templatefile("${path.module}/lambda/florida_geolocation_controller.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Obscenity Content Filter Lambda (Florida § 847.01 & § 847.011)
resource "aws_lambda_function" "florida_obscenity_filter" {
  function_name = "${var.project_name}-florida-obscenity-filter-${var.environment}"
  role          = aws_iam_role.florida_obscenity_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900
  memory_size   = 1024

  filename         = data.archive_file.florida_obscenity_zip.output_path
  source_code_hash = data.archive_file.florida_obscenity_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.florida_compliance_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      PROJECT_NAME      = var.project_name
      COMPLIANCE_BUCKET = aws_s3_bucket.florida_compliance.bucket
      FLORIDA_KMS_KEY   = aws_kms_key.florida_compliance_key.arn
    }
  }

  tags = {
    Name = "${var.project_name}-florida-obscenity-filter-${var.environment}"
  }
}

data "archive_file" "florida_obscenity_zip" {
  type        = "zip"
  output_path = "/tmp/florida_obscenity.zip"
  source {
    content = templatefile("${path.module}/lambda/florida_obscenity_filter.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Florida HB 3 Compliance Auditor Lambda
resource "aws_lambda_function" "florida_compliance_auditor" {
  function_name = "${var.project_name}-florida-compliance-auditor-${var.environment}"
  role          = aws_iam_role.florida_compliance_auditor_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512

  filename         = data.archive_file.florida_compliance_auditor_zip.output_path
  source_code_hash = data.archive_file.florida_compliance_auditor_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.florida_compliance_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      PROJECT_NAME      = var.project_name
      COMPLIANCE_BUCKET = aws_s3_bucket.florida_compliance.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-florida-compliance-auditor-${var.environment}"
  }
}

data "archive_file" "florida_compliance_auditor_zip" {
  type        = "zip"
  output_path = "/tmp/florida_compliance_auditor.zip"
  source {
    content = templatefile("${path.module}/lambda/florida_compliance_auditor.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# DynamoDB Tables for Florida Compliance

# Florida HB 3 Age Verification Records
resource "aws_dynamodb_table" "florida_age_verification" {
  name         = "${var.project_name}-florida-age-verification-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "verification_timestamp"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "verification_timestamp"
    type = "S"
  }

  attribute {
    name = "verification_method"
    type = "S"
  }

  attribute {
    name = "ip_address"
    type = "S"
  }

  global_secondary_index {
    name      = "verification-method-index"
    hash_key  = "verification_method"
    range_key = "verification_timestamp"
  }

  global_secondary_index {
    name      = "ip-address-index"
    hash_key  = "ip_address"
    range_key = "verification_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.florida_compliance_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-florida-age-verification-${var.environment}"
  }
}

# Florida Geolocation Access Logs
resource "aws_dynamodb_table" "florida_geolocation_logs" {
  name         = "${var.project_name}-florida-geolocation-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "ip_address"
    type = "S"
  }

  attribute {
    name = "state"
    type = "S"
  }

  global_secondary_index {
    name      = "ip-timestamp-index"
    hash_key  = "ip_address"
    range_key = "timestamp"
  }

  global_secondary_index {
    name      = "state-timestamp-index"
    hash_key  = "state"
    range_key = "timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.florida_compliance_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-florida-geolocation-logs-${var.environment}"
  }
}

# Florida Obscenity Filtering Records
resource "aws_dynamodb_table" "florida_obscenity_logs" {
  name         = "${var.project_name}-florida-obscenity-logs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "content_id"
  range_key    = "filter_timestamp"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "filter_timestamp"
    type = "S"
  }

  attribute {
    name = "filter_result"
    type = "S"
  }

  attribute {
    name = "user_location"
    type = "S"
  }

  global_secondary_index {
    name      = "result-timestamp-index"
    hash_key  = "filter_result"
    range_key = "filter_timestamp"
  }

  global_secondary_index {
    name      = "location-timestamp-index"
    hash_key  = "user_location"
    range_key = "filter_timestamp"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.florida_compliance_key.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-florida-obscenity-logs-${var.environment}"
  }
}

# IAM Roles and Policies

# Florida Age Verifier Role
resource "aws_iam_role" "florida_age_verifier_role" {
  name = "${var.project_name}-florida-age-verifier-role-${var.environment}"

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

resource "aws_iam_role_policy" "florida_age_verifier_policy" {
  name = "${var.project_name}-florida-age-verifier-policy-${var.environment}"
  role = aws_iam_role.florida_age_verifier_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.florida_age_verification.arn,
          "${aws_dynamodb_table.florida_age_verification.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "textract:AnalyzeID",
          "textract:AnalyzeDocument",
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
          "${aws_s3_bucket.florida_compliance.arn}/*"
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
          aws_kms_key.florida_compliance_key.arn
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

# Florida Geolocation Role
resource "aws_iam_role" "florida_geolocation_role" {
  name = "${var.project_name}-florida-geolocation-role-${var.environment}"

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

resource "aws_iam_role_policy" "florida_geolocation_policy" {
  name = "${var.project_name}-florida-geolocation-policy-${var.environment}"
  role = aws_iam_role.florida_geolocation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.florida_geolocation_logs.arn,
          "${aws_dynamodb_table.florida_geolocation_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.florida_compliance.arn}/*"
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

# Florida Obscenity Filter Role
resource "aws_iam_role" "florida_obscenity_role" {
  name = "${var.project_name}-florida-obscenity-role-${var.environment}"

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

resource "aws_iam_role_policy" "florida_obscenity_policy" {
  name = "${var.project_name}-florida-obscenity-policy-${var.environment}"
  role = aws_iam_role.florida_obscenity_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectModerationLabels",
          "rekognition:DetectText",
          "textract:DetectDocumentText"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.florida_obscenity_logs.arn,
          "${aws_dynamodb_table.florida_obscenity_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.florida_compliance.arn}/*",
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
          aws_kms_key.florida_compliance_key.arn
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

# Florida Compliance Auditor Role
resource "aws_iam_role" "florida_compliance_auditor_role" {
  name = "${var.project_name}-florida-compliance-auditor-role-${var.environment}"

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

resource "aws_iam_role_policy" "florida_compliance_auditor_policy" {
  name = "${var.project_name}-florida-compliance-auditor-policy-${var.environment}"
  role = aws_iam_role.florida_compliance_auditor_role.id

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
          aws_dynamodb_table.florida_age_verification.arn,
          "${aws_dynamodb_table.florida_age_verification.arn}/index/*",
          aws_dynamodb_table.florida_geolocation_logs.arn,
          "${aws_dynamodb_table.florida_geolocation_logs.arn}/index/*",
          aws_dynamodb_table.florida_obscenity_logs.arn,
          "${aws_dynamodb_table.florida_obscenity_logs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.florida_compliance.arn}/*"
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
resource "aws_iam_role_policy_attachment" "florida_age_verifier_vpc_access" {
  role       = aws_iam_role.florida_age_verifier_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "florida_geolocation_vpc_access" {
  role       = aws_iam_role.florida_geolocation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "florida_obscenity_vpc_access" {
  role       = aws_iam_role.florida_obscenity_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "florida_compliance_auditor_vpc_access" {
  role       = aws_iam_role.florida_compliance_auditor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security Group
resource "aws_security_group" "florida_compliance_sg" {
  name_prefix = "${var.project_name}-florida-compliance-sg-"
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
    Name = "${var.project_name}-florida-compliance-sg-${var.environment}"
  }
}

# CloudWatch Event Rules for Florida Compliance

# Daily compliance audit
resource "aws_cloudwatch_event_rule" "florida_compliance_audit" {
  name                = "${var.project_name}-florida-compliance-audit-${var.environment}"
  description         = "Daily Florida compliance audit"
  schedule_expression = "cron(0 8 * * ? *)" # Daily at 8 AM

  tags = {
    Name = "${var.project_name}-florida-compliance-audit-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "florida_compliance_audit_target" {
  rule      = aws_cloudwatch_event_rule.florida_compliance_audit.name
  target_id = "FloridaComplianceAuditTarget"
  arn       = aws_lambda_function.florida_compliance_auditor.arn

  input = jsonencode({
    action = "daily_audit"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_florida_audit" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.florida_compliance_auditor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.florida_compliance_audit.arn
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "florida_compliance_logs" {
  for_each = toset([
    "florida-age-verifier",
    "florida-geolocation-controller",
    "florida-obscenity-filter",
    "florida-compliance-auditor"
  ])

  name              = "/aws/lambda/${var.project_name}-${each.key}-${var.environment}"
  retention_in_days = 2555 # 7 years for compliance
  kms_key_id        = aws_kms_key.florida_compliance_key.arn

  tags = {
    Name = "${var.project_name}-${each.key}-logs-${var.environment}"
  }
}

# CloudWatch Alarms for Florida Compliance
resource "aws_cloudwatch_metric_alarm" "florida_age_verification_failures" {
  alarm_name          = "${var.project_name}-florida-age-verification-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "Florida age verification failures"

  dimensions = {
    FunctionName = aws_lambda_function.florida_age_verifier.function_name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-florida-age-verification-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "florida_obscenity_filter_failures" {
  alarm_name          = "${var.project_name}-florida-obscenity-filter-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Florida obscenity filter failures"

  dimensions = {
    FunctionName = aws_lambda_function.florida_obscenity_filter.function_name
  }

  alarm_actions = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  tags = {
    Name = "${var.project_name}-florida-obscenity-filter-alarm-${var.environment}"
  }
}

# Variables for Florida Compliance
variable "geolocation_api_key" {
  description = "API key for geolocation services"
  type        = string
  default     = ""
  sensitive   = true
}

variable "florida_age_verification_methods" {
  description = "Approved age verification methods for Florida HB 3"
  type        = list(string)
  default     = ["government_id", "credit_card", "third_party_service"]
}

variable "enable_florida_strict_mode" {
  description = "Enable strict Florida compliance mode"
  type        = bool
  default     = true
}

variable "florida_content_moderation_threshold" {
  description = "Content moderation threshold for Florida users (0-100)"
  type        = number
  default     = 90
}

# Outputs
output "florida_compliance_bucket" {
  description = "S3 bucket for Florida compliance"
  value       = aws_s3_bucket.florida_compliance.bucket
}

output "florida_age_verifier_arn" {
  description = "Florida age verifier Lambda function ARN"
  value       = aws_lambda_function.florida_age_verifier.arn
}

output "florida_geolocation_controller_arn" {
  description = "Florida geolocation controller Lambda function ARN"
  value       = aws_lambda_function.florida_geolocation_controller.arn
}

output "florida_obscenity_filter_arn" {
  description = "Florida obscenity filter Lambda function ARN"
  value       = aws_lambda_function.florida_obscenity_filter.arn
}

output "florida_compliance_kms_key_arn" {
  description = "KMS key ARN for Florida compliance encryption"
  value       = aws_kms_key.florida_compliance_key.arn
}

output "florida_age_verification_table" {
  description = "DynamoDB table for Florida age verification records"
  value       = aws_dynamodb_table.florida_age_verification.name
}

output "florida_geolocation_logs_table" {
  description = "DynamoDB table for Florida geolocation logs"
  value       = aws_dynamodb_table.florida_geolocation_logs.name
}

output "florida_obscenity_logs_table" {
  description = "DynamoDB table for Florida obscenity filtering logs"
  value       = aws_dynamodb_table.florida_obscenity_logs.name
}