#!/bin/bash

# AEIMS Secrets Retrieval Script
# Generated automatically by Terraform for ${environment} environment
# Retrieves secrets from AWS Secrets Manager for local development

set -euo pipefail

# Configuration
PROJECT_NAME="${project_name}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

success() {
    log "$${GREEN}✓ $1$${NC}"
}

error() {
    log "$${RED}✗ $1$${NC}"
}

warning() {
    log "$${YELLOW}⚠ $1$${NC}"
}

info() {
    log "$${BLUE}ℹ $1$${NC}"
}

# Check AWS CLI
check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi

    success "AWS CLI configured and working"
}

# Get secret value
get_secret() {
    local secret_name=$1
    local output_file=$2

    info "Retrieving secret: $secret_name"

    if aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text > "$output_file" 2>/dev/null; then
        success "Retrieved secret: $secret_name"
        return 0
    else
        error "Failed to retrieve secret: $secret_name"
        return 1
    fi
}

# Extract environment variables from secret
extract_env_vars() {
    local secret_file=$1
    local service_name=$2
    local env_file="$service_name.env"

    info "Extracting environment variables for $service_name"

    if [[ -f "$secret_file" ]]; then
        # Parse JSON and create .env file
        cat "$secret_file" | jq -r 'to_entries[] | "\(.key | ascii_upcase)=\(.value)"' > "$env_file"
        success "Created environment file: $env_file"
    else
        warning "Secret file not found: $secret_file"
    fi
}

# Main function
main() {
    local action=$${1:-"fetch"}
    local service=$${2:-"all"}

    info "AEIMS Secrets Manager for $ENVIRONMENT environment"

    # Check prerequisites
    check_aws_cli

    case "$action" in
        "fetch")
            fetch_secrets "$service"
            ;;
        "env")
            generate_env_files "$service"
            ;;
        "list")
            list_secrets
            ;;
        "test")
            test_secrets
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# Fetch secrets
fetch_secrets() {
    local service=$1

    info "Fetching secrets for service: $service"

    # Create secrets directory
    mkdir -p secrets

    # Define secret mappings based on available secrets
    declare -A secret_mappings=(
        ["database"]="$PROJECT_NAME-$ENVIRONMENT-database-main"
        ["app-database"]="$PROJECT_NAME-$ENVIRONMENT-database-app"
        ["redis"]="$PROJECT_NAME-$ENVIRONMENT-redis-main"
        ["application"]="$PROJECT_NAME-$ENVIRONMENT-application"
        ["monitoring"]="$PROJECT_NAME-$ENVIRONMENT-monitoring"
        ["external"]="$PROJECT_NAME-$ENVIRONMENT-external"
        ["ssl"]="$PROJECT_NAME-$ENVIRONMENT-ssl"
    )

    if [[ "$service" == "all" ]]; then
        for secret_key in "$${!secret_mappings[@]}"; do
            get_secret "$${secret_mappings[$secret_key]}" "secrets/$secret_key.json" || true
        done
    elif [[ -n "$${secret_mappings[$service]:-}" ]]; then
        get_secret "$${secret_mappings[$service]}" "secrets/$service.json"
    else
        error "Unknown service: $service"
        exit 1
    fi
}

# Generate environment files
generate_env_files() {
    local service=$1

    info "Generating environment files for service: $service"

    if [[ "$service" == "all" ]]; then
        # Generate .env files for all services
        if [[ -f "secrets/database.json" ]]; then
            extract_env_vars "secrets/database.json" "aeims-core-db"
        fi

        if [[ -f "secrets/app-database.json" ]]; then
            extract_env_vars "secrets/app-database.json" "aeims-app-db"
        fi

        if [[ -f "secrets/application.json" ]]; then
            extract_env_vars "secrets/application.json" "aeims-app"
        fi

        # Create unified .env file
        cat > .env << EOF
# AEIMS Environment Configuration
# Generated from AWS Secrets Manager for $ENVIRONMENT environment
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

ENVIRONMENT=$ENVIRONMENT
AWS_REGION=$AWS_REGION
PROJECT_NAME=$PROJECT_NAME

EOF

        # Append database configuration
        if [[ -f "aeims-core-db.env" ]]; then
            echo "# Core Database Configuration" >> .env
            sed 's/^/AEIMS_CORE_DB_/' aeims-core-db.env >> .env
            echo "" >> .env
        fi

        # Append app database configuration
        if [[ -f "aeims-app-db.env" ]]; then
            echo "# App Database Configuration" >> .env
            sed 's/^/AEIMS_APP_DB_/' aeims-app-db.env >> .env
            echo "" >> .env
        fi

        # Append application secrets
        if [[ -f "aeims-app.env" ]]; then
            echo "# Application Secrets" >> .env
            cat aeims-app.env >> .env
            echo "" >> .env
        fi

        success "Generated unified .env file"
    else
        extract_env_vars "secrets/$service.json" "$service"
    fi
}

# List available secrets
list_secrets() {
    info "Listing available secrets for $PROJECT_NAME-$ENVIRONMENT"

    aws secretsmanager list-secrets \
        --region "$AWS_REGION" \
        --query "SecretList[?starts_with(Name, '$PROJECT_NAME-$ENVIRONMENT-')].{Name:Name,Description:Description}" \
        --output table
}

# Test secret access
test_secrets() {
    info "Testing secret access"

    local test_secret="$PROJECT_NAME-$ENVIRONMENT-application"

    if aws secretsmanager describe-secret \
        --secret-id "$test_secret" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        success "Can access secrets in $ENVIRONMENT environment"
    else
        error "Cannot access secrets in $ENVIRONMENT environment"
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
AEIMS Secrets Manager Script

Usage: $0 [ACTION] [SERVICE]

ACTIONS:
    fetch [SERVICE]     Fetch secrets from AWS Secrets Manager
    env [SERVICE]       Generate environment files from secrets
    list               List available secrets
    test               Test secret access
    help               Show this help message

SERVICES:
    all                All services (default)
    database           Core database secrets
    app-database       App database secrets
    redis              Redis secrets
    application        Application secrets
    monitoring         Monitoring secrets
    external           External service secrets
    ssl                SSL certificate secrets

EXAMPLES:
    # Fetch all secrets
    $0 fetch

    # Fetch database secrets only
    $0 fetch database

    # Generate environment files
    $0 env

    # List available secrets
    $0 list

    # Test secret access
    $0 test

ENVIRONMENT VARIABLES:
    AWS_PROFILE        AWS profile to use
    AWS_REGION         AWS region (overrides default)

Available Secrets for $PROJECT_NAME-$ENVIRONMENT:
%{~ for secret_name in secret_names ~}
    - ${secret_name}
%{~ endfor ~}

EOF
}

# Parse arguments and run
if [[ "$${BASH_SOURCE[0]}" == "$${0}" ]]; then
    case "$${1:-fetch}" in
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            main "$@"
            ;;
    esac
fi