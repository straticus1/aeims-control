# AWS Secrets Manager Configuration for AEIMS
# Manages all sensitive configuration data securely

# Database secrets
resource "aws_secretsmanager_secret" "database_secrets" {
  for_each = var.database_configs

  name        = "${var.project_name}/${var.environment}/${each.key}/database"
  description = "Database credentials for ${each.key} in ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-${each.key}-db-secret-${var.environment}"
    Service     = each.key
    Environment = var.environment
    Type        = "Database"
  }
}

resource "aws_secretsmanager_secret_version" "database_secrets" {
  for_each = var.database_configs

  secret_id = aws_secretsmanager_secret.database_secrets[each.key].id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.db_passwords[each.key].result
    engine   = each.value.engine
    host     = aws_db_instance.aeims_databases[each.key].endpoint
    port     = each.value.engine == "postgres" ? 5432 : 3306
    dbname   = "${var.project_name}_${replace(each.key, "-", "_")}"
    url      = "${each.value.engine}://admin:${random_password.db_passwords[each.key].result}@${aws_db_instance.aeims_databases[each.key].endpoint}/${var.project_name}_${replace(each.key, "-", "_")}"
  })
}

# Redis secrets
resource "aws_secretsmanager_secret" "redis_secrets" {
  for_each = var.elasticache_configs

  name        = "${var.project_name}/${var.environment}/${each.key}/redis"
  description = "Redis credentials for ${each.key} in ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-${each.key}-redis-secret-${var.environment}"
    Service     = each.key
    Environment = var.environment
    Type        = "Redis"
  }
}

resource "aws_secretsmanager_secret_version" "redis_secrets" {
  for_each = var.elasticache_configs

  secret_id = aws_secretsmanager_secret.redis_secrets[each.key].id
  secret_string = jsonencode({
    password = random_password.redis_passwords[each.key].result
    host     = aws_elasticache_cluster.aeims_redis[each.key].cache_nodes[0].address
    port     = each.value.port
    url      = "redis://:${random_password.redis_passwords[each.key].result}@${aws_elasticache_cluster.aeims_redis[each.key].cache_nodes[0].address}:${each.value.port}"
  })
}

# Generate Redis passwords
resource "random_password" "redis_passwords" {
  for_each = var.elasticache_configs

  length  = 32
  special = true
}

# Application secrets
resource "aws_secretsmanager_secret" "application_secrets" {
  name        = "${var.project_name}/${var.environment}/application"
  description = "Application-level secrets for AEIMS ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-app-secrets-${var.environment}"
    Environment = var.environment
    Type        = "Application"
  }
}

resource "aws_secretsmanager_secret_version" "application_secrets" {
  secret_id = aws_secretsmanager_secret.application_secrets.id
  secret_string = jsonencode({
    jwt_secret          = random_password.jwt_secret.result
    api_key             = random_password.api_key.result
    webhook_secret      = random_password.webhook_secret.result
    encryption_key      = random_password.encryption_key.result
    admin_token         = random_password.admin_token.result
    freeswitch_password = var.freeswitch_password != "" ? var.freeswitch_password : "ClueCon"
  })
}

# Generate application secrets
resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "random_password" "webhook_secret" {
  length  = 32
  special = true
}

resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

resource "random_password" "admin_token" {
  length  = 48
  special = false
}

# Monitoring secrets
resource "aws_secretsmanager_secret" "monitoring_secrets" {
  count = var.enable_monitoring ? 1 : 0

  name        = "${var.project_name}/${var.environment}/monitoring"
  description = "Monitoring system secrets for AEIMS ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-monitoring-secrets-${var.environment}"
    Environment = var.environment
    Type        = "Monitoring"
  }
}

resource "aws_secretsmanager_secret_version" "monitoring_secrets" {
  count = var.enable_monitoring ? 1 : 0

  secret_id = aws_secretsmanager_secret.monitoring_secrets[0].id
  secret_string = jsonencode({
    grafana_admin_password = var.monitoring_configs.grafana.admin_password
    prometheus_auth_token  = random_password.prometheus_token[0].result
    alertmanager_webhook   = var.alertmanager_webhook != "" ? var.alertmanager_webhook : ""
  })
}

resource "random_password" "prometheus_token" {
  count = var.enable_monitoring ? 1 : 0

  length  = 32
  special = false
}

# SSL/TLS certificates (if provided)
resource "aws_secretsmanager_secret" "ssl_certificates" {
  count = var.certificate_content != "" ? 1 : 0

  name        = "${var.project_name}/${var.environment}/ssl"
  description = "SSL/TLS certificates for AEIMS ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-ssl-secret-${var.environment}"
    Environment = var.environment
    Type        = "SSL"
  }
}

resource "aws_secretsmanager_secret_version" "ssl_certificates" {
  count = var.certificate_content != "" ? 1 : 0

  secret_id = aws_secretsmanager_secret.ssl_certificates[0].id
  secret_string = jsonencode({
    certificate = var.certificate_content
    private_key = var.private_key_content
  })
}

# External API secrets
resource "aws_secretsmanager_secret" "external_secrets" {
  name        = "${var.project_name}/${var.environment}/external"
  description = "External service secrets for AEIMS ${var.environment}"

  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name        = "${var.project_name}-external-secrets-${var.environment}"
    Environment = var.environment
    Type        = "External"
  }
}

resource "aws_secretsmanager_secret_version" "external_secrets" {
  secret_id = aws_secretsmanager_secret.external_secrets.id
  secret_string = jsonencode({
    smtp_password     = var.smtp_password != "" ? var.smtp_password : ""
    slack_webhook_url = var.slack_webhook_url != "" ? var.slack_webhook_url : ""
    sentry_dsn        = var.sentry_dsn != "" ? var.sentry_dsn : ""
    twilio_auth_token = var.twilio_auth_token != "" ? var.twilio_auth_token : ""
  })
}

# IAM policy for ECS tasks to access secrets
resource "aws_iam_policy" "secrets_access" {
  name        = "${var.project_name}-secrets-access-${var.environment}"
  description = "Policy for AEIMS services to access Secrets Manager"

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
          for secret in concat(
            values(aws_secretsmanager_secret.database_secrets),
            values(aws_secretsmanager_secret.redis_secrets),
            [aws_secretsmanager_secret.application_secrets],
            aws_secretsmanager_secret.monitoring_secrets,
            aws_secretsmanager_secret.ssl_certificates,
            [aws_secretsmanager_secret.external_secrets]
          ) : secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.aeims_key.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.aeims_task_execution_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# Create a script for local secret retrieval (development)
resource "local_file" "get_secrets_script" {
  content = templatefile("${path.module}/templates/get-secrets.sh.tpl", {
    environment  = var.environment
    project_name = var.project_name
    aws_region   = var.aws_region
    secret_names = [
      for k, v in aws_secretsmanager_secret.database_secrets : v.name
    ]
  })
  filename        = "${path.module}/../scripts/get-secrets.sh"
  file_permission = "0755"
}

# Outputs (ARNs only, not actual secret values)
output "secret_arns" {
  description = "ARNs of all secrets created"
  value = {
    database_secrets    = { for k, v in aws_secretsmanager_secret.database_secrets : k => v.arn }
    redis_secrets       = { for k, v in aws_secretsmanager_secret.redis_secrets : k => v.arn }
    application_secrets = aws_secretsmanager_secret.application_secrets.arn
    monitoring_secrets  = var.enable_monitoring ? aws_secretsmanager_secret.monitoring_secrets[0].arn : null
    ssl_certificates    = var.certificate_content != "" ? aws_secretsmanager_secret.ssl_certificates[0].arn : null
    external_secrets    = aws_secretsmanager_secret.external_secrets.arn
  }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secret encryption"
  value       = aws_kms_key.aeims_key.arn
}

# Variable definitions for secrets
variable "freeswitch_password" {
  description = "FreeSWITCH password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_content" {
  description = "SSL certificate content"
  type        = string
  default     = ""
  sensitive   = true
}

variable "private_key_content" {
  description = "SSL private key content"
  type        = string
  default     = ""
  sensitive   = true
}

variable "smtp_password" {
  description = "SMTP password for email notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sentry_dsn" {
  description = "Sentry DSN for error tracking"
  type        = string
  default     = ""
  sensitive   = true
}

variable "twilio_auth_token" {
  description = "Twilio auth token for SMS/voice services"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alertmanager_webhook" {
  description = "Alertmanager webhook URL"
  type        = string
  default     = ""
  sensitive   = true
}