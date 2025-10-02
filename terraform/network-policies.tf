# Network Security Policies for AEIMS
# Implements network segmentation and security controls

# Enhanced Security Groups with specific rules
resource "aws_security_group" "aeims_frontend_sg" {
  name_prefix = "${var.project_name}-frontend-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # HTTP/HTTPS from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Admin access only from specific IPs
  dynamic "ingress" {
    for_each = var.admin_cidr_blocks
    content {
      description = "Admin access"
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-frontend-sg-${var.environment}"
  }
}

resource "aws_security_group" "aeims_backend_sg" {
  name_prefix = "${var.project_name}-backend-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # Only allow access from frontend security group
  ingress {
    description     = "HTTP from frontend"
    from_port       = 8000
    to_port         = 8010
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_frontend_sg.id]
  }

  # Inter-service communication
  ingress {
    description = "Inter-service communication"
    from_port   = 8000
    to_port     = 8010
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg-${var.environment}"
  }
}

resource "aws_security_group" "aeims_database_sg" {
  name_prefix = "${var.project_name}-database-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # PostgreSQL from backend only
  ingress {
    description     = "PostgreSQL from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_backend_sg.id]
  }

  # MySQL from backend only
  ingress {
    description     = "MySQL from backend"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_backend_sg.id]
  }

  # Redis from backend only
  ingress {
    description     = "Redis from backend"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_backend_sg.id]
  }

  # Database backup access
  dynamic "ingress" {
    for_each = var.backup_cidr_blocks
    content {
      description = "Backup access"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-database-sg-${var.environment}"
  }
}

# Network ACLs for additional security
resource "aws_network_acl" "aeims_private_nacl" {
  vpc_id     = aws_vpc.aeims_vpc.id
  subnet_ids = aws_subnet.private_subnets[*].id

  # Allow inbound HTTP/HTTPS from public subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  # Allow AEIMS service ports
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 8000
    to_port    = 8010
  }

  # Allow ephemeral ports for responses
  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-private-nacl-${var.environment}"
  }
}

resource "aws_network_acl" "aeims_database_nacl" {
  vpc_id     = aws_vpc.aeims_vpc.id
  subnet_ids = aws_subnet.database_subnets[*].id

  # Allow database ports only from private subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = cidrsubnet(var.vpc_cidr, 8, 10) # Private subnet range
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = cidrsubnet(var.vpc_cidr, 8, 10)
    from_port  = 3306
    to_port    = 3306
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = cidrsubnet(var.vpc_cidr, 8, 10)
    from_port  = 6379
    to_port    = 6379
  }

  # Allow ephemeral ports for responses
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # Allow outbound to private subnets only
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-database-nacl-${var.environment}"
  }
}

# VPC Flow Logs for monitoring
resource "aws_flow_log" "aeims_vpc_flow_log" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log_role[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.aeims_vpc.id

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-${var.environment}"
  }
}

resource "aws_iam_role" "flow_log_role" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name = "${var.project_name}-flow-log-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log_policy" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  name = "${var.project_name}-flow-log-policy-${var.environment}"
  role = aws_iam_role.flow_log_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# DDoS Protection (Shield Advanced)
resource "aws_shield_protection" "aeims_alb_protection" {
  count = var.enable_shield_advanced ? 1 : 0

  name         = "${var.project_name}-alb-protection-${var.environment}"
  resource_arn = aws_lb.aeims_alb.arn
}

# GuardDuty for threat detection
resource "aws_guardduty_detector" "aeims_guardduty" {
  count = var.enable_guardduty ? 1 : 0

  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name = "${var.project_name}-guardduty-${var.environment}"
  }
}

# Variables
variable "admin_cidr_blocks" {
  description = "CIDR blocks for admin access"
  type        = list(string)
  default     = []
}

variable "backup_cidr_blocks" {
  description = "CIDR blocks for backup access"
  type        = list(string)
  default     = []
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "enable_shield_advanced" {
  description = "Enable AWS Shield Advanced"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

# Outputs
output "network_policy_security_group_ids" {
  description = "Network policy security group IDs"
  value = {
    frontend = aws_security_group.aeims_frontend_sg.id
    backend  = aws_security_group.aeims_backend_sg.id
    database = aws_security_group.aeims_database_sg.id
  }
}

output "network_acl_ids" {
  description = "Network ACL IDs"
  value = {
    private  = aws_network_acl.aeims_private_nacl.id
    database = aws_network_acl.aeims_database_nacl.id
  }
}