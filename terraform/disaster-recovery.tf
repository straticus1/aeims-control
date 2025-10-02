# Disaster Recovery for AEIMS Infrastructure
# Multi-region backup and failover capabilities

# Secondary region configuration
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "AEIMS"
      Environment = "${var.environment}-dr"
      ManagedBy   = "Terraform"
      Purpose     = "DisasterRecovery"
    }
  }
}

# DR VPC
resource "aws_vpc" "aeims_dr_vpc" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider             = aws.dr
  cidr_block           = var.dr_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-dr-vpc-${var.environment}"
  }
}

# DR Subnets
resource "aws_subnet" "dr_private_subnets" {
  count = var.enable_disaster_recovery ? var.dr_subnet_count : 0

  provider          = aws.dr
  vpc_id            = aws_vpc.aeims_dr_vpc[0].id
  cidr_block        = cidrsubnet(var.dr_vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.dr_azs[0].names[count.index]

  tags = {
    Name = "${var.project_name}-dr-private-subnet-${count.index + 1}-${var.environment}"
  }
}

data "aws_availability_zones" "dr_azs" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider = aws.dr
  state    = "available"
}

# Database Cross-Region Backups
resource "aws_db_instance" "aeims_dr_databases" {
  for_each = var.enable_disaster_recovery ? var.database_configs : {}

  provider = aws.dr

  identifier = "${var.project_name}-${each.key}-dr-${var.environment}"

  # Create from automated backup of primary database
  restore_to_point_in_time {
    source_db_instance_identifier = aws_db_instance.aeims_databases[each.key].identifier
    use_latest_restorable_time    = true
  }

  instance_class = each.value.instance_class

  # Enable automated backups for DR
  backup_retention_period = 35
  backup_window           = "05:00-06:00"
  maintenance_window      = "sun:06:00-sun:07:00"

  multi_az                  = true
  publicly_accessible       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${each.key}-dr-final-${var.environment}"

  tags = {
    Name        = "${var.project_name}-${each.key}-dr-${var.environment}"
    Purpose     = "DisasterRecovery"
    Environment = var.environment
  }
}

# S3 Cross-Region Replication for backups
resource "aws_s3_bucket" "aeims_dr_backups" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider = aws.dr
  bucket   = "${var.project_name}-dr-backups-${var.environment}-${random_id.dr_bucket_suffix[0].hex}"

  tags = {
    Name    = "${var.project_name}-dr-backups-${var.environment}"
    Purpose = "DisasterRecovery"
  }
}

resource "random_id" "dr_bucket_suffix" {
  count = var.enable_disaster_recovery ? 1 : 0

  byte_length = 4
}

resource "aws_s3_bucket_versioning" "dr_backups_versioning" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider = aws.dr
  bucket   = aws_s3_bucket.aeims_dr_backups[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# Cross-region replication
resource "aws_s3_bucket_replication_configuration" "aeims_backup_replication" {
  count = var.enable_disaster_recovery ? 1 : 0

  role   = aws_iam_role.s3_replication_role[0].arn
  bucket = aws_s3_bucket.aeims_assets.id

  rule {
    id     = "ReplicateToDR"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.aeims_dr_backups[0].arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.aeims_dr_key[0].arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.aeims_assets_versioning]
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication_role" {
  count = var.enable_disaster_recovery ? 1 : 0

  name = "${var.project_name}-s3-replication-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication_policy" {
  count = var.enable_disaster_recovery ? 1 : 0

  name = "${var.project_name}-s3-replication-policy-${var.environment}"
  role = aws_iam_role.s3_replication_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.aeims_assets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.aeims_assets.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.aeims_dr_backups[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.aeims_key.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.aeims_dr_key[0].arn
      }
    ]
  })
}

# KMS key for DR region
resource "aws_kms_key" "aeims_dr_key" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider                = aws.dr
  description             = "KMS key for AEIMS DR ${var.environment} environment"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-dr-kms-key-${var.environment}"
  }
}

resource "aws_kms_alias" "aeims_dr_key_alias" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider      = aws.dr
  name          = "alias/${var.project_name}-dr-key-${var.environment}"
  target_key_id = aws_kms_key.aeims_dr_key[0].key_id
}

# Route 53 Health Checks and Failover
resource "aws_route53_health_check" "aeims_primary_health" {
  count = var.enable_disaster_recovery && var.domain_name != "" ? 1 : 0

  fqdn                            = var.domain_name
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/health"
  failure_threshold               = "3"
  request_interval                = "30"
  cloudwatch_alarm_region         = var.aws_region
  insufficient_data_health_status = "Failure"

  tags = {
    Name = "${var.project_name}-primary-health-check-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_site_down" {
  count = var.enable_disaster_recovery ? 1 : 0

  alarm_name          = "${var.project_name}-primary-site-down-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Primary site health check failure"

  dimensions = {
    HealthCheckId = aws_route53_health_check.aeims_primary_health[0].id
  }

  alarm_actions = [aws_sns_topic.dr_notifications[0].arn]

  tags = {
    Name = "${var.project_name}-primary-site-alarm-${var.environment}"
  }
}

# DNS Failover Configuration
resource "aws_route53_record" "aeims_primary" {
  count = var.enable_disaster_recovery && var.domain_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = aws_lb.aeims_alb.dns_name
    zone_id                = aws_lb.aeims_alb.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.aeims_primary_health[0].id
}

resource "aws_route53_record" "aeims_secondary" {
  count = var.enable_disaster_recovery && var.domain_name != "" ? 1 : 0

  provider = aws.dr
  zone_id  = var.route53_zone_id
  name     = var.domain_name
  type     = "A"

  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = aws_lb.aeims_dr_alb[0].dns_name
    zone_id                = aws_lb.aeims_dr_alb[0].zone_id
    evaluate_target_health = true
  }
}

# DR Load Balancer (simplified)
resource "aws_lb" "aeims_dr_alb" {
  count = var.enable_disaster_recovery ? 1 : 0

  provider           = aws.dr
  name               = "${var.project_name}-dr-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.dr_private_subnets[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-dr-alb-${var.environment}"
  }
}

# Backup automation with Lambda
resource "aws_lambda_function" "dr_backup" {
  count = var.enable_disaster_recovery ? 1 : 0

  function_name = "${var.project_name}-dr-backup-${var.environment}"
  role          = aws_iam_role.dr_backup_role[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 900

  filename         = data.archive_file.dr_backup_zip[0].output_path
  source_code_hash = data.archive_file.dr_backup_zip[0].output_base64sha256

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      PROJECT_NAME   = var.project_name
      DR_REGION      = var.dr_region
      PRIMARY_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-dr-backup-${var.environment}"
  }
}

data "archive_file" "dr_backup_zip" {
  count = var.enable_disaster_recovery ? 1 : 0

  type        = "zip"
  output_path = "/tmp/dr_backup.zip"
  source {
    content = templatefile("${path.module}/lambda/dr_backup.py", {
      environment  = var.environment
      project_name = var.project_name
      dr_region    = var.dr_region
    })
    filename = "index.py"
  }
}

# IAM role for DR backup Lambda
resource "aws_iam_role" "dr_backup_role" {
  count = var.enable_disaster_recovery ? 1 : 0

  name = "${var.project_name}-dr-backup-role-${var.environment}"

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

resource "aws_iam_role_policy" "dr_backup_policy" {
  count = var.enable_disaster_recovery ? 1 : 0

  name = "${var.project_name}-dr-backup-policy-${var.environment}"
  role = aws_iam_role.dr_backup_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:CopyDBSnapshot",
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:CopyObject"
        ]
        Resource = [
          aws_s3_bucket.aeims_assets.arn,
          "${aws_s3_bucket.aeims_assets.arn}/*",
          aws_s3_bucket.aeims_dr_backups[0].arn,
          "${aws_s3_bucket.aeims_dr_backups[0].arn}/*"
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

# SNS topic for DR notifications
resource "aws_sns_topic" "dr_notifications" {
  count = var.enable_disaster_recovery ? 1 : 0

  name = "${var.project_name}-dr-notifications-${var.environment}"

  tags = {
    Name = "${var.project_name}-dr-notifications-${var.environment}"
  }
}

resource "aws_sns_topic_subscription" "dr_email_notification" {
  count = var.enable_disaster_recovery && var.dr_notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.dr_notifications[0].arn
  protocol  = "email"
  endpoint  = var.dr_notification_email
}

# EventBridge rule for scheduled DR testing
resource "aws_cloudwatch_event_rule" "dr_test_schedule" {
  count = var.enable_disaster_recovery ? 1 : 0

  name                = "${var.project_name}-dr-test-${var.environment}"
  description         = "Scheduled disaster recovery testing"
  schedule_expression = var.dr_test_schedule

  tags = {
    Name = "${var.project_name}-dr-test-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "dr_test_target" {
  count = var.enable_disaster_recovery ? 1 : 0

  rule      = aws_cloudwatch_event_rule.dr_test_schedule[0].name
  target_id = "DrTestTarget"
  arn       = aws_lambda_function.dr_backup[0].arn

  input = jsonencode({
    action = "test"
  })
}

# Variables for disaster recovery
variable "enable_disaster_recovery" {
  description = "Enable disaster recovery capabilities"
  type        = bool
  default     = true
}

variable "dr_region" {
  description = "Disaster recovery region"
  type        = string
  default     = "us-east-1"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_subnet_count" {
  description = "Number of DR subnets"
  type        = number
  default     = 2
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "dr_notification_email" {
  description = "Email for DR notifications"
  type        = string
  default     = ""
}

variable "dr_test_schedule" {
  description = "Schedule for DR testing (cron expression)"
  type        = string
  default     = "cron(0 1 * * SUN *)" # Weekly on Sunday at 1 AM
}

# Outputs
output "dr_backup_bucket" {
  description = "DR backup bucket name"
  value       = var.enable_disaster_recovery ? aws_s3_bucket.aeims_dr_backups[0].bucket : null
}

output "dr_database_endpoints" {
  description = "DR database endpoints"
  value       = var.enable_disaster_recovery ? { for k, v in aws_db_instance.aeims_dr_databases : k => v.endpoint } : {}
  sensitive   = true
}

output "primary_health_check_id" {
  description = "Primary site health check ID"
  value       = var.enable_disaster_recovery && var.domain_name != "" ? aws_route53_health_check.aeims_primary_health[0].id : null
}