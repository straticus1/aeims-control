# AEIMS Infrastructure Management System - Installation Guide

**Version:** 2.2.0 | **Date:** 2025-11-06

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Requirements](#system-requirements)
3. [Installation Steps](#installation-steps)
4. [Configuration](#configuration)
5. [Verification](#verification)
6. [First Deployment](#first-deployment)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before installing AEIMS Infrastructure Management System, ensure you have the following tools and services configured:

### Required Tools

| Tool | Minimum Version | Purpose | Installation |
|------|----------------|---------|--------------|
| **AWS CLI** | 2.x | AWS resource management | [Install AWS CLI](https://aws.amazon.com/cli/) |
| **Terraform** | 1.5+ | Infrastructure as Code | [Install Terraform](https://www.terraform.io/downloads) |
| **Ansible** | 2.10+ | Configuration management | `pip install ansible` |
| **Docker** | 20.10+ | Container runtime | [Install Docker](https://docs.docker.com/get-docker/) |
| **Docker Compose** | 2.x | Multi-container orchestration | Included with Docker Desktop |
| **jq** | 1.6+ | JSON processing | `brew install jq` (macOS) or `apt-get install jq` (Linux) |
| **Node.js** | 16+ | Testing and utilities | [Install Node.js](https://nodejs.org/) |
| **Git** | 2.x | Version control | [Install Git](https://git-scm.com/) |

### AWS Account Setup

```bash
# Configure AWS credentials
aws configure

# Required information:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (e.g., us-east-1)
# - Output format (json)

# Verify AWS configuration
aws sts get-caller-identity
```

### Required AWS Services Access

Ensure your AWS account has access to and appropriate permissions for:

- **ECS (Elastic Container Service)** - Container orchestration
- **RDS (Relational Database Service)** - Managed databases
- **ElastiCache** - Redis caching
- **VPC** - Virtual Private Cloud networking
- **ALB** - Application Load Balancer
- **Route53** - DNS management
- **ACM** - SSL/TLS certificate management
- **CloudWatch** - Logging and monitoring
- **S3** - Object storage
- **IAM** - Identity and Access Management
- **KMS** - Key Management Service
- **EFS** - Elastic File System

---

## System Requirements

### Development Environment

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 8 GB | 16+ GB |
| **Disk Space** | 20 GB | 50+ GB |
| **OS** | macOS 10.15+, Ubuntu 20.04+, or Windows 10+ with WSL2 | macOS 12+, Ubuntu 22.04+ |

### Production Environment (AWS)

| Component | Configuration |
|-----------|--------------|
| **ECS Tasks** | 2 vCPUs, 4GB RAM per service (minimum) |
| **RDS PostgreSQL** | db.t3.medium or larger |
| **RDS MySQL** | db.t3.medium or larger |
| **ElastiCache Redis** | cache.t3.medium or larger |
| **ALB** | Application Load Balancer (multi-AZ) |
| **EFS** | General Purpose with provisioned throughput |

---

## Installation Steps

### 1. Clone the Repository

```bash
# Clone aeims-control repository
cd ~/development
git clone https://github.com/yourusername/aeims-control.git
cd aeims-control

# Verify you're on the correct branch
git branch
```

### 2. Clone Related Repositories

AEIMS Infrastructure Management System manages three primary repositories:

```bash
cd ~/development

# Clone AEIMS Core (telephony platform)
git clone https://github.com/yourusername/aeims.git

# Clone AEIMS App (website and admin)
git clone https://github.com/yourusername/aeims.app.git

# Clone AEIMS Lib (device management)
git clone https://github.com/yourusername/aeimsLib.git

# Verify directory structure
ls -la ~/development/
# Should show: aeims/ aeims.app/ aeimsLib/ aeims-control/
```

### 3. Install Control Plane CLI

```bash
# Make aeims-ctl executable
chmod +x ~/development/aeims-control/bin/aeims-ctl
chmod +x ~/development/aeims-control/bin/aeims-remote

# Add to PATH (choose your shell)
# For Zsh (macOS default):
echo 'export PATH="$HOME/development/aeims-control/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# For Bash:
echo 'export PATH="$HOME/development/aeims-control/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
aeims-ctl --version
aeims-ctl --help
```

### 4. Install Dependencies

```bash
cd ~/development/aeims-control

# Install Ansible collections
ansible-galaxy collection install community.docker
ansible-galaxy collection install amazon.aws

# Install Python dependencies (if any)
pip install -r requirements.txt 2>/dev/null || echo "No Python requirements"

# Install Node.js dependencies for testing
cd tests
npm install
cd ..
```

### 5. Configure Docker

```bash
# Verify Docker is running
docker info

# Login to AWS ECR (if using AWS)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 515966511618.dkr.ecr.us-east-1.amazonaws.com

# Create Docker network (for local development)
docker network create aeims-network 2>/dev/null || echo "Network already exists"
```

---

## Configuration

### 1. Environment Configuration

```bash
cd ~/development/aeims-control

# Copy example environment file
cp .env.example .env

# Edit .env with your configuration
# Use your preferred editor (nano, vim, code, etc.)
nano .env
```

### Key Configuration Options

```bash
# Environment Settings
ENVIRONMENT=dev                    # Options: dev, staging, prod

# Database Configuration
AEIMS_CORE_DB_NAME=aeims_core
AEIMS_CORE_DB_USER=aeims_user
AEIMS_CORE_DB_PASS=<secure_password>

AEIMS_APP_DB_NAME=aeims_app
AEIMS_APP_DB_USER=aeims_user
AEIMS_APP_DB_PASS=<secure_password>

# Redis Configuration
REDIS_PASSWORD=<secure_redis_password>

# Service Ports
AEIMS_CORE_PORT=8000
AEIMS_APP_PORT=81
AEIMS_LIB_PORT=8080

# AWS Configuration (for cloud deployments)
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=<your_aws_account_id>
TF_STATE_BUCKET=aeims-terraform-state-dev

# Feature Flags
ENABLE_AEIMS_CORE=true
ENABLE_AEIMS_APP=true
ENABLE_AEIMS_LIB=true
ENABLE_MONITORING=true
```

### 2. Terraform Configuration

```bash
cd ~/development/aeims-control/terraform

# Copy example terraform variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform variables
nano terraform.tfvars
```

Example `terraform.tfvars`:

```hcl
# Basic Configuration
environment  = "dev"
aws_region   = "us-east-1"
project_name = "aeims"

# Infrastructure Sizing
vpc_cidr             = "10.0.0.0/16"
public_subnet_count  = 2
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
  aeims_app = {
    min_capacity = 2
    max_capacity = 8
    target_cpu   = 70
  }
}
```

### 3. Initialize Terraform Backend

```bash
cd ~/development/aeims-control/terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format Terraform files
terraform fmt -recursive
```

---

## Verification

### 1. Verify Tool Installations

```bash
# Create verification script
cat > /tmp/verify-install.sh << 'EOF'
#!/bin/bash
echo "🔍 Verifying AEIMS installation..."
echo ""

check_tool() {
  if command -v $1 &> /dev/null; then
    version=$($2)
    echo "✅ $1: $version"
  else
    echo "❌ $1: NOT FOUND"
  fi
}

check_tool "aws" "aws --version"
check_tool "terraform" "terraform version | head -n1"
check_tool "ansible" "ansible --version | head -n1"
check_tool "docker" "docker --version"
check_tool "docker-compose" "docker-compose --version"
check_tool "jq" "jq --version"
check_tool "node" "node --version"
check_tool "git" "git --version"
check_tool "aeims-ctl" "aeims-ctl --version"

echo ""
echo "🎯 Checking AWS connectivity..."
aws sts get-caller-identity &> /dev/null && echo "✅ AWS credentials valid" || echo "❌ AWS credentials invalid"

echo ""
echo "🐳 Checking Docker..."
docker info &> /dev/null && echo "✅ Docker is running" || echo "❌ Docker is not running"

EOF

chmod +x /tmp/verify-install.sh
/tmp/verify-install.sh
```

### 2. Verify Repository Structure

```bash
# Check directory structure
ls -la ~/development/aeims-control
ls -la ~/development/aeims
ls -la ~/development/aeims.app
ls -la ~/development/aeimsLib

# Verify aeims-ctl can list services
aeims-ctl list
```

### 3. Test Configuration

```bash
cd ~/development/aeims-control

# Validate environment file
if [ -f .env ]; then
  echo "✅ .env file exists"
  source .env
  echo "✅ Environment: $ENVIRONMENT"
else
  echo "❌ .env file missing"
fi

# Test Terraform configuration
cd terraform
terraform validate && echo "✅ Terraform configuration valid" || echo "❌ Terraform configuration invalid"
```

---

## First Deployment

### Local Development Deployment

```bash
cd ~/development/aeims-control

# Start all services locally
./deploy.sh --environment dev

# Or use Docker Compose directly
docker-compose up -d

# Check service status
aeims-ctl status

# View logs
aeims-ctl logs aeims-core
```

### Verify Services Are Running

```bash
# Use aeims-ctl to check all services
aeims-ctl health

# Or manually check endpoints
curl http://localhost:8000/health  # AEIMS Core
curl http://localhost:81/          # AEIMS App
curl http://localhost:8080/health  # AEIMS Lib

# Check containers
docker ps

# View all logs
aeims-ctl logs all
```

### Run Integration Tests

```bash
cd ~/development/aeims-control

# Run comprehensive integration tests
./tests/integration-test.sh dev

# Expected output: All tests passing
```

---

## Troubleshooting

### Common Issues

#### AWS Credentials Not Found

```bash
# Verify AWS configuration
aws configure list

# Test AWS access
aws sts get-caller-identity

# If needed, reconfigure
aws configure
```

#### Docker Not Running

```bash
# Check Docker status
docker info

# Start Docker Desktop (macOS)
open -a Docker

# Start Docker daemon (Linux)
sudo systemctl start docker
```

#### Port Conflicts

```bash
# Check what's using ports
lsof -i :8000
lsof -i :81
lsof -i :8080

# Stop conflicting services or change ports in .env
```

#### Database Connection Errors

```bash
# Check database containers
docker ps | grep postgres
docker ps | grep mysql

# View database logs
docker logs aeims-core-postgres
docker logs aeims-app-mysql

# Restart databases
docker-compose restart aeims-core-postgres
docker-compose restart aeims-app-mysql
```

#### aeims-ctl Command Not Found

```bash
# Check PATH
echo $PATH

# Verify file exists and is executable
ls -la ~/development/aeims-control/bin/aeims-ctl

# Make executable if needed
chmod +x ~/development/aeims-control/bin/aeims-ctl

# Re-add to PATH
export PATH="$HOME/development/aeims-control/bin:$PATH"
source ~/.zshrc  # or ~/.bashrc
```

#### Terraform State Lock

```bash
cd ~/development/aeims-control/terraform

# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Or delete local state and reinitialize (development only)
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### Getting Help

If you encounter issues not covered here:

1. **Check Documentation**:
   - [README.md](README.md) - Main documentation
   - [RECONCILIATION-USER-GUIDE.md](RECONCILIATION-USER-GUIDE.md) - Operational guidance
   - [docs/CONTROL-PLANE.md](docs/CONTROL-PLANE.md) - CLI reference

2. **Review Logs**:
   ```bash
   # Deployment logs
   ls -la logs/
   
   # Service logs
   aeims-ctl logs all
   ```

3. **Contact Support**:
   - **Email**: coleman.ryan@gmail.com
   - **Response Time**: Within 24 hours

---

## Next Steps

After successful installation:

1. **Read the Quick Start Guide**: [docs/AEIMS-CTL-QUICK-START.md](docs/AEIMS-CTL-QUICK-START.md)
2. **Review Control Plane Documentation**: [docs/CONTROL-PLANE.md](docs/CONTROL-PLANE.md)
3. **Understand Reconciliation Capabilities**: [RECONCILIATION-EXECUTIVE-SUMMARY.md](RECONCILIATION-EXECUTIVE-SUMMARY.md)
4. **Deploy to Staging**: `./deploy.sh --environment staging --plan-only`
5. **Configure Monitoring**: [docs/monitoring-setup.md](docs/monitoring-setup.md)

---

**Built with ❤️ by After Dark Systems**

*AEIMS Infrastructure Management System - Complete platform orchestration made simple*
