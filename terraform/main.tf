# AEIMS Infrastructure Management System
# Terraform configuration for deploying AEIMS ecosystem
# Compatible with SuperDeploy deployment system

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    # Backend configuration will be provided via backend config file or CLI
    # This prevents circular dependency with variables
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AEIMS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "AfterDarkSystems"
    }
  }
}

# Configure Docker Provider
provider "docker" {
  host = var.docker_host
}

# Local provider for file generation
provider "local" {}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Configure Kubernetes Provider
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Main VPC
resource "aws_vpc" "aeims_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc-${var.environment}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "aeims_igw" {
  vpc_id = aws_vpc.aeims_vpc.id

  tags = {
    Name = "${var.project_name}-igw-${var.environment}"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count             = var.public_subnet_count
  vpc_id            = aws_vpc.aeims_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}-${var.environment}"
    Type = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.aeims_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}-${var.environment}"
    Type = "Private"
  }
}

# Database Subnets
resource "aws_subnet" "database_subnets" {
  count             = var.database_subnet_count
  vpc_id            = aws_vpc.aeims_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-db-subnet-${count.index + 1}-${var.environment}"
    Type = "Database"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.aeims_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aeims_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt-${var.environment}"
  }
}

resource "aws_route_table" "private_rt" {
  count  = var.private_subnet_count
  vpc_id = aws_vpc.aeims_vpc.id

  tags = {
    Name = "${var.project_name}-private-rt-${count.index + 1}-${var.environment}"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta" {
  count          = var.public_subnet_count
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count          = var.private_subnet_count
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

# NAT Gateways
resource "aws_eip" "nat_gateway_eips" {
  count  = var.enable_nat_gateway ? var.private_subnet_count : 0
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index + 1}-${var.environment}"
  }

  depends_on = [aws_internet_gateway.aeims_igw]
}

resource "aws_nat_gateway" "nat_gateways" {
  count         = var.enable_nat_gateway ? var.private_subnet_count : 0
  allocation_id = aws_eip.nat_gateway_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "${var.project_name}-nat-gw-${count.index + 1}-${var.environment}"
  }

  depends_on = [aws_internet_gateway.aeims_igw]
}

# Update private route tables with NAT Gateway routes
resource "aws_route" "private_nat_routes" {
  count                  = var.enable_nat_gateway ? var.private_subnet_count : 0
  route_table_id         = aws_route_table.private_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateways[count.index].id
}

# Security Groups
resource "aws_security_group" "aeims_alb_sg" {
  name_prefix = "${var.project_name}-alb-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg-${var.environment}"
  }
}

resource "aws_security_group" "aeims_app_sg" {
  name_prefix = "${var.project_name}-app-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # HTTP from ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # AEIMS Core services ports
  ingress {
    description     = "AEIMS Core Services"
    from_port       = 8000
    to_port         = 8010
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # AeimsLib WebSocket
  ingress {
    description     = "AeimsLib WebSocket"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # React frontend
  ingress {
    description     = "React Frontend"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg-${var.environment}"
  }
}

resource "aws_security_group" "aeims_db_sg" {
  name_prefix = "${var.project_name}-db-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # PostgreSQL
  ingress {
    description     = "PostgreSQL"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  # MySQL
  ingress {
    description     = "MySQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  # Redis
  ingress {
    description     = "Redis"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg-${var.environment}"
  }
}

# Application Load Balancer
resource "aws_lb" "aeims_alb" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.aeims_alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = var.environment == "prod" ? true : false

  tags = {
    Name = "${var.project_name}-alb-${var.environment}"
  }
}

# Database Subnet Group
resource "aws_db_subnet_group" "aeims_db_subnet_group" {
  name       = "${var.project_name}-db-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.database_subnets[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group-${var.environment}"
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "aeims_cache_subnet_group" {
  name       = "${var.project_name}-cache-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.database_subnets[*].id
}

# ECR Repositories for Docker images
resource "aws_ecr_repository" "aeims_repositories" {
  for_each = var.ecr_repositories

  name                 = "${var.project_name}-${each.key}-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "${var.project_name}-${each.key}-${var.environment}"
    Service = each.key
  }
}

# KMS Key for encryption
resource "aws_kms_key" "aeims_key" {
  description             = "KMS key for AEIMS ${var.environment} environment"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-kms-key-${var.environment}"
  }
}

resource "aws_kms_alias" "aeims_key_alias" {
  name          = "alias/${var.project_name}-key-${var.environment}"
  target_key_id = aws_kms_key.aeims_key.key_id
}

# S3 Bucket for application assets and backups
resource "aws_s3_bucket" "aeims_assets" {
  bucket = "${var.project_name}-assets-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-assets-${var.environment}"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "aeims_assets_versioning" {
  bucket = aws_s3_bucket.aeims_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aeims_assets_encryption" {
  bucket = aws_s3_bucket.aeims_assets.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.aeims_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "aeims_logs" {
  for_each = var.log_groups

  name              = "/aws/aeims/${var.environment}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-${each.key}-logs-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "aeims_task_execution_role" {
  name = "${var.project_name}-task-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-task-execution-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "aeims_task_execution_role_policy" {
  role       = aws_iam_role.aeims_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "aeims_task_execution_custom_policy" {
  name = "${var.project_name}-task-execution-custom-policy-${var.environment}"
  role = aws_iam_role.aeims_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      }
    ]
  })
}

# Output values for other modules
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.aeims_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "database_subnet_ids" {
  description = "IDs of the database subnets"
  value       = aws_subnet.database_subnets[*].id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.aeims_alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.aeims_alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.aeims_alb.zone_id
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb_sg = aws_security_group.aeims_alb_sg.id
    app_sg = aws_security_group.aeims_app_sg.id
    db_sg  = aws_security_group.aeims_db_sg.id
  }
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value = {
    for k, v in aws_ecr_repository.aeims_repositories : k => v.repository_url
  }
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for assets"
  value       = aws_s3_bucket.aeims_assets.bucket
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.aeims_key.key_id
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.aeims_task_execution_role.arn
}

output "db_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = aws_db_subnet_group.aeims_db_subnet_group.name
}

output "cache_subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.aeims_cache_subnet_group.name
}
