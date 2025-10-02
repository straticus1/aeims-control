# Enhanced Auto-scaling for AEIMS Services
# Implements predictive scaling, custom metrics, and advanced scaling policies

# Application Auto Scaling for ECS Services
resource "aws_appautoscaling_target" "aeims_enhanced_scaling" {
  for_each = var.enhanced_auto_scaling_configs

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${aws_ecs_cluster.aeims_cluster.name}/${aws_ecs_service.aeims_services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = {
    Name = "${var.project_name}-${each.key}-scaling-target-${var.environment}"
  }
}

# CPU-based scaling policy
resource "aws_appautoscaling_policy" "aeims_cpu_scaling" {
  for_each = var.enhanced_auto_scaling_configs

  name               = "${var.project_name}-${each.key}-cpu-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = each.value.target_cpu
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}

# Memory-based scaling policy
resource "aws_appautoscaling_policy" "aeims_memory_scaling" {
  for_each = var.enhanced_auto_scaling_configs

  name               = "${var.project_name}-${each.key}-memory-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = each.value.target_memory
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}

# Custom metrics scaling (e.g., active connections, queue length)
resource "aws_appautoscaling_policy" "aeims_custom_metrics_scaling" {
  for_each = {
    for service, config in var.enhanced_auto_scaling_configs : service => config
    if lookup(config, "custom_metric_name", "") != ""
  }

  name               = "${var.project_name}-${each.key}-custom-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = each.value.custom_metric_name
      namespace   = "AEIMS/Application"
      statistic   = "Average"

      dynamic "dimensions" {
        for_each = lookup(each.value, "custom_metric_dimensions", {})
        content {
          name  = dimensions.key
          value = dimensions.value
        }
      }
    }

    target_value       = each.value.custom_metric_target
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}

# Step scaling for rapid response to traffic spikes
resource "aws_appautoscaling_policy" "aeims_step_scaling_up" {
  for_each = {
    for service, config in var.enhanced_auto_scaling_configs : service => config
    if lookup(config, "enable_step_scaling", false)
  }

  name               = "${var.project_name}-${each.key}-step-scale-up-${var.environment}"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "PercentChangeInCapacity"
    cooldown                = each.value.scale_out_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 50
      scaling_adjustment          = 50
    }

    step_adjustment {
      metric_interval_lower_bound = 50
      scaling_adjustment          = 100
    }
  }
}

resource "aws_appautoscaling_policy" "aeims_step_scaling_down" {
  for_each = {
    for service, config in var.enhanced_auto_scaling_configs : service => config
    if lookup(config, "enable_step_scaling", false)
  }

  name               = "${var.project_name}-${each.key}-step-scale-down-${var.environment}"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.aeims_enhanced_scaling[each.key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "PercentChangeInCapacity"
    cooldown                = each.value.scale_in_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -25
    }
  }
}

# CloudWatch Alarms for step scaling
resource "aws_cloudwatch_metric_alarm" "aeims_high_cpu_alarm" {
  for_each = {
    for service, config in var.enhanced_auto_scaling_configs : service => config
    if lookup(config, "enable_step_scaling", false)
  }

  alarm_name          = "${var.project_name}-${each.key}-high-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.high_cpu_threshold
  alarm_description   = "This metric monitors ECS CPU utilization"

  alarm_actions = [aws_appautoscaling_policy.aeims_step_scaling_up[each.key].arn]

  dimensions = {
    ServiceName = aws_ecs_service.aeims_services[each.key].name
    ClusterName = aws_ecs_cluster.aeims_cluster.name
  }

  tags = {
    Name = "${var.project_name}-${each.key}-high-cpu-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "aeims_low_cpu_alarm" {
  for_each = {
    for service, config in var.enhanced_auto_scaling_configs : service => config
    if lookup(config, "enable_step_scaling", false)
  }

  alarm_name          = "${var.project_name}-${each.key}-low-cpu-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.low_cpu_threshold
  alarm_description   = "This metric monitors ECS CPU utilization for scale down"

  alarm_actions = [aws_appautoscaling_policy.aeims_step_scaling_down[each.key].arn]

  dimensions = {
    ServiceName = aws_ecs_service.aeims_services[each.key].name
    ClusterName = aws_ecs_cluster.aeims_cluster.name
  }

  tags = {
    Name = "${var.project_name}-${each.key}-low-cpu-alarm-${var.environment}"
  }
}

# Predictive Scaling (using EventBridge for scheduling)
resource "aws_lambda_function" "predictive_scaling" {
  count = var.enable_predictive_scaling ? 1 : 0

  function_name = "${var.project_name}-predictive-scaling-${var.environment}"
  role          = aws_iam_role.predictive_scaling_role[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300

  filename         = data.archive_file.predictive_scaling_zip[0].output_path
  source_code_hash = data.archive_file.predictive_scaling_zip[0].output_base64sha256

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  tags = {
    Name = "${var.project_name}-predictive-scaling-${var.environment}"
  }
}

data "archive_file" "predictive_scaling_zip" {
  count = var.enable_predictive_scaling ? 1 : 0

  type        = "zip"
  output_path = "/tmp/predictive_scaling.zip"
  source {
    content = templatefile("${path.module}/lambda/predictive_scaling.py", {
      environment  = var.environment
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# IAM role for predictive scaling Lambda
resource "aws_iam_role" "predictive_scaling_role" {
  count = var.enable_predictive_scaling ? 1 : 0

  name = "${var.project_name}-predictive-scaling-role-${var.environment}"

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

resource "aws_iam_role_policy" "predictive_scaling_policy" {
  count = var.enable_predictive_scaling ? 1 : 0

  name = "${var.project_name}-predictive-scaling-policy-${var.environment}"
  role = aws_iam_role.predictive_scaling_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:UpdateScalableTarget",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "ecs:DescribeServices",
          "ecs:UpdateService"
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

# EventBridge rule for predictive scaling
resource "aws_cloudwatch_event_rule" "predictive_scaling_schedule" {
  count = var.enable_predictive_scaling ? 1 : 0

  name                = "${var.project_name}-predictive-scaling-${var.environment}"
  description         = "Trigger predictive scaling analysis"
  schedule_expression = "rate(15 minutes)"

  tags = {
    Name = "${var.project_name}-predictive-scaling-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "predictive_scaling_target" {
  count = var.enable_predictive_scaling ? 1 : 0

  rule      = aws_cloudwatch_event_rule.predictive_scaling_schedule[0].name
  target_id = "PredictiveScalingTarget"
  arn       = aws_lambda_function.predictive_scaling[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge_predictive_scaling" {
  count = var.enable_predictive_scaling ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predictive_scaling[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.predictive_scaling_schedule[0].arn
}

# WebSocket connection scaling for AEIMS Lib
resource "aws_cloudwatch_metric_alarm" "websocket_connections_high" {
  alarm_name          = "${var.project_name}-websocket-connections-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ActiveConnections"
  namespace           = "AEIMS/WebSocket"
  period              = "300"
  statistic           = "Average"
  threshold           = var.websocket_connection_threshold
  alarm_description   = "This metric monitors WebSocket connections"

  alarm_actions = [aws_appautoscaling_policy.aeims_cpu_scaling["aeims_lib"].arn]

  dimensions = {
    Service = "aeims-lib"
  }

  tags = {
    Name = "${var.project_name}-websocket-alarm-${var.environment}"
  }
}

# Variables for enhanced auto-scaling
variable "enhanced_auto_scaling_configs" {
  description = "Enhanced auto-scaling configuration for ECS services"
  type = map(object({
    min_capacity             = number
    max_capacity             = number
    target_cpu               = number
    target_memory            = number
    scale_in_cooldown        = number
    scale_out_cooldown       = number
    enable_step_scaling      = bool
    high_cpu_threshold       = number
    low_cpu_threshold        = number
    custom_metric_name       = string
    custom_metric_target     = number
    custom_metric_dimensions = map(string)
  }))
  default = {
    aeims_core = {
      min_capacity         = 2
      max_capacity         = 20
      target_cpu           = 60
      target_memory        = 70
      scale_in_cooldown    = 300
      scale_out_cooldown   = 180
      enable_step_scaling  = true
      high_cpu_threshold   = 80
      low_cpu_threshold    = 20
      custom_metric_name   = "ActiveCalls"
      custom_metric_target = 50
      custom_metric_dimensions = {
        Service = "aeims-core"
      }
    }
    aeims_app = {
      min_capacity         = 1
      max_capacity         = 10
      target_cpu           = 70
      target_memory        = 80
      scale_in_cooldown    = 300
      scale_out_cooldown   = 180
      enable_step_scaling  = true
      high_cpu_threshold   = 85
      low_cpu_threshold    = 25
      custom_metric_name   = "RequestsPerSecond"
      custom_metric_target = 100
      custom_metric_dimensions = {
        Service = "aeims-app"
      }
    }
    aeims_lib = {
      min_capacity         = 1
      max_capacity         = 15
      target_cpu           = 65
      target_memory        = 75
      scale_in_cooldown    = 300
      scale_out_cooldown   = 120
      enable_step_scaling  = true
      high_cpu_threshold   = 80
      low_cpu_threshold    = 20
      custom_metric_name   = "WebSocketConnections"
      custom_metric_target = 1000
      custom_metric_dimensions = {
        Service = "aeims-lib"
      }
    }
  }
}

variable "enable_predictive_scaling" {
  description = "Enable predictive scaling using machine learning"
  type        = bool
  default     = true
}

variable "websocket_connection_threshold" {
  description = "Threshold for WebSocket connections to trigger scaling"
  type        = number
  default     = 800
}

# Outputs
output "autoscaling_policies" {
  description = "Auto-scaling policy ARNs"
  value = {
    cpu_policies    = { for k, v in aws_appautoscaling_policy.aeims_cpu_scaling : k => v.arn }
    memory_policies = { for k, v in aws_appautoscaling_policy.aeims_memory_scaling : k => v.arn }
    custom_policies = { for k, v in aws_appautoscaling_policy.aeims_custom_metrics_scaling : k => v.arn }
  }
}

output "predictive_scaling_function_arn" {
  description = "Predictive scaling Lambda function ARN"
  value       = var.enable_predictive_scaling ? aws_lambda_function.predictive_scaling[0].arn : null
}