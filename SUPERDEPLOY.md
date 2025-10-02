# AEIMS SuperDeploy Integration Guide

This document describes how to register and deploy the AEIMS platform using SuperDeploy.

## Registration Process

### 1. Prerequisites

Ensure you have SuperDeploy installed and configured:

```bash
# Install SuperDeploy (if not already installed)
npm install -g superdeploy

# Verify installation
superdeploy --version
```

### 2. Register AEIMS Control with SuperDeploy

```bash
# Navigate to SuperDeploy directory
cd /Users/ryan/development/SuperDeploy

# Add AEIMS Control project
./superdeploy add aeims-control

# Verify registration
./superdeploy list
```

### 3. Initial AWS Infrastructure Setup

Before deploying, set up the required AWS infrastructure:

```bash
# Setup AWS infrastructure (S3, DynamoDB, ECR)
cd /Users/ryan/development/aeims-control
./setup-aws-infrastructure.sh dev
```

### 4. Deploy via SuperDeploy

```bash
# Development deployment
./superdeploy deploy aeims-control --environment dev

# Staging deployment (with plan review)
./superdeploy plan aeims-control --environment staging
./superdeploy deploy aeims-control --environment staging

# Production deployment (with approval workflow)
./superdeploy plan aeims-control --environment prod
./superdeploy deploy aeims-control --environment prod --auto-approve
```

## SuperDeploy Configuration

The AEIMS platform includes a complete SuperDeploy configuration (`superdeploy.json`) with:

- **Multi-environment support**: dev, staging, prod
- **Service orchestration**: All AEIMS services with proper dependencies
- **Infrastructure management**: Complete AWS infrastructure via Terraform
- **Compliance configurations**: GDPR, PCI DSS, SOX, FOSTA, and more
- **Monitoring integration**: Prometheus, Grafana, ELK stack
- **Security features**: WAF, SSL, encryption, rate limiting
- **Auto-scaling**: CPU and memory-based scaling policies
- **Backup strategies**: Database and application data retention

## Deployment Commands

### Standard Operations

```bash
# Deploy to development
superdeploy deploy aeims-control --environment dev

# Plan staging deployment
superdeploy plan aeims-control --environment staging

# Deploy to production with approval
superdeploy deploy aeims-control --environment prod

# View deployment status
superdeploy status aeims-control

# View deployment logs
superdeploy logs aeims-control --environment dev

# Rollback deployment
superdeploy rollback aeims-control --environment staging
```

### Advanced Operations

```bash
# Deploy infrastructure only
superdeploy deploy aeims-control --environment dev --infrastructure-only

# Deploy applications only
superdeploy deploy aeims-control --environment dev --application-only

# Enable monitoring profile
superdeploy deploy aeims-control --environment dev --profile monitoring

# Scale services
superdeploy scale aeims-control --service aeims-core --replicas 5

# Health check all services
superdeploy health aeims-control --environment dev
```

## Service Architecture

The AEIMS platform consists of the following integrated services:

### Core Services
- **aeims-core**: Main telephony platform (Port 8000)
- **aeims-app**: Showcase website and admin interface (Port 80)
- **aeims-lib**: Device management WebSocket server (Port 8080)
- **aeims-frontend**: React.js user interface (Port 3000)

### Microservices
- **user-service**: User management (Port 8001)
- **billing-service**: Payment processing (Port 8002)
- **call-service**: Call management (Port 8003)
- **operator-service**: Operator interface (Port 8004)
- **conference-service**: Conference calls (Port 8005)
- **notification-service**: Notifications (Port 8006)
- **analytics-service**: Analytics and reporting (Port 8007)

### Infrastructure Services
- **aeims-nginx**: Load balancer and reverse proxy (Port 80/443)
- **aeims-core-postgres**: PostgreSQL database for core platform
- **aeims-app-mysql**: MySQL database for showcase website
- **aeims-redis**: Redis cache and session storage

### Monitoring Services (Optional)
- **aeims-prometheus**: Metrics collection (Port 9090)
- **aeims-grafana**: Visualization dashboards (Port 3001)

## Environment Configuration

### Development Environment
- Uses Docker Compose for local development
- Direct database connections
- Debug logging enabled
- Auto-approval for deployments

### Staging Environment
- AWS ECS deployment
- RDS managed databases
- SSL/TLS enabled
- Load balancer with health checks
- Manual approval required

### Production Environment
- Multi-AZ deployment
- Auto-scaling enabled
- WAF protection
- Enhanced monitoring
- Backup strategies
- Manual approval with additional security

## Access URLs

After successful deployment, access the platform via:

### Development (Local)
- **Main Application**: http://localhost/
- **AEIMS Core API**: http://localhost:8000/
- **AEIMS App**: http://localhost:81/
- **AEIMS Lib WebSocket**: ws://localhost:8080/
- **Prometheus**: http://localhost:9090/
- **Grafana**: http://localhost:3001/

### Cloud Environments
- **Main Application**: http://[ALB-DNS-NAME]/
- **AEIMS Core API**: http://[ALB-DNS-NAME]/api/
- **AEIMS Lib WebSocket**: ws://[ALB-DNS-NAME]/ws/
- **Admin Interface**: http://[ALB-DNS-NAME]/admin/
- **Monitoring**: http://[ALB-DNS-NAME]/grafana/

## Troubleshooting

### Common Issues

#### 1. AWS Infrastructure Not Ready
```bash
# Run infrastructure setup first
./setup-aws-infrastructure.sh dev
```

#### 2. Service Health Check Failures
```bash
# Check service status
superdeploy status aeims-control --environment dev

# View service logs
superdeploy logs aeims-control --service aeims-core

# Restart specific service
superdeploy restart aeims-control --service aeims-core
```

#### 3. Database Connection Issues
```bash
# Check database status
superdeploy exec aeims-control --service aeims-core-postgres -- pg_isready

# View database logs
superdeploy logs aeims-control --service aeims-core-postgres
```

#### 4. Terraform Backend Issues
```bash
# Recreate S3 bucket and DynamoDB table
./setup-aws-infrastructure.sh dev

# Clear Terraform state
rm -rf terraform/.terraform
```

### Support

For technical support or deployment issues:
- **Email**: coleman.ryan@gmail.com
- **Response Time**: Within 24 hours
- **Emergency**: Use GitHub issues for urgent deployment problems

## Integration Testing

The platform includes comprehensive integration tests:

```bash
# Run integration tests
./tests/integration-test.sh dev

# Run tests via SuperDeploy
superdeploy test aeims-control --environment dev
```

## Monitoring and Observability

### Metrics Collection
- Service health and uptime
- Database connection pools
- Redis cache hit rates
- Load balancer response times
- Container resource utilization

### Dashboards
- **Grafana**: Real-time visualization dashboards
- **Prometheus**: Metrics collection and alerting
- **CloudWatch**: AWS native logging and metrics

### Alerting
- CPU/Memory threshold alerts
- Service availability alerts
- Database performance alerts
- Security event notifications

---

**The AEIMS platform is now ready for SuperDeploy integration and can be deployed across multiple environments with full compliance and monitoring capabilities.**