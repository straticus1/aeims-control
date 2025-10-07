# Variables for AEIMS Infrastructure Management System

# General Configuration
variable "project_name" {
  description = "Name of the AEIMS project"
  type        = string
  default     = "aeims"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "tf_state_bucket" {
  description = "S3 bucket for storing Terraform state"
  type        = string
  default     = "aeims-terraform-state-dev"
}

variable "docker_host" {
  description = "Docker daemon host"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_count" {
  description = "Number of public subnets"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets"
  type        = number
  default     = 2
}

variable "database_subnet_count" {
  description = "Number of database subnets"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateways for private subnets"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# ECR Repositories
variable "ecr_repositories" {
  description = "ECR repositories to create for AEIMS services"
  type        = set(string)
  default = [
    "aeims-core",
    "aeims-app",
    "aeims-lib",
    "user-service",
    "billing-service",
    "call-service",
    "operator-service",
    "conference-service",
    "notification-service",
    "analytics-service",
    "frontend",
    "nginx"
  ]
}

# Logging Configuration
variable "log_groups" {
  description = "CloudWatch log groups to create"
  type        = set(string)
  default = [
    "aeims-core",
    "aeims-app",
    "aeims-lib",
    "user-service",
    "billing-service",
    "call-service",
    "operator-service",
    "conference-service",
    "notification-service",
    "analytics-service",
    "frontend",
    "nginx",
    "system",
    "logstash"
  ]
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Database Configuration
variable "database_configs" {
  description = "Database configuration for different AEIMS components"
  type = map(object({
    engine                = string
    engine_version        = string
    instance_class        = string
    allocated_storage     = number
    max_allocated_storage = number
    storage_encrypted     = bool
    backup_retention_days = number
    backup_window         = string
    maintenance_window    = string
    multi_az              = bool
    publicly_accessible   = bool
  }))
  default = {
    aeims_core = {
      engine                = "postgres"
      engine_version        = "14.19"
      instance_class        = "db.t3.micro"
      allocated_storage     = 20
      max_allocated_storage = 100
      storage_encrypted     = true
      backup_retention_days = 7
      backup_window         = "03:00-04:00"
      maintenance_window    = "sun:04:00-sun:05:00"
      multi_az              = false
      publicly_accessible   = false
    }
    aeims_app = {
      engine                = "mysql"
      engine_version        = "8.0.43"
      instance_class        = "db.t3.micro"
      allocated_storage     = 20
      max_allocated_storage = 100
      storage_encrypted     = true
      backup_retention_days = 7
      backup_window         = "03:00-04:00"
      maintenance_window    = "sun:04:00-sun:05:00"
      multi_az              = false
      publicly_accessible   = false
    }
  }
}

# ElastiCache Configuration  
variable "elasticache_configs" {
  description = "ElastiCache configuration for Redis instances"
  type = map(object({
    node_type            = string
    port                 = number
    parameter_group_name = string
    num_cache_nodes      = number
    engine_version       = string
    apply_immediately    = bool
  }))
  default = {
    aeims_core = {
      node_type            = "cache.t3.micro"
      port                 = 6379
      parameter_group_name = "default.redis7"
      num_cache_nodes      = 1
      engine_version       = "7.0"
      apply_immediately    = true
    }
    aeims_app = {
      node_type            = "cache.t3.micro"
      port                 = 6379
      parameter_group_name = "default.redis7"
      num_cache_nodes      = 1
      engine_version       = "7.0"
      apply_immediately    = true
    }
    aeims_lib = {
      node_type            = "cache.t3.micro"
      port                 = 6379
      parameter_group_name = "default.redis7"
      num_cache_nodes      = 1
      engine_version       = "7.0"
      apply_immediately    = true
    }
  }
}

# ECS Configuration
variable "ecs_cluster_settings" {
  description = "ECS cluster settings"
  type = object({
    name               = string
    capacity_providers = list(string)
    insights_enabled   = bool
  })
  default = {
    name               = "aeims-cluster"
    capacity_providers = ["FARGATE", "FARGATE_SPOT"]
    insights_enabled   = true
  }
}

variable "ecs_service_configs" {
  description = "ECS service configurations"
  type = map(object({
    cpu               = number
    memory            = number
    port              = number
    count             = number
    health_check_path = string
  }))
  default = {
    aeims_core = {
      cpu               = 512
      memory            = 1024
      port              = 8000
      count             = 1
      health_check_path = "/health"
    }
    aeims_app = {
      cpu               = 256
      memory            = 512
      port              = 80
      count             = 1
      health_check_path = "/"
    }
    aeims_lib = {
      cpu               = 256
      memory            = 512
      port              = 8080
      count             = 1
      health_check_path = "/health"
    }
    user_service = {
      cpu               = 256
      memory            = 512
      port              = 8001
      count             = 1
      health_check_path = "/health"
    }
    billing_service = {
      cpu               = 256
      memory            = 512
      port              = 8002
      count             = 1
      health_check_path = "/health"
    }
    call_service = {
      cpu               = 256
      memory            = 512
      port              = 8003
      count             = 1
      health_check_path = "/health"
    }
    operator_service = {
      cpu               = 256
      memory            = 512
      port              = 8004
      count             = 1
      health_check_path = "/health"
    }
    conference_service = {
      cpu               = 256
      memory            = 512
      port              = 8005
      count             = 1
      health_check_path = "/health"
    }
    notification_service = {
      cpu               = 256
      memory            = 512
      port              = 8006
      count             = 1
      health_check_path = "/health"
    }
    analytics_service = {
      cpu               = 256
      memory            = 512
      port              = 8007
      count             = 1
      health_check_path = "/health"
    }
    frontend = {
      cpu               = 256
      memory            = 512
      port              = 3000
      count             = 1
      health_check_path = "/"
    }
  }
}

# Certificate Configuration
variable "domain_name" {
  description = "Primary domain name for AEIMS deployment"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "Primary ACM certificate ARN for HTTPS"
  type        = string
  default     = ""
}

variable "additional_domains" {
  description = "Additional domains for SSL certificates"
  type = map(object({
    domain_name = string
    sans        = list(string)  # Subject Alternative Names
  }))
  default = {
    nycflirts = {
      domain_name = "nycflirts.com"
      sans        = ["www.nycflirts.com"]
    }
    flirtsnyc = {
      domain_name = "flirts.nyc"
      sans        = ["www.flirts.nyc"]
    }
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring with CloudWatch, Prometheus, and Grafana"
  type        = bool
  default     = true
}

variable "monitoring_configs" {
  description = "Monitoring service configurations"
  type = object({
    prometheus = object({
      retention_days = number
      storage_size   = string
    })
    grafana = object({
      admin_password = string
      storage_size   = string
    })
  })
  default = {
    prometheus = {
      retention_days = 15
      storage_size   = "20Gi"
    }
    grafana = {
      admin_password = "admin123"
      storage_size   = "10Gi"
    }
  }
  sensitive = true
}

# Secrets Configuration
variable "database_passwords" {
  description = "Database passwords for AEIMS services"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "redis_passwords" {
  description = "Redis passwords for AEIMS services"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Scaling Configuration
variable "auto_scaling_configs" {
  description = "Auto scaling configuration for ECS services"
  type = map(object({
    min_capacity        = number
    max_capacity        = number
    target_cpu          = number
    target_memory       = number
    scale_up_cooldown   = number
    scale_down_cooldown = number
  }))
  default = {
    aeims_core = {
      min_capacity        = 1
      max_capacity        = 10
      target_cpu          = 70
      target_memory       = 80
      scale_up_cooldown   = 300
      scale_down_cooldown = 300
    }
    aeims_app = {
      min_capacity        = 1
      max_capacity        = 5
      target_cpu          = 70
      target_memory       = 80
      scale_up_cooldown   = 300
      scale_down_cooldown = 300
    }
    aeims_lib = {
      min_capacity        = 1
      max_capacity        = 5
      target_cpu          = 70
      target_memory       = 80
      scale_up_cooldown   = 300
      scale_down_cooldown = 300
    }
  }
}

# Backup Configuration
variable "backup_configs" {
  description = "Backup configuration for databases and storage"
  type = object({
    database_backup_retention = number
    s3_backup_retention       = number
    backup_schedule           = string
    backup_window             = string
  })
  default = {
    database_backup_retention = 7
    s3_backup_retention       = 30
    backup_schedule           = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
    backup_window             = "02:00-03:00"
  }
}

# Feature Flags
variable "feature_flags" {
  description = "Feature flags for enabling/disabling components"
  type = object({
    enable_aeims_core = bool
    enable_aeims_app  = bool
    enable_aeims_lib  = bool
    enable_monitoring = bool
    enable_backup     = bool
    enable_ssl        = bool
    enable_waf        = bool
  })
  default = {
    enable_aeims_core = true
    enable_aeims_app  = true
    enable_aeims_lib  = true
    enable_monitoring = true
    enable_backup     = true
    enable_ssl        = false
    enable_waf        = false
  }
}
