# ELK Stack (Elasticsearch, Logstash, Kibana) for AEIMS
# Provides centralized logging and log analysis

# Elasticsearch Service
resource "aws_elasticsearch_domain" "aeims_es" {
  count = var.enable_centralized_logging ? 1 : 0

  domain_name           = "${var.project_name}-logs-${var.environment}"
  elasticsearch_version = var.elasticsearch_version

  cluster_config {
    instance_type            = var.elasticsearch_instance_type
    instance_count           = var.elasticsearch_instance_count
    dedicated_master_enabled = var.elasticsearch_instance_count > 2
    dedicated_master_type    = var.elasticsearch_instance_count > 2 ? var.elasticsearch_master_instance_type : null
    dedicated_master_count   = var.elasticsearch_instance_count > 2 ? 3 : null
    zone_awareness_enabled   = var.elasticsearch_instance_count > 1

    dynamic "zone_awareness_config" {
      for_each = var.elasticsearch_instance_count > 1 ? [1] : []
      content {
        availability_zone_count = min(var.elasticsearch_instance_count, length(data.aws_availability_zones.available.names))
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.elasticsearch_volume_size
    throughput  = 250
    iops        = 3000
  }

  vpc_options {
    subnet_ids         = slice(aws_subnet.private_subnets[*].id, 0, min(var.elasticsearch_instance_count, length(aws_subnet.private_subnets)))
    security_group_ids = [aws_security_group.elasticsearch_sg[0].id]
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.aeims_key.key_id
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-logs-${var.environment}/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = concat(
              [var.vpc_cidr],
              var.admin_cidr_blocks
            )
          }
        }
      }
    ]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.elasticsearch_logs[0].arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.elasticsearch_logs[0].arn
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = true
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "indices.fielddata.cache.size"           = "20"
    "indices.query.bool.max_clause_count"    = "1024"
  }

  tags = {
    Name        = "${var.project_name}-elasticsearch-${var.environment}"
    Environment = var.environment
  }

  depends_on = [aws_iam_service_linked_role.es]
}

# IAM service linked role for Elasticsearch
resource "aws_iam_service_linked_role" "es" {
  count            = var.enable_centralized_logging ? 1 : 0
  aws_service_name = "es.amazonaws.com"
}

# Security group for Elasticsearch
resource "aws_security_group" "elasticsearch_sg" {
  count = var.enable_centralized_logging ? 1 : 0

  name_prefix = "${var.project_name}-es-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  ingress {
    description     = "HTTPS from AEIMS services"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  ingress {
    description = "HTTPS from admin CIDR blocks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-elasticsearch-sg-${var.environment}"
  }
}

# CloudWatch Log Group for Elasticsearch
resource "aws_cloudwatch_log_group" "elasticsearch_logs" {
  count = var.enable_centralized_logging ? 1 : 0

  name              = "/aws/elasticsearch/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-elasticsearch-logs-${var.environment}"
  }
}

# Logstash configuration (running on ECS)
resource "aws_ecs_task_definition" "logstash" {
  count = var.enable_centralized_logging ? 1 : 0

  family                   = "${var.project_name}-logstash-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.aeims_task_execution_role.arn
  task_role_arn            = aws_iam_role.logstash_task_role[0].arn

  container_definitions = jsonencode([
    {
      name  = "logstash"
      image = "docker.elastic.co/logstash/logstash:${var.elk_version}"

      portMappings = [
        {
          containerPort = 5044
          protocol      = "tcp"
        },
        {
          containerPort = 9600
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ELASTICSEARCH_HOSTS"
          value = "https://${aws_elasticsearch_domain.aeims_es[0].endpoint}"
        },
        {
          name  = "XPACK_MONITORING_ENABLED"
          value = "false"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "logstash-config"
          containerPath = "/usr/share/logstash/pipeline"
          readOnly      = true
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.aeims_logs["logstash"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9600/_node/hot_threads || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  volume {
    name = "logstash-config"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.logstash_config[0].id
      root_directory = "/"
    }
  }

  tags = {
    Name = "${var.project_name}-logstash-task-${var.environment}"
  }
}

# ECS Service for Logstash
resource "aws_ecs_service" "logstash" {
  count = var.enable_centralized_logging ? 1 : 0

  name            = "${var.project_name}-logstash-${var.environment}"
  cluster         = aws_ecs_cluster.aeims_cluster.id
  task_definition = aws_ecs_task_definition.logstash[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnets[*].id
    security_groups  = [aws_security_group.logstash_sg[0].id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.logstash[0].arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.logstash_task_policy
  ]

  tags = {
    Name = "${var.project_name}-logstash-service-${var.environment}"
  }
}

# Security group for Logstash
resource "aws_security_group" "logstash_sg" {
  count = var.enable_centralized_logging ? 1 : 0

  name_prefix = "${var.project_name}-logstash-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  ingress {
    description     = "Beats input"
    from_port       = 5044
    to_port         = 5044
    protocol        = "tcp"
    security_groups = [aws_security_group.aeims_app_sg.id]
  }

  ingress {
    description = "Logstash API"
    from_port   = 9600
    to_port     = 9600
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-logstash-sg-${var.environment}"
  }
}

# EFS for Logstash configuration
resource "aws_efs_file_system" "logstash_config" {
  count = var.enable_centralized_logging ? 1 : 0

  creation_token                  = "${var.project_name}-logstash-config-${var.environment}"
  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 100

  encrypted  = true
  kms_key_id = aws_kms_key.aeims_key.arn

  tags = {
    Name = "${var.project_name}-logstash-config-${var.environment}"
  }
}

# EFS mount targets
resource "aws_efs_mount_target" "logstash_config" {
  count = var.enable_centralized_logging ? length(aws_subnet.private_subnets) : 0

  file_system_id  = aws_efs_file_system.logstash_config[0].id
  subnet_id       = aws_subnet.private_subnets[count.index].id
  security_groups = [aws_security_group.efs_sg[0].id]
}

# Security group for EFS
resource "aws_security_group" "efs_sg" {
  count = var.enable_centralized_logging ? 1 : 0

  name_prefix = "${var.project_name}-efs-sg-"
  vpc_id      = aws_vpc.aeims_vpc.id

  ingress {
    description     = "NFS from Logstash"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.logstash_sg[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg-${var.environment}"
  }
}

# IAM role for Logstash
resource "aws_iam_role" "logstash_task_role" {
  count = var.enable_centralized_logging ? 1 : 0

  name = "${var.project_name}-logstash-task-role-${var.environment}"

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
}

resource "aws_iam_role_policy" "logstash_task_policy" {
  count = var.enable_centralized_logging ? 1 : 0

  name = "${var.project_name}-logstash-task-policy-${var.environment}"
  role = aws_iam_role.logstash_task_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Resource = "${aws_elasticsearch_domain.aeims_es[0].arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "logstash_task_policy" {
  count = var.enable_centralized_logging ? 1 : 0

  role       = aws_iam_role.logstash_task_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Service Discovery for Logstash
resource "aws_service_discovery_private_dns_namespace" "aeims" {
  count = var.enable_centralized_logging ? 1 : 0

  name = "${var.project_name}.local"
  vpc  = aws_vpc.aeims_vpc.id

  tags = {
    Name = "${var.project_name}-service-discovery-${var.environment}"
  }
}

resource "aws_service_discovery_service" "logstash" {
  count = var.enable_centralized_logging ? 1 : 0

  name = "logstash"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aeims[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = {
    Name = "${var.project_name}-logstash-discovery-${var.environment}"
  }
}

# Kibana (using AWS managed service or separate deployment)
resource "aws_ecs_task_definition" "kibana" {
  count = var.enable_centralized_logging && var.deploy_kibana_separately ? 1 : 0

  family                   = "${var.project_name}-kibana-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.aeims_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "kibana"
      image = "docker.elastic.co/kibana/kibana:${var.elk_version}"

      portMappings = [
        {
          containerPort = 5601
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ELASTICSEARCH_HOSTS"
          value = "https://${aws_elasticsearch_domain.aeims_es[0].endpoint}"
        },
        {
          name  = "SERVER_NAME"
          value = "kibana.${var.project_name}.local"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.aeims_logs["kibana"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5601/api/status || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-kibana-task-${var.environment}"
  }
}

# Variables for ELK Stack
variable "enable_centralized_logging" {
  description = "Enable centralized logging with ELK stack"
  type        = bool
  default     = true
}

variable "elasticsearch_version" {
  description = "Elasticsearch version"
  type        = string
  default     = "OpenSearch_2.19"
}

variable "elasticsearch_instance_type" {
  description = "Elasticsearch instance type"
  type        = string
  default     = "t3.medium.elasticsearch"
}

variable "elasticsearch_instance_count" {
  description = "Number of Elasticsearch instances"
  type        = number
  default     = 1
}

variable "elasticsearch_master_instance_type" {
  description = "Elasticsearch master instance type"
  type        = string
  default     = "t3.small.elasticsearch"
}

variable "elasticsearch_volume_size" {
  description = "EBS volume size for Elasticsearch (GB)"
  type        = number
  default     = 20
}

variable "elk_version" {
  description = "ELK stack version"
  type        = string
  default     = "7.17.0"
}

variable "deploy_kibana_separately" {
  description = "Deploy Kibana as separate service (vs using AWS Kibana)"
  type        = bool
  default     = false
}

# Outputs
output "elasticsearch_endpoint" {
  description = "Elasticsearch endpoint"
  value       = var.enable_centralized_logging ? aws_elasticsearch_domain.aeims_es[0].endpoint : null
}

output "elasticsearch_kibana_endpoint" {
  description = "Kibana endpoint (AWS managed)"
  value       = var.enable_centralized_logging ? aws_elasticsearch_domain.aeims_es[0].kibana_endpoint : null
}

output "logstash_service_name" {
  description = "Logstash service discovery name"
  value       = var.enable_centralized_logging ? "${aws_service_discovery_service.logstash[0].name}.${aws_service_discovery_private_dns_namespace.aeims[0].name}" : null
}
