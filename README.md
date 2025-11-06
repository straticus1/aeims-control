# AEIMS Infrastructure Management System

A comprehensive production-grade infrastructure management system for deploying and orchestrating the complete AEIMS ecosystem using Terraform, Ansible, and Docker. This system is fully compatible with SuperDeploy deployment patterns and manages all three AEIMS components as an integrated platform with advanced compliance monitoring, multi-domain support, and enterprise-grade security.

## 🌟 Version 2.2.0 Highlights

- **🔄 State Reconciliation Analysis**: Comprehensive analysis of mixed deployment scenarios
- **⚠️ Production Risk Assessment**: Critical gaps identified in state management and configuration drift
- **📋 Deployment Manifest Tracking**: Framework for tracking deployment history and enabling rollbacks
- **🔍 Enhanced Service Discovery**: Remote service detection with `aeims-remote` utility
- **⚙️ Configuration Drift Detection**: Analysis of configuration management between control plane and manual deployments
- **🚨 Critical Risk Mitigation**: Documentation of production risks and recommended safeguards
- **📚 Reconciliation Documentation Suite**: 5 comprehensive guides covering edge cases and best practices
- **🛠️ Testing Framework**: New reconciliation testing capabilities with JavaScript test suite
- **🎯 Production Readiness Roadmap**: Clear path to production-safe state reconciliation

## 🌟 Version 2.1.0 Highlights

- **🎮 Unified Control Plane**: New `aeims-ctl` CLI for managing all services across repositories
- **🔍 Service Discovery**: Automatic detection of local Docker and AWS ECS services
- **🏭 Production-Grade Infrastructure**: Complete AWS ECS deployment with auto-scaling, load balancing, and multi-AZ support
- **🔒 Advanced Compliance**: Federal (FOSTA-SESTA), State (Florida), GDPR, and NY SHIELD Act monitoring
- **🌐 Multi-Domain Management**: SSL certificates and routing for aeims.app, sexacomms.com, nycflirts.com, flirts.nyc
- **💾 Persistent Storage**: EFS file systems with automatic backups for site content and configurations
- **🧪 Comprehensive Testing**: Playwright-based testing suite with 245+ automated tests across 5 browsers
- **📊 Production Monitoring**: CloudWatch, ELK stack, Prometheus, and Grafana integration
- **🛡️ Enterprise Security**: WAF protection, KMS encryption, and real-time threat detection

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
├── bin/                         # Command-line Tools
│   └── aeims-ctl               # Unified control plane CLI (1000+ lines)
│
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
├── scripts/                     # Operational Scripts
│   ├── emergency-site-restore.sh    # Site recovery procedures
│   ├── setup-monitoring.sh          # Monitoring stack setup
│   ├── get-secrets.sh               # Secrets management
│   └── validate-docker-contexts.sh  # Docker validation
│
├── docs/                        # Documentation
│   ├── CONTROL-PLANE.md         # Control plane reference (500+ lines)
│   ├── AEIMS-CTL-QUICK-START.md # Quick start guide
│   ├── DETECT-FEATURE.md        # Service discovery guide (400+ lines)
│   └── SERVICE-INTEGRATION-ANALYSIS.md # Architecture analysis
│
├── tests/                       # Integration Testing
│   └── integration-test.sh     # Comprehensive test suite
│
├── logs/                        # Deployment and operation logs
├── docker-compose.yml           # Complete service orchestration
├── .env.example                 # Environment template
├── deploy.sh                    # SuperDeploy-compatible script
├── CHANGELOG.md                 # Version history
└── README.md                    # This file
```

## 🎮 Control Plane Management

### Unified CLI Tool

The new `aeims-ctl` command provides centralized management for all AEIMS services:

```bash
# List all services
aeims-ctl list

# Check service status
aeims-ctl status              # All services
aeims-ctl status redis        # Specific service

# Start/stop services
aeims-ctl start all           # Start everything
aeims-ctl start redis         # Start one service
aeims-ctl stop all            # Stop everything
aeims-ctl restart aeims-core  # Restart service

# View logs
aeims-ctl logs aeims-core     # View logs
aeims-ctl logs nginx -f       # Follow logs in real-time

# Service discovery
aeims-ctl detect              # Find local Docker containers
aeims-ctl detect --aws        # Discover AWS ECS services
aeims-ctl detect --all        # Scan everything

# Health checks
aeims-ctl health              # Check all health endpoints
aeims-ctl ps                  # Show running containers

# JSON output for automation
aeims-ctl status --json
aeims-ctl list --json
```

**Installation:**
```bash
# Make executable
chmod +x ~/development/aeims-control/bin/aeims-ctl

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/development/aeims-control/bin:$PATH"

# Verify
aeims-ctl --help
```

**Full Documentation:** See [docs/CONTROL-PLANE.md](docs/CONTROL-PLANE.md) and [docs/AEIMS-CTL-QUICK-START.md](docs/AEIMS-CTL-QUICK-START.md)

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

### Production Service Architecture (v2.0.0)

```
                            🌐 AWS Application Load Balancer
                                   (Multi-Domain SSL)
                            aeims.app | sexacomms.com | nycflirts.com | flirts.nyc
                                           │
                                           ▼
                                 ┌─────────────────────┐
                                 │    Nginx Proxy      │
                                 │   (8085/8445)       │
                                 │ • SSL Termination   │
                                 │ • Rate Limiting     │
                                 │ • CORS Headers      │
                                 └─────────────────────┘
                                           │
                  ┌────────────────────────┼────────────────────────┐
                  ▼                        ▼                        ▼
        ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
        │   AEIMS Core    │      │    AEIMS App    │      │   AEIMS Lib     │
        │    (8000)       │      │     (81/443)    │      │    (8081 WS)    │
        │                 │      │                 │      │                 │
        │ • Django API    │      │ • Marketing     │      │ • Buttplug.io   │
        │ • 12 Services   │      │ • Admin Portal  │      │ • WebSocket     │
        │ • PostgreSQL    │◄────►│ • MySQL         │◄────►│ • Device Ctrl   │
        │ • Auth/OAuth    │      │ • CMS           │      │ • VR/AR Support │
        └─────────────────┘      └─────────────────┘      └─────────────────┘
                  │                        │                        │
                  └────────────────────────┼────────────────────────┘
                                           ▼
                              ┌─────────────────────────┐
                              │    Redis Cluster        │
                              │     (6379)             │
                              │ • Session Storage      │
                              │ • Rate Limiting        │
                              │ • WebSocket State      │
                              │ • Cache Layer          │
                              └─────────────────────────┘

📊 Microservices (PHP/Python):
   User(8001) | Billing(8002) | Telephony(8003) | Call(8004) | 
   Operator(8005) | Session(8006) | Analytics(8007) | Admin(8008) |
   Content(8009) | File(8010) | Marketing(8011) | Verification(8012)

🗄️ Persistent Storage:
   EFS Sites | EFS Data | EFS Nginx Config | RDS PostgreSQL | RDS MySQL

🔍 Monitoring Stack:
   CloudWatch | Prometheus(9090) | Grafana(3001) | ELK Stack
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

## 🔒 Security & Compliance Framework

### Federal Compliance (FOSTA-SESTA)
- **Anti-Trafficking Monitoring**: Real-time content scanning and user activity monitoring
- **Interstate Commerce Tracking**: Multi-state transaction monitoring and reporting
- **Mann Act Compliance**: Transportation activity auditing and legal compliance
- **Law Enforcement Reporting**: Automated suspicious activity reporting to appropriate authorities

### State-Level Compliance (Florida)
- **Age Verification**: Enhanced age verification systems with ID validation
- **Content Filtering**: Real-time content moderation and obscenity filtering
- **Geolocation Controls**: Location-based access restrictions and compliance
- **Regulatory Reporting**: Automated compliance reporting to state authorities

### Privacy & Data Protection
- **GDPR Compliance**: European privacy rights management and data protection
- **NY SHIELD Act**: Data breach notification and consumer protection systems
- **Privacy Rights Management**: User data control and deletion capabilities
- **Breach Detection**: Real-time monitoring for data breaches and security incidents

### Security Infrastructure
- **WAF Protection**: Web Application Firewall with custom rule sets
- **KMS Encryption**: Database and storage encryption with AWS Key Management
- **Audit Logging**: Comprehensive audit trails for all system activities
- **Threat Detection**: Real-time security monitoring and threat response

## 🧪 Testing & Quality Assurance

### Comprehensive Testing Suite (v2.0.0)
- **Playwright Framework**: End-to-end testing across 5 browser engines
- **245+ Automated Tests**: Comprehensive coverage of all system components
- **Multi-Viewport Testing**: Desktop, tablet, and mobile device testing
- **Network Analysis**: Traffic monitoring and performance validation
- **Accessibility Testing**: WCAG compliance validation and accessibility checks
- **Security Testing**: Penetration testing and vulnerability assessments

### Production Monitoring
- **Health Check Endpoints**: Automated health monitoring for all services
- **Performance Metrics**: Real-time performance monitoring and alerting
- **Error Tracking**: Comprehensive error logging and notification systems
- **Uptime Monitoring**: 24/7 service availability monitoring

### Test Coverage Areas
| Component | Coverage | Status |
|-----------|----------|--------|
| **Authentication** | Login/logout, OAuth, sessions | ✅ Implemented |
| **API Endpoints** | All REST/GraphQL endpoints | ✅ Implemented |
| **Device Control** | Buttplug.io integration | ✅ Implemented |
| **VoIP Services** | Telephony and call management | ✅ Implemented |
| **Payment Systems** | Billing and payment processing | ✅ Implemented |
| **Admin Functions** | User management, reporting | ✅ Implemented |
| **Compliance** | Regulatory and legal compliance | ✅ Implemented |
| **Security** | WAF, encryption, audit trails | ✅ Implemented |

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

## 💫 Documentation & Resources

### Core Documentation
- [AEIMS Core Documentation](../aeims/README.md)
- [AEIMS App Documentation](../aeims.app/README.md)  
- [AEIMS Lib Documentation](../aeimsLib/README.md)
- [SuperDeploy Documentation](../SuperDeploy/README.md)

### New in Version 2.2.0
- [Reconciliation Executive Summary](RECONCILIATION-EXECUTIVE-SUMMARY.md) - Critical gaps and production risk assessment
- [Reconciliation Complete Analysis](RECONCILIATION-COMPLETE.md) - Comprehensive capability analysis
- [Reconciliation Quick Reference](RECONCILIATION-QUICK-REFERENCE.md) - At-a-glance status and decisions
- [Reconciliation User Guide](RECONCILIATION-USER-GUIDE.md) - Best practices and operational guidance
- [Reconciliation Analysis](RECONCILIATION-ANALYSIS.md) - Detailed technical analysis and code review

### New in Version 2.1.0
- [Control Plane Documentation](docs/CONTROL-PLANE.md) - Complete CLI reference (500+ lines)
- [Quick Start Guide](docs/AEIMS-CTL-QUICK-START.md) - Essential commands and workflows
- [Service Discovery Guide](docs/DETECT-FEATURE.md) - Local and AWS service detection (400+ lines)
- [Integration Analysis](docs/SERVICE-INTEGRATION-ANALYSIS.md) - Architecture and integration status
- [Control Plane Summary](CONTROL-PLANE-SUMMARY.md) - Implementation overview and results

### Version 2.0.0 Documentation
- [Service Architecture Guide](SERVICE-ARCHITECTURE.md) - Complete port mapping and service dependencies
- [Deployment Analysis Report](DEPLOYMENT-ANALYSIS-REPORT.md) - Infrastructure audit and production readiness
- [Production Validation Report](FINAL-PRODUCTION-VALIDATION-REPORT.md) - Comprehensive deployment validation
- [Testing Results Summary](tests/TESTING_RESULTS_SUMMARY.md) - Automated testing results and coverage
- [Terraform Deployment Guide](terraform/DEPLOYMENT-GUIDE.md) - Step-by-step AWS deployment procedures
- [Session Completion Summary](SESSION-COMPLETION-SUMMARY.md) - Operational reports and maintenance procedures

### Technical Reference
- [Health Check Specifications](docs/health-check-spec.md) - API health check endpoints and monitoring
- [Security Credentials Management](SEXACOMMS-CREDENTIALS.md) - Authentication and access management
- [PHP Debugging Helper](php-debug-helper.php) - Production debugging and error handling
- [Claude AI Integration](CLAUDE.md) - AI-powered deployment automation

### Compliance & Security
- **Federal Compliance**: FOSTA-SESTA monitoring, Mann Act compliance, anti-trafficking systems
- **State Compliance**: Florida age verification, content filtering, geolocation controls
- **Privacy Protection**: GDPR compliance, NY SHIELD Act, privacy rights management
- **Security Infrastructure**: WAF protection, KMS encryption, audit logging, threat detection

## 🤝 Support

For technical support or questions:

- **Email**: coleman.ryan@gmail.com
- **Response Time**: Within 24 hours
- **Emergency**: Use GitHub issues for urgent deployment problems

---

**Built with ❤️ by After Dark Systems**

*AEIMS Infrastructure Management System - Complete platform orchestration made simple*