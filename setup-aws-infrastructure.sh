#!/bin/bash

# AEIMS AWS Infrastructure Setup Script
# Creates necessary AWS resources before main deployment

set -euo pipefail

# Configuration
ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
PROJECT_NAME="aeims"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

failure() {
    echo -e "${RED}✗ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Create S3 bucket for Terraform state
create_terraform_state_bucket() {
    local bucket_name="${PROJECT_NAME}-terraform-state-${ENVIRONMENT}"

    info "Creating S3 bucket for Terraform state: $bucket_name"

    if aws s3 ls "s3://$bucket_name" >/dev/null 2>&1; then
        success "S3 bucket $bucket_name already exists"
    else
        if aws s3 mb "s3://$bucket_name" --region "$REGION"; then
            success "S3 bucket $bucket_name created"

            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$bucket_name" \
                --versioning-configuration Status=Enabled
            success "Versioning enabled for $bucket_name"

            # Block public access
            aws s3api put-public-access-block \
                --bucket "$bucket_name" \
                --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
            success "Public access blocked for $bucket_name"
        else
            failure "Failed to create S3 bucket $bucket_name"
            return 1
        fi
    fi
}

# Create DynamoDB table for Terraform locks
create_terraform_locks_table() {
    local table_name="${PROJECT_NAME}-terraform-locks-${ENVIRONMENT}"

    info "Creating DynamoDB table for Terraform locks: $table_name"

    if aws dynamodb describe-table --table-name "$table_name" --region "$REGION" >/dev/null 2>&1; then
        success "DynamoDB table $table_name already exists"
    else
        if aws dynamodb create-table \
            --table-name "$table_name" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$REGION" >/dev/null; then
            success "DynamoDB table $table_name created"

            # Wait for table to be active
            aws dynamodb wait table-exists --table-name "$table_name" --region "$REGION"
            success "DynamoDB table $table_name is active"
        else
            failure "Failed to create DynamoDB table $table_name"
            return 1
        fi
    fi
}

# Create ECR repositories
create_ecr_repositories() {
    local repositories=(
        "aeims-core"
        "aeims-app"
        "aeims-lib"
        "aeims-frontend"
        "aeims-user-service"
        "aeims-billing-service"
        "aeims-call-service"
        "aeims-operator-service"
        "aeims-conference-service"
        "aeims-notification-service"
        "aeims-analytics-service"
    )

    info "Creating ECR repositories..."

    for repo in "${repositories[@]}"; do
        local repo_name="${PROJECT_NAME}-${repo}-${ENVIRONMENT}"

        if aws ecr describe-repositories --repository-names "$repo_name" --region "$REGION" >/dev/null 2>&1; then
            success "ECR repository $repo_name already exists"
        else
            if aws ecr create-repository \
                --repository-name "$repo_name" \
                --image-scanning-configuration scanOnPush=true \
                --region "$REGION" >/dev/null; then
                success "ECR repository $repo_name created"
            else
                failure "Failed to create ECR repository $repo_name"
            fi
        fi
    done
}

# Main execution
main() {
    log "Setting up AWS infrastructure for AEIMS $ENVIRONMENT environment"
    log "Region: $REGION"
    log "Project: $PROJECT_NAME"
    log ""

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        failure "AWS credentials not configured or invalid"
        exit 1
    fi

    success "AWS credentials validated"

    # Create infrastructure
    create_terraform_state_bucket
    create_terraform_locks_table
    create_ecr_repositories

    log ""
    success "AWS infrastructure setup completed!"
    log ""
    log "You can now run the main deployment:"
    log "  ./deploy.sh --environment $ENVIRONMENT"
    log ""
    log "Or deploy via SuperDeploy:"
    log "  superdeploy deploy aeims-control --environment $ENVIRONMENT"
}

# Execute main function
main "$@"