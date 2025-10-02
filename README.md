# AEIMS Infrastructure Management System

A comprehensive infrastructure management system for deploying and orchestrating the complete AEIMS ecosystem using Terraform, Ansible, and Docker. This system is fully compatible with SuperDeploy deployment patterns and manages all three AEIMS components as an integrated platform.

## 🏗️ System Overview

This infrastructure management system deploys and manages:

- **AEIMS Core** (../aeims) - Enterprise telephony platform with microservices
- **AEIMS App** (../aeims.app) - Showcase website and administration interface
- **AEIMS Lib** (../aeimsLib) - Device management library with WebSocket support

## 🚀 Quick Start

### Prerequisites

Ensure you have the following tools installed:

```bash
# Required tools
aws-cli      # AWS command line interface
terraform    # Infrastructure as Code
ansible      # Configuration management
docker       # Container runtime
jq           # JSON processor
```

### Local Development Deployment

```bash
# Clone and setup
cd /Users/ryan/development/aeims-control

# Copy environment configuration
cp .env.example .env

# Deploy locally with Docker Compose
./deploy.sh --environment dev

# Or use Docker Compose directly
docker-compose up -d
```

### Cloud Deployment

```bash
# Deploy to staging
./deploy.sh --environment staging --auto-approve

# Deploy to production (plan first)
./deploy.sh --environment prod --plan-only
./deploy.sh --environment prod --auto-approve
```

## 📁 Project Structure

```
aeims-control/
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Main Terraform configuration
│   ├── variables.tf             # Variable definitions
│   ├── ecs.tf                   # ECS services and databases
│   └── plans/                   # Terraform execution plans
│
├── ansible/                     # Configuration Management
│   ├── deploy.yml               # Main deployment playbook
│   ├── vars/main.yml            # Configuration variables
│   ├── tasks/                   # Ansible task modules
│   │   ├── container-build.yml  # Docker build tasks
│   │   ├── build-single-service.yml
│   │   └── ...
│   └── inventory.yml            # Generated inventory
│
├── tests/                       # Integration Testing
│   └── integration-test.sh     # Comprehensive test suite
│
├── logs/                        # Deployment and operation logs
├── docker-compose.yml           # Complete service orchestration
├── .env.example                 # Environment template
├── deploy.sh                    # SuperDeploy-compatible script
└── README.md                    # This file
```

## 🔧 Deployment Options

### SuperDeploy Compatible Commands

The `deploy.sh` script supports all standard SuperDeploy arguments:

```bash
# Basic deployment
./deploy.sh --environment dev

# Planning mode (dry run)
./deploy.sh --environment prod --plan-only

# Infrastructure only
./deploy.sh --environment staging --infrastructure-only

# Applications only
./deploy.sh --environment staging --application-only

# Auto-approve mode
./deploy.sh --environment prod --auto-approve

# Verbose output
./deploy.sh --environment dev --verbose

# Show help
./deploy.sh --help
```

### Environment-Specific Deployments

#### Development Environment
- Uses local Docker Compose
- Direct database connections
- No SSL/TLS encryption
- Debug logging enabled

```bash
./deploy.sh --environment dev
```

#### Staging Environment
- AWS ECS deployment
- RDS managed databases
- SSL/TLS enabled
- LoadBalancer with health checks

```bash
./deploy.sh --environment staging --auto-approve
```

#### Production Environment
- Multi-AZ deployment
- Auto-scaling enabled
- WAF protection
- Enhanced monitoring
- Backup strategies

```bash
./deploy.sh --environment prod --plan-only
# Review plan, then:
./deploy.sh --environment prod --auto-approve
```

## 🏗️ Infrastructure Components

### Terraform Resources

| Component | Description | Environment Support |
|-----------|-------------|-------------------|
| **VPC & Networking** | Private/public subnets, NAT gateways | All |
| **ECS Cluster** | Fargate-based container orchestration | Staging, Prod |
| **RDS Databases** | PostgreSQL (Core), MySQL (App) | All |
| **ElastiCache** | Redis clusters for all services | All |
| **Application Load Balancer** | Traffic routing and SSL termination | Staging, Prod |
| **Auto Scaling** | CPU/Memory-based scaling policies | All |
| **CloudWatch** | Logging and metrics collection | All |
| **S3 Buckets** | Asset storage and backups | All |
| **IAM Roles** | Least-privilege access policies | All |

### Service Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AEIMS Core    │    │    AEIMS App    │    │   AEIMS Lib     │
│                 │    │                 │    │                 │
│ • Telephony API │    │ • Showcase Site │    │ • Device Mgmt   │
│ • Microservices │    │ • Admin Panel   │    │ • WebSocket API │
│ • FreeSWITCH    │◄──►│ • Contact Forms │◄──►│ • Protocol Lib  │
│ • PostgreSQL    │    │ • MySQL         │    │ • Redis Cache   │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────────────┐
                    │   Load Balancer/Nginx   │
                    │                         │
                    │ • Route: /api/* → Core  │
                    │ • Route: /ws/* → Lib    │
                    │ • Route: /* → App       │
                    └─────────────────────────┘
```

## 📦 Service Configurations

### AEIMS Core Services

| Service | Port | Description | Dependencies |
|---------|------|-------------|--------------|
| **aeims-core** | 8000 | Main telephony platform | PostgreSQL, Redis |
| **user-service** | 8001 | User management | PostgreSQL, Redis |
| **billing-service** | 8002 | Billing and payments | PostgreSQL, Redis |
| **call-service** | 8003 | Call management | PostgreSQL, Redis |
| **operator-service** | 8004 | Operator interface | PostgreSQL, Redis |
| **conference-service** | 8005 | Conference calls | PostgreSQL, Redis |
| **notification-service** | 8006 | Notifications | PostgreSQL, Redis |
| **analytics-service** | 8007 | Analytics and reporting | PostgreSQL, Redis |
| **frontend** | 3000 | React.js interface | - |

### Database Services

| Service | Type | Port | Purpose |
|---------|------|------|---------|
| **aeims-core-postgres** | PostgreSQL 14 | 5432 | Core platform data |
| **aeims-app-mysql** | MySQL 8.0 | 3306 | Website and admin data |
| **aeims-redis** | Redis 7 | 6379 | Caching and sessions |

### Integration Endpoints

| Service | URL Pattern | Target | Description |
|---------|-------------|--------|-------------|
| AEIMS Core API | `/api/*` | aeims-core:8000 | Telephony API endpoints |
| AEIMS Lib WebSocket | `/ws/*` | aeims-lib:8080 | Device control WebSocket |
| User Management | `/users/*` | user-service:8001 | User operations |
| Billing | `/billing/*` | billing-service:8002 | Payment processing |
| Analytics | `/analytics/*` | analytics-service:8007 | Reporting interface |
| AEIMS App | `/*` | aeims-app:80 | Main website (fallback) |

## 🔧 Configuration Management

### Environment Variables

Key configuration options (see `.env.example` for full list):

```bash
# Environment
ENVIRONMENT=dev|staging|prod
AEIMS_VERSION=latest

# Database Configuration
AEIMS_CORE_DB_NAME=aeims_core
AEIMS_CORE_DB_USER=aeims_user
AEIMS_CORE_DB_PASS=secure_password_123

AEIMS_APP_DB_NAME=aeims_app
AEIMS_APP_DB_USER=aeims_user
AEIMS_APP_DB_PASS=secure_password_123

# Redis Configuration
REDIS_PASSWORD=secure_redis_pass

# Service Ports
AEIMS_CORE_PORT=8000
AEIMS_APP_PORT=81
AEIMS_LIB_PORT=8080

# AWS Configuration
AWS_REGION=us-west-2
TF_STATE_BUCKET=aeims-terraform-state-dev

# Feature Flags
ENABLE_AEIMS_CORE=true
ENABLE_AEIMS_APP=true
ENABLE_AEIMS_LIB=true
ENABLE_MONITORING=true
```

### Terraform Variables

Override variables in `terraform/terraform.tfvars`:

```hcl
# Basic Configuration
environment = "staging"
aws_region = "us-west-2"
project_name = "aeims"

# Infrastructure Sizing
vpc_cidr = "10.0.0.0/16"
public_subnet_count = 2
private_subnet_count = 2

# Feature Toggles
feature_flags = {
  enable_aeims_core = true
  enable_aeims_app  = true
  enable_aeims_lib  = true
  enable_monitoring = true
  enable_ssl        = true
}

# Auto Scaling
auto_scaling_configs = {
  aeims_core = {
    min_capacity = 2
    max_capacity = 10
    target_cpu   = 70
  }
}
```

## 🧪 Testing and Validation

### Integration Test Suite

The comprehensive test suite validates all service integrations:

```bash
# Run all integration tests
./tests/integration-test.sh dev

# Run tests for specific environment
./tests/integration-test.sh staging
```

### Test Coverage

| Phase | Tests | Description |
|-------|-------|-------------|
| **Service Readiness** | 3 tests | HTTP health checks for all services |
| **Database Connectivity** | 3 tests | PostgreSQL, MySQL, Redis connections |
| **API Endpoints** | 5+ tests | Service-specific API validation |
| **Service Integration** | 3 tests | Cross-service communication |
| **Performance** | 2 tests | Response time validation |
| **Security** | 1+ tests | Security header validation |

### Expected Test Results

```
Phase 1: Service Readiness Tests
=================================
✓ AEIMS Core is ready (HTTP 200)
✓ AEIMS App is ready (HTTP 200)  
✓ AEIMS Lib is ready (HTTP 200)

Phase 2: Database Connectivity Tests
====================================
✓ AEIMS Core PostgreSQL connection OK
✓ AEIMS App MySQL connection OK
✓ Redis connection OK

Phase 3: API Endpoint Tests
===========================
✓ AEIMS Core Health Check OK (HTTP 200, 0.123s)
✓ AEIMS App Index OK (HTTP 200, 0.089s)
✓ AEIMS Lib Health Check OK (HTTP 200, 0.067s)

Integration Test Results
=======================
Total Tests: 15
Passed: 15
Failed: 0

✓ All integration tests passed! ✨
```

## 🔍 Monitoring and Observability

### Monitoring Stack

When `ENABLE_MONITORING=true`:

- **Prometheus** (port 9090) - Metrics collection
- **Grafana** (port 3001) - Visualization dashboards  
- **CloudWatch** - AWS native logging and metrics
- **Application logs** - Centralized in `/var/log/aeims`

### Key Metrics

- Service health and uptime
- Database connection pools
- Redis cache hit rates
- Load balancer response times
- Container resource utilization
- Integration endpoint latencies

### Accessing Monitoring

```bash
# Local development
open http://localhost:9090    # Prometheus
open http://localhost:3001    # Grafana (admin/admin123)

# Cloud environments
open http://$(terraform output -raw alb_dns_name)/grafana
```

## 📋 Maintenance and Operations

### Regular Operations

```bash
# Check deployment status
./deploy.sh --environment prod --plan-only

# Update application images
docker-compose pull && docker-compose up -d

# View logs
docker-compose logs -f aeims-core
docker-compose logs -f aeims-app
docker-compose logs -f aeims-lib

# Scale services
docker-compose up -d --scale aeims-core=3

# Health check
curl http://localhost:8000/health
curl http://localhost:81/
curl http://localhost:8080/health
```

### Database Management

```bash
# PostgreSQL (AEIMS Core)
docker-compose exec aeims-core-postgres psql -U aeims_user aeims_core

# MySQL (AEIMS App)
docker-compose exec aeims-app-mysql mysql -u aeims_user -p aeims_app

# Redis
docker-compose exec aeims-redis redis-cli -a secure_redis_pass
```

### Backup and Recovery

```bash
# Database backups (automated via AWS RDS in cloud)
# Manual backup for development
docker-compose exec aeims-core-postgres pg_dump -U aeims_user aeims_core > backup.sql

# Configuration backup
tar -czf aeims-config-backup.tar.gz .env terraform/ ansible/vars/
```

## 🚨 Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check logs
docker-compose logs service-name

# Check dependencies
docker-compose ps

# Restart service
docker-compose restart service-name
```

#### Database Connection Issues
```bash
# Check database is running
docker-compose ps | grep postgres
docker-compose ps | grep mysql

# Test connection manually
docker-compose exec aeims-core-postgres pg_isready
```

#### Integration Test Failures
```bash
# Run verbose tests
./tests/integration-test.sh dev

# Check service endpoints individually
curl -v http://localhost:8000/health
curl -v http://localhost:81/
curl -v http://localhost:8080/health
```

### Log Locations

| Component | Log Location |
|-----------|--------------|
| **Deploy Script** | `logs/deploy-YYYYMMDD-HHMMSS.log` |
| **Integration Tests** | Console output + test artifacts |
| **Docker Services** | `docker-compose logs <service>` |
| **Terraform** | `terraform/plans/*.plan` |
| **Ansible** | `ansible/logs/deployment-*.log` |

## 🔗 Integration with SuperDeploy

This system is fully compatible with SuperDeploy and can be managed through it:

```bash
# Add to SuperDeploy
cd /Users/ryan/development/SuperDeploy
./superdeploy add aeims-control

# Deploy via SuperDeploy
./superdeploy deploy aeims-control --environment dev
./superdeploy plan aeims-control --environment prod
```

The `deploy.sh` script follows SuperDeploy conventions and supports all standard arguments.

## 📖 Additional Resources

- [AEIMS Core Documentation](../aeims/README.md)
- [AEIMS App Documentation](../aeims.app/README.md)  
- [AEIMS Lib Documentation](../aeimsLib/README.md)
- [SuperDeploy Documentation](../SuperDeploy/README.md)

## 🤝 Support

For technical support or questions:

- **Email**: coleman.ryan@gmail.com
- **Response Time**: Within 24 hours
- **Emergency**: Use GitHub issues for urgent deployment problems

---

**Built with ❤️ by After Dark Systems**

*AEIMS Infrastructure Management System - Complete platform orchestration made simple*