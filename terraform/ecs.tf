# ECS Configuration for AEIMS Services
# This module creates and manages ECS clusters and services for all AEIMS components

# ECS Cluster
resource "aws_ecs_cluster" "aeims_cluster" {
  name = "${var.project_name}-cluster-${var.environment}"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.aeims_key.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.aeims_logs["system"].name
      }
    }
  }

  dynamic "setting" {
    for_each = var.ecs_cluster_settings.insights_enabled ? [1] : []
    content {
      name  = "containerInsights"
      value = "enabled"
    }
  }

  tags = {
    Name = "${var.project_name}-cluster-${var.environment}"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "aeims_cluster_capacity" {
  cluster_name = aws_ecs_cluster.aeims_cluster.name

  capacity_providers = var.ecs_cluster_settings.capacity_providers

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# RDS Databases
resource "aws_db_instance" "aeims_databases" {
  for_each = var.database_configs

  identifier = "${var.project_name}-${replace(each.key, "_", "-")}-${var.environment}"

  engine                = each.value.engine
  engine_version        = each.value.engine_version
  instance_class        = each.value.instance_class
  allocated_storage     = each.value.allocated_storage
  max_allocated_storage = each.value.max_allocated_storage
  storage_encrypted     = each.value.storage_encrypted

  db_name  = "${var.project_name}_${replace(each.key, "-", "_")}"
  username = "admin"
  password = lookup(var.database_passwords, each.key, "temp-password-${random_password.db_passwords[each.key].result}")

  vpc_security_group_ids = [aws_security_group.aeims_db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.aeims_db_subnet_group.name

  backup_retention_period = each.value.backup_retention_days
  backup_window           = each.value.backup_window
  maintenance_window      = each.value.maintenance_window

  multi_az            = each.value.multi_az
  publicly_accessible = each.value.publicly_accessible

  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${each.key}-final-snapshot-${var.environment}" : null

  kms_key_id = each.value.storage_encrypted ? aws_kms_key.aeims_key.arn : null

  tags = {
    Name        = "${var.project_name}-${each.key}-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# Generate random passwords for databases
resource "random_password" "db_passwords" {
  for_each = var.database_configs

  length  = 16
  special = true
}

# ElastiCache Redis instances
resource "aws_elasticache_cluster" "aeims_redis" {
  for_each = var.elasticache_configs

  cluster_id           = "${var.project_name}-${replace(each.key, "_", "-")}-${var.environment}"
  engine               = "redis"
  node_type            = each.value.node_type
  num_cache_nodes      = each.value.num_cache_nodes
  parameter_group_name = each.value.parameter_group_name
  port                 = each.value.port
  subnet_group_name    = aws_elasticache_subnet_group.aeims_cache_subnet_group.name
  security_group_ids   = [aws_security_group.aeims_db_sg.id]
  engine_version       = each.value.engine_version
  apply_immediately    = each.value.apply_immediately

  tags = {
    Name        = "${var.project_name}-${each.key}-redis-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# Store database connection strings in Systems Manager
resource "aws_ssm_parameter" "database_urls" {
  for_each = var.database_configs

  name  = "/aeims/${var.environment}/${each.key}/database_url"
  type  = "SecureString"
  value = "${each.value.engine}://admin:${random_password.db_passwords[each.key].result}@${aws_db_instance.aeims_databases[each.key].endpoint}/${var.project_name}_${replace(each.key, "-", "_")}"

  depends_on = [aws_db_instance.aeims_databases]

  tags = {
    Name        = "${var.project_name}-${each.key}-db-url-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# Store Redis connection strings in Systems Manager
resource "aws_ssm_parameter" "redis_urls" {
  for_each = aws_elasticache_cluster.aeims_redis

  name  = "/aeims/${var.environment}/${each.key}/redis_url"
  type  = "SecureString"
  value = "redis://${each.value.cache_nodes[0].address}:${each.value.cache_nodes[0].port}"

  tags = {
    Name        = "${var.project_name}-${each.key}-redis-url-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "aeims_services" {
  for_each = var.ecs_service_configs

  family                   = "${var.project_name}-${each.key}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.aeims_task_execution_role.arn
  task_role_arn            = aws_iam_role.aeims_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = "${aws_ecr_repository.aeims_repositories[replace(each.key, "_", "-")].repository_url}:latest"

      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      environment = concat(
        [
          {
            name  = "ENVIRONMENT"
            value = var.environment
          },
          {
            name  = "SERVICE_NAME"
            value = each.key
          },
          {
            name  = "AWS_REGION"
            value = var.aws_region
          }
        ],
        # Service-specific environment variables
        each.key == "aeims_core" ? [
          {
            name  = "PORT"
            value = tostring(each.value.port)
          }
          ] : each.key == "aeims_app" ? [
          {
            name  = "APACHE_DOCUMENT_ROOT"
            value = "/var/www/aeims"
          }
          ] : each.key == "aeims_lib" ? [
          {
            name  = "WEBSOCKET_PORT"
            value = tostring(each.value.port)
          }
          ] : [
          {
            name  = "SERVICE_PORT"
            value = tostring(each.value.port)
          }
        ]
      )

      secrets = concat(
        # Database secrets for services that need them
        contains(keys(var.database_configs), replace(each.key, "_", "-")) ? [
          {
            name      = "DATABASE_USERNAME"
            valueFrom = "${aws_secretsmanager_secret.database_secrets[replace(each.key, "_", "-")].arn}:username::"
          },
          {
            name      = "DATABASE_PASSWORD"
            valueFrom = "${aws_secretsmanager_secret.database_secrets[replace(each.key, "_", "-")].arn}:password::"
          },
          {
            name      = "DATABASE_URL"
            valueFrom = "${aws_secretsmanager_secret.database_secrets[replace(each.key, "_", "-")].arn}:url::"
          }
        ] : [],
        # Redis secrets for all services
        contains(keys(var.elasticache_configs), replace(each.key, "_", "-")) ? [
          {
            name      = "REDIS_PASSWORD"
            valueFrom = "${aws_secretsmanager_secret.redis_secrets[replace(each.key, "_", "-")].arn}:password::"
          },
          {
            name      = "REDIS_URL"
            valueFrom = "${aws_secretsmanager_secret.redis_secrets[replace(each.key, "_", "-")].arn}:url::"
          }
        ] : [],
        # Application secrets for all services
        [
          {
            name      = "JWT_SECRET"
            valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:jwt_secret::"
          },
          {
            name      = "API_KEY"
            valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:api_key::"
          },
          {
            name      = "ENCRYPTION_KEY"
            valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:encryption_key::"
          }
        ]
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.aeims_logs[replace(each.key, "_", "-")].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}${each.value.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name        = "${var.project_name}-${each.key}-task-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# ECS Services
resource "aws_ecs_service" "aeims_services" {
  for_each = var.ecs_service_configs

  name            = "${var.project_name}-${each.key}-${var.environment}"
  cluster         = aws_ecs_cluster.aeims_cluster.id
  task_definition = aws_ecs_task_definition.aeims_services[each.key].arn
  desired_count   = each.value.count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.aeims_app_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.aeims_targets[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  depends_on = [
    aws_lb_listener.aeims_listener_http,
    aws_iam_role_policy_attachment.aeims_task_execution_role_policy
  ]

  tags = {
    Name        = "${var.project_name}-${each.key}-service-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# Target Groups for Load Balancer
resource "aws_lb_target_group" "aeims_targets" {
  for_each = var.ecs_service_configs

  name        = "${substr(replace("${var.project_name}-${replace(each.key, "_", "-")}-${var.environment}", "_", "-"), 0, 32)}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.aeims_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = each.value.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-${each.key}-tg-${var.environment}"
    Service     = each.key
    Environment = var.environment
  }
}

# Load Balancer Listener (HTTP)
resource "aws_lb_listener" "aeims_listener_http" {
  load_balancer_arn = aws_lb.aeims_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Load Balancer Listener (HTTPS) - conditional
resource "aws_lb_listener" "aeims_listener_https" {
  count = var.certificate_arn != "" || length(var.additional_domains) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.aeims_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : (
    length(aws_acm_certificate_validation.domain_validations) > 0 ? 
    values(aws_acm_certificate_validation.domain_validations)[0].certificate_arn : null
  )

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_targets["aeims_app"].arn
  }
}

# Additional certificate attachments for multiple domains
resource "aws_lb_listener_certificate" "additional_certificates" {
  for_each = {
    for domain_key in keys(aws_acm_certificate_validation.domain_validations) : domain_key => var.additional_domains[domain_key]
  }

  listener_arn    = aws_lb_listener.aeims_listener_https[0].arn
  certificate_arn = aws_acm_certificate_validation.domain_validations[each.key].certificate_arn

  depends_on = [
    aws_lb_listener.aeims_listener_https,
    aws_acm_certificate_validation.domain_validations
  ]
}

# Listener Rules for routing
resource "aws_lb_listener_rule" "aeims_core_rule" {
  listener_arn = (var.certificate_arn != "" || length(var.additional_domains) > 0) ? aws_lb_listener.aeims_listener_https[0].arn : aws_lb_listener.aeims_listener_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_targets["aeims_core"].arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/telephony/*", "/calls/*"]
    }
  }
}

resource "aws_lb_listener_rule" "aeims_lib_rule" {
  listener_arn = (var.certificate_arn != "" || length(var.additional_domains) > 0) ? aws_lb_listener.aeims_listener_https[0].arn : aws_lb_listener.aeims_listener_http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_targets["aeims_lib"].arn
  }

  condition {
    path_pattern {
      values = ["/ws/*", "/device/*", "/control/*"]
    }
  }
}

# Service-specific routing rules
resource "aws_lb_listener_rule" "microservice_rules" {
  for_each = {
    user_service         = { path = "/users/*", priority = 300 }
    billing_service      = { path = "/billing/*", priority = 400 }
    call_service         = { path = "/calls/*", priority = 500 }
    operator_service     = { path = "/operators/*", priority = 600 }
    conference_service   = { path = "/conference/*", priority = 700 }
    notification_service = { path = "/notifications/*", priority = 800 }
    analytics_service    = { path = "/analytics/*", priority = 900 }
  }

  listener_arn = (var.certificate_arn != "" || length(var.additional_domains) > 0) ? aws_lb_listener.aeims_listener_https[0].arn : aws_lb_listener.aeims_listener_http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_targets[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

# Domain-specific routing rules for additional domains
resource "aws_lb_listener_rule" "domain_specific_rules" {
  for_each = {
    for domain_key, domain_config in var.additional_domains : domain_key => domain_config
    if var.certificate_arn != "" || length(var.additional_domains) > 0
  }

  listener_arn = aws_lb_listener.aeims_listener_https[0].arn
  priority     = 1000 + index(keys(var.additional_domains), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aeims_targets["aeims_app"].arn
  }

  condition {
    host_header {
      values = concat([each.value.domain_name], each.value.sans)
    }
  }

  depends_on = [
    aws_lb_listener.aeims_listener_https,
    aws_lb_listener_certificate.additional_certificates
  ]
}

# Auto Scaling for ECS Services
resource "aws_appautoscaling_target" "aeims_scaling_targets" {
  for_each = var.auto_scaling_configs

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${aws_ecs_cluster.aeims_cluster.name}/${aws_ecs_service.aeims_services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "aeims_scale_up_cpu" {
  for_each = var.auto_scaling_configs

  name               = "${var.project_name}-${each.key}-scale-up-cpu-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aeims_scaling_targets[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_scaling_targets[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_scaling_targets[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = each.value.target_cpu
    scale_in_cooldown  = each.value.scale_down_cooldown
    scale_out_cooldown = each.value.scale_up_cooldown
  }
}

resource "aws_appautoscaling_policy" "aeims_scale_up_memory" {
  for_each = var.auto_scaling_configs

  name               = "${var.project_name}-${each.key}-scale-up-memory-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aeims_scaling_targets[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_scaling_targets[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_scaling_targets[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = each.value.target_memory
    scale_in_cooldown  = each.value.scale_down_cooldown
    scale_out_cooldown = each.value.scale_up_cooldown
  }
}

# Output values
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.aeims_cluster.name
}

output "ecs_service_names" {
  description = "Names of the ECS services"
  value       = { for k, v in aws_ecs_service.aeims_services : k => v.name }
}

output "database_endpoints" {
  description = "Database connection endpoints"
  value       = { for k, v in aws_db_instance.aeims_databases : k => v.endpoint }
  sensitive   = true
}

output "redis_endpoints" {
  description = "Redis connection endpoints"
  value       = { for k, v in aws_elasticache_cluster.aeims_redis : k => "${v.cache_nodes[0].address}:${v.cache_nodes[0].port}" }
  sensitive   = true
}
