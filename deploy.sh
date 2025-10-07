#!/bin/bash

# AEIMS Infrastructure Management System
# SuperDeploy-compatible deployment script
# Manages complete AEIMS ecosystem deployment with Terraform and Ansible

set -euo pipefail

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="aeims"
DEFAULT_ENVIRONMENT="dev"
DEFAULT_REGION="us-east-1"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Success message
success() {
    log "INFO" "$1"
    echo -e "${GREEN}$1${NC}"
}

# Warning message
warning() {
    log "WARN" "$1"
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Info message
info() {
    log "INFO" "$1"
    echo -e "${BLUE}INFO: $1${NC}"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

AEIMS Infrastructure Management System Deployment Script
Compatible with SuperDeploy deployment patterns

OPTIONS:
    --environment, -e ENV       Environment (dev, staging, prod) [default: ${DEFAULT_ENVIRONMENT}]
    --region, -r REGION         AWS region [default: ${DEFAULT_REGION}]
    --auto-approve              Auto-approve all prompts
    --plan-only                 Show deployment plan without making changes
    --infrastructure-only       Deploy infrastructure only (Terraform)
    --application-only          Deploy applications only (Ansible)
    --verbose                   Enable verbose output
    --help, -h                  Show this help message

EXAMPLES:
    # Deploy development environment
    $0 --environment dev

    # Plan production deployment
    $0 --environment prod --plan-only

    # Deploy infrastructure only
    $0 --environment staging --infrastructure-only

    # Deploy with auto-approval
    $0 --environment prod --auto-approve

SUPERDEPLOY COMPATIBILITY:
    This script is fully compatible with SuperDeploy and supports all
    standard SuperDeploy arguments and deployment patterns.

EOF
}

# Parse command line arguments
parse_args() {
    ENVIRONMENT="${DEFAULT_ENVIRONMENT}"
    REGION="${DEFAULT_REGION}"
    AUTO_APPROVE=false
    PLAN_ONLY=false
    INFRASTRUCTURE_ONLY=false
    APPLICATION_ONLY=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --region|-r)
                REGION="$2"
                shift 2
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --plan-only)
                PLAN_ONLY=true
                shift
                ;;
            --infrastructure-only)
                INFRASTRUCTURE_ONLY=true
                shift
                ;;
            --application-only)
                APPLICATION_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done

    # Validate environment
    case "${ENVIRONMENT}" in
        dev|staging|prod)
            ;;
        *)
            error_exit "Invalid environment: ${ENVIRONMENT}. Must be dev, staging, or prod."
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in aws terraform ansible docker jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured or invalid"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker daemon not running"
    fi
    
    # Verify source directories exist
    for dir in "../aeims" "../aeims.app" "../aeimsLib"; do
        if [[ ! -d "$dir" ]]; then
            error_exit "Source directory not found: $dir"
        fi
    done
    
    success "Prerequisites check passed"
}

# Initialize Terraform
init_terraform() {
    info "Initializing Terraform..."

    cd "${SCRIPT_DIR}/terraform"

    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f "terraform.tfvars" ]]; then
        cat > terraform.tfvars << EOF
# AEIMS Terraform Variables
environment = "${ENVIRONMENT}"
aws_region = "${REGION}"
project_name = "${PROJECT_NAME}"
EOF
        info "Created terraform.tfvars file"
    fi

    # Create backend configuration
    if [[ ! -f "backend.conf" ]]; then
        cat > backend.conf << EOF
bucket         = "${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"
key            = "aeims/terraform.tfstate"
region         = "${REGION}"
encrypt        = true
dynamodb_table = "${PROJECT_NAME}-terraform-locks-${ENVIRONMENT}"
EOF
        info "Created backend.conf file"
    fi

    # Initialize Terraform with backend config
    if terraform init -backend-config=backend.conf -upgrade; then
        success "Terraform initialized with remote backend"
    else
        warning "Remote backend initialization failed, initializing without backend"
        terraform init -upgrade
    fi

    # Validate configuration
    terraform validate

    success "Terraform initialized successfully"
    cd - >/dev/null
}

# Create Terraform plan
terraform_plan() {
    info "Creating Terraform plan..."
    
    cd "${SCRIPT_DIR}/terraform"
    
    local plan_file="plans/terraform-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).plan"
    mkdir -p plans
    
    terraform plan \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${REGION}" \
        -var="project_name=${PROJECT_NAME}" \
        -out="${plan_file}"
    
    echo "Plan saved to: ${plan_file}"
    
    if [[ "${PLAN_ONLY}" == "true" ]]; then
        success "Terraform plan completed (plan-only mode)"
        exit 0
    fi
    
    cd - >/dev/null
}

# Apply Terraform configuration
terraform_apply() {
    info "Applying Terraform configuration..."
    
    cd "${SCRIPT_DIR}/terraform"
    
    local apply_args=()
    
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        apply_args+=("-auto-approve")
    fi
    
    terraform apply "${apply_args[@]}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${REGION}" \
        -var="project_name=${PROJECT_NAME}"
    
    # Save Terraform outputs
    terraform output -json > "../terraform-outputs.json"
    
    success "Terraform infrastructure deployed successfully"
    cd - >/dev/null
}

# Run Ansible deployment
ansible_deploy() {
    info "Running Ansible deployment..."
    
    cd "${SCRIPT_DIR}/ansible"
    
    # Create ansible inventory
    cat > inventory.yml << EOF
---
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: "{{ ansible_playbook_python }}"
  vars:
    environment: "${ENVIRONMENT}"
    aws_region: "${REGION}"
    project_name: "${PROJECT_NAME}"
EOF
    
    # Prepare Ansible arguments
    local ansible_args=()
    ansible_args+=("--inventory" "inventory.yml")
    
    if [[ "${VERBOSE}" == "true" ]]; then
        ansible_args+=("--verbose")
    fi
    
    # Add environment-specific variables
    ansible_args+=("--extra-vars" "env=${ENVIRONMENT}")
    ansible_args+=("--extra-vars" "region=${REGION}")
    
    # Load Terraform outputs if available
    if [[ -f "../terraform-outputs.json" ]]; then
        ansible_args+=("--extra-vars" "@../terraform-outputs.json")
    fi
    
    # Run the playbook
    ansible-playbook "${ansible_args[@]}" deploy.yml
    
    success "Ansible deployment completed successfully"
    cd - >/dev/null
}

# Deploy Docker containers locally (for dev environment)
deploy_docker_local() {
    info "Deploying containers locally with Docker Compose..."
    
    # Use existing docker-compose files from the source directories
    local compose_files=()
    
    if [[ -f "../aeims/telephony-platform/docker-compose.yml" ]]; then
        compose_files+=("-f" "../aeims/telephony-platform/docker-compose.yml")
    fi
    
    if [[ -f "../aeims.app/infrastructure/docker-compose.yml" ]]; then
        compose_files+=("-f" "../aeims.app/infrastructure/docker-compose.yml")
    fi
    
    # Create override file for integration
    cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  # Integration network
  aeims-core:
    networks:
      - aeims-network
    environment:
      - AEIMS_APP_URL=http://aeims-app
      - AEIMS_LIB_URL=http://aeims-lib:8080
  
  aeims-app:
    networks:
      - aeims-network
    environment:
      - AEIMS_CORE_URL=http://aeims-core:8000
      - AEIMS_LIB_URL=http://aeims-lib:8080
  
  aeims-lib:
    build:
      context: ../aeimsLib
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    networks:
      - aeims-network
    environment:
      - AEIMS_CORE_URL=http://aeims-core:8000
      - AEIMS_APP_URL=http://aeims-app

networks:
  aeims-network:
    driver: bridge

EOF
    
    compose_files+=("-f" "docker-compose.override.yml")
    
    # Deploy with Docker Compose
    docker-compose "${compose_files[@]}" up -d --build
    
    success "Docker containers deployed locally"
}

# Integration tests
run_integration_tests() {
    info "Running integration tests..."
    
    local test_script="${SCRIPT_DIR}/tests/integration-test.sh"
    
    if [[ -f "$test_script" ]]; then
        bash "$test_script" "$ENVIRONMENT"
    else
        warning "Integration test script not found, skipping tests"
    fi
}

# Main deployment function
main() {
    info "Starting AEIMS deployment..."
    info "Environment: ${ENVIRONMENT}"
    info "Region: ${REGION}"
    info "Project: ${PROJECT_NAME}"
    
    # Record deployment start time
    local start_time=$(date +%s)
    
    # Check prerequisites
    check_prerequisites
    
    # Infrastructure deployment (Terraform)
    if [[ "${APPLICATION_ONLY}" != "true" ]]; then
        init_terraform
        terraform_plan
        
        if [[ "${PLAN_ONLY}" != "true" ]]; then
            terraform_apply
        fi
    fi
    
    # Application deployment (Ansible)
    if [[ "${INFRASTRUCTURE_ONLY}" != "true" && "${PLAN_ONLY}" != "true" ]]; then
        if [[ "${ENVIRONMENT}" == "dev" ]]; then
            deploy_docker_local
        else
            ansible_deploy
        fi
        
        # Run integration tests
        run_integration_tests
    fi
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Deployment summary
    success "====== AEIMS Deployment Complete ======"
    info "Environment: ${ENVIRONMENT}"
    info "Region: ${REGION}"
    info "Duration: ${duration} seconds"
    info "Log file: ${LOG_FILE}"
    
    if [[ "${ENVIRONMENT}" != "dev" && -f "terraform-outputs.json" ]]; then
        local alb_dns=$(jq -r '.alb_dns_name.value // "Not configured"' terraform-outputs.json)
        info "Load Balancer: ${alb_dns}"
        info "Access URLs:"
        info "  - AEIMS App: http://${alb_dns}/"
        info "  - AEIMS Core API: http://${alb_dns}/api/"
        info "  - AEIMS Lib WebSocket: ws://${alb_dns}/ws/"
    fi
    
    success "Deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi