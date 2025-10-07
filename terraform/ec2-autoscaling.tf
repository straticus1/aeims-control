# AEIMS EC2 Auto Scaling Group Configuration
# Ubuntu-compatible infrastructure with Ansible integration
# Supports Docker build integration for regulatory compliance

# Ubuntu 22.04 LTS AMI data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "aeims_ec2_role" {
  name = "${var.project_name}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role-${var.environment}"
  }
}

# IAM Role Policy for EC2 instances
resource "aws_iam_role_policy" "aeims_ec2_policy" {
  name = "${var.project_name}-ec2-policy-${var.environment}"
  role = aws_iam_role.aeims_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:*",
          "ssmmessages:*",
          "ec2messages:*",
          "logs:*",
          "s3:GetObject",
          "s3:PutObject",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:RecordLifecycleActionHeartbeat"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "aeims_ec2_profile" {
  name = "${var.project_name}-ec2-profile-${var.environment}"
  role = aws_iam_role.aeims_ec2_role.name

  tags = {
    Name = "${var.project_name}-ec2-profile-${var.environment}"
  }
}

# Security Group for EC2 instances
resource "aws_security_group" "aeims_ec2_sg" {
  name_prefix = "${var.project_name}-ec2-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  # HTTP from ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # Main application port
  ingress {
    description     = "AEIMS Main Port"
    from_port       = 8080
    to_port         = 8080
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

  # React frontend
  ingress {
    description     = "React Frontend"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  # VoIP ports for Asterisk
  ingress {
    description = "SIP"
    from_port   = 5060
    to_port     = 5061
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RTP ports for voice
  ingress {
    description = "RTP"
    from_port   = 10000
    to_port     = 20000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  # Health check from ALB
  ingress {
    description     = "Health Check"
    from_port       = 80
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg-${var.environment}"
  }
}

# S3 Bucket for Docker images and deployment artifacts
resource "aws_s3_bucket" "aeims_deployment" {
  bucket = "${var.project_name}-deployment-${var.environment}-${random_id.deployment_suffix.hex}"

  tags = {
    Name = "${var.project_name}-deployment-${var.environment}"
  }
}

resource "random_id" "deployment_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "aeims_deployment_versioning" {
  bucket = aws_s3_bucket.aeims_deployment.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aeims_deployment_encryption" {
  bucket = aws_s3_bucket.aeims_deployment.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.aeims_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# User Data Script for Ubuntu instances with Ansible integration
locals {
  user_data = base64encode(templatefile("${path.module}/user-data/ubuntu-bootstrap-fixed.sh", {
    project_name      = var.project_name
    environment       = var.environment
    ansible_playbook  = "deploy.yml"
    s3_bucket        = aws_s3_bucket.aeims_deployment.bucket
    ecr_repositories = aws_ecr_repository.aeims_repositories
    aws_region       = var.aws_region
  }))
}

# Launch Template
resource "aws_launch_template" "aeims_template" {
  name_prefix   = "${var.project_name}-template-${var.environment}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.ec2_instance_type

  vpc_security_group_ids = [aws_security_group.aeims_ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.aeims_ec2_profile.name
  }

  user_data = local.user_data

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.ec2_volume_size
      volume_type          = "gp3"
      encrypted            = true
      kms_key_id          = aws_kms_key.aeims_key.arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-instance-${var.environment}"
      Environment = var.environment
      Project     = var.project_name
      OS          = "Ubuntu"
      ManagedBy   = "Terraform"
    }
  }

  tags = {
    Name = "${var.project_name}-template-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Target Group for ALB
resource "aws_lb_target_group" "aeims_ec2_tg" {
  name     = "${var.project_name}-ec2-tg-${var.environment}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.aeims_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  tags = {
    Name = "${var.project_name}-ec2-tg-${var.environment}"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "aeims_asg" {
  name                = "${var.project_name}-asg-${var.environment}"
  vpc_zone_identifier = aws_subnet.private_subnets[*].id
  target_group_arns   = [aws_lb_target_group.aeims_ec2_tg.arn]

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.aeims_template.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 300
      checkpoint_delay      = 600
    }
    triggers = ["tag"]
  }

  dynamic "tag" {
    for_each = var.asg_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance-${var.environment}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener Rule for EC2 targets
resource "aws_lb_listener_rule" "aeims_ec2_rule" {
  listener_arn = aws_lb_listener.aeims_listener_http.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_ec2_tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = {
    Name = "${var.project_name}-ec2-listener-rule-${var.environment}"
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "aeims_scale_up" {
  name                   = "${var.project_name}-scale-up-${var.environment}"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.aeims_asg.name
}

resource "aws_autoscaling_policy" "aeims_scale_down" {
  name                   = "${var.project_name}-scale-down-${var.environment}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.aeims_asg.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "aeims_cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.aeims_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.aeims_asg.name
  }

  tags = {
    Name = "${var.project_name}-cpu-high-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "aeims_cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "25"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.aeims_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.aeims_asg.name
  }

  tags = {
    Name = "${var.project_name}-cpu-low-alarm-${var.environment}"
  }
}

# Variables for EC2 configuration
variable "ec2_instance_type" {
  description = "EC2 instance type for AEIMS application"
  type        = string
  default     = "t3.medium"
}

variable "ec2_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 30
}

variable "asg_min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 10
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_tags" {
  description = "Additional tags for Auto Scaling Group instances"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "AEIMS"
    OS          = "Ubuntu"
    ManagedBy   = "Terraform"
  }
}

# Outputs
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.aeims_asg.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.aeims_asg.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.aeims_template.id
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.aeims_ec2_tg.arn
}

output "deployment_bucket_name" {
  description = "Name of the S3 bucket for deployment artifacts"
  value       = aws_s3_bucket.aeims_deployment.bucket
}

output "ubuntu_ami_id" {
  description = "AMI ID used for Ubuntu instances"
  value       = data.aws_ami.ubuntu.id
}