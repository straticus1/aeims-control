# EFS File Systems for AEIMS Persistent Storage
# Ensures sites, configurations, and nginx configs persist across ECS deployments

# EFS File System for AEIMS Sites Content
resource "aws_efs_file_system" "aeims_sites" {
  creation_token = "${var.project_name}-sites-${var.environment}"
  encrypted      = true
  kms_key_id     = aws_kms_key.aeims_key.arn

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-sites-efs-${var.environment}"
    Environment = var.environment
    Purpose     = "aeims-sites-storage"
  }
}

# EFS File System for AEIMS Data/Configuration
resource "aws_efs_file_system" "aeims_data" {
  creation_token = "${var.project_name}-data-${var.environment}"
  encrypted      = true
  kms_key_id     = aws_kms_key.aeims_key.arn

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-data-efs-${var.environment}"
    Environment = var.environment
    Purpose     = "aeims-config-storage"
  }
}

# EFS File System for Nginx Configurations
resource "aws_efs_file_system" "aeims_nginx" {
  creation_token = "${var.project_name}-nginx-${var.environment}"
  encrypted      = true
  kms_key_id     = aws_kms_key.aeims_key.arn

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-nginx-efs-${var.environment}"
    Environment = var.environment
    Purpose     = "nginx-config-storage"
  }
}

# EFS Mount Targets for Sites (one per subnet)
resource "aws_efs_mount_target" "aeims_sites_mount" {
  count = length(aws_subnet.private_subnets)

  file_system_id  = aws_efs_file_system.aeims_sites.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.aeims_efs_sg.id]
}

# EFS Mount Targets for Data (one per subnet)
resource "aws_efs_mount_target" "aeims_data_mount" {
  count = length(aws_subnet.private_subnets)

  file_system_id  = aws_efs_file_system.aeims_data.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.aeims_efs_sg.id]
}

# EFS Mount Targets for Nginx (one per subnet)
resource "aws_efs_mount_target" "aeims_nginx_mount" {
  count = length(aws_subnet.private_subnets)

  file_system_id  = aws_efs_file_system.aeims_nginx.id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.aeims_efs_sg.id]
}

# Security Group for EFS
resource "aws_security_group" "aeims_efs_sg" {
  name_prefix = "${var.project_name}-efs-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id
  description = "Security group for AEIMS EFS file systems"

  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-efs-sg-${var.environment}"
    Environment = var.environment
  }
}

# EFS Access Points for better isolation and management

# Access Point for Sites Directory
resource "aws_efs_access_point" "aeims_sites_ap" {
  file_system_id = aws_efs_file_system.aeims_sites.id

  root_directory {
    path = "/sites"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = {
    Name        = "${var.project_name}-sites-access-point-${var.environment}"
    Environment = var.environment
  }
}

# Access Point for Data Directory
resource "aws_efs_access_point" "aeims_data_ap" {
  file_system_id = aws_efs_file_system.aeims_data.id

  root_directory {
    path = "/data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = {
    Name        = "${var.project_name}-data-access-point-${var.environment}"
    Environment = var.environment
  }
}

# Access Point for Nginx Config Directory
resource "aws_efs_access_point" "aeims_nginx_ap" {
  file_system_id = aws_efs_file_system.aeims_nginx.id

  root_directory {
    path = "/nginx"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = {
    Name        = "${var.project_name}-nginx-access-point-${var.environment}"
    Environment = var.environment
  }
}

# Backup policy for EFS (optional but recommended for production)
resource "aws_efs_backup_policy" "aeims_sites_backup" {
  file_system_id = aws_efs_file_system.aeims_sites.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_backup_policy" "aeims_data_backup" {
  file_system_id = aws_efs_file_system.aeims_data.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_backup_policy" "aeims_nginx_backup" {
  file_system_id = aws_efs_file_system.aeims_nginx.id

  backup_policy {
    status = "ENABLED"
  }
}

# Outputs for reference
output "efs_file_system_ids" {
  description = "EFS file system IDs"
  value = {
    sites = aws_efs_file_system.aeims_sites.id
    data  = aws_efs_file_system.aeims_data.id
    nginx = aws_efs_file_system.aeims_nginx.id
  }
}

output "efs_access_point_ids" {
  description = "EFS access point IDs"
  value = {
    sites = aws_efs_access_point.aeims_sites_ap.id
    data  = aws_efs_access_point.aeims_data_ap.id
    nginx = aws_efs_access_point.aeims_nginx_ap.id
  }
}
