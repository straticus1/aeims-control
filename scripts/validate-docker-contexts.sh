#!/bin/bash

# Docker Build Context Validation Script
# Validates all Docker build contexts and dependencies for AEIMS

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${ENVIRONMENT:-dev}"

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
    log "${GREEN}✓ $1${NC}"
}

error() {
    log "${RED}✗ $1${NC}"
}

warning() {
    log "${YELLOW}⚠ $1${NC}"
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

# Check if directory exists
check_directory() {
    local dir=$1
    local description=$2

    if [[ -d "$dir" ]]; then
        success "$description exists: $dir"
        return 0
    else
        error "$description missing: $dir"
        return 1
    fi
}

# Check if file exists
check_file() {
    local file=$1
    local description=$2

    if [[ -f "$file" ]]; then
        success "$description exists: $file"
        return 0
    else
        error "$description missing: $file"
        return 1
    fi
}

# Validate Docker context
validate_docker_context() {
    local service=$1
    local context=$2
    local dockerfile=$3

    info "Validating Docker context for $service"

    local full_context_path
    if [[ "$context" = /* ]]; then
        full_context_path="$context"
    else
        full_context_path="$PROJECT_ROOT/$context"
    fi

    local dockerfile_path="$full_context_path/$dockerfile"

    # Check context directory
    if ! check_directory "$full_context_path" "Context directory for $service"; then
        return 1
    fi

    # Check Dockerfile
    if ! check_file "$dockerfile_path" "Dockerfile for $service"; then
        return 1
    fi

    # Validate Dockerfile syntax
    if docker run --rm -i hadolint/hadolint < "$dockerfile_path" >/dev/null 2>&1; then
        success "Dockerfile syntax valid for $service"
    else
        warning "Dockerfile has linting issues for $service (non-blocking)"
    fi

    # Check for common build dependencies
    local common_files=(
        "package.json"
        "composer.json"
        "requirements.txt"
        "go.mod"
        "Cargo.toml"
    )

    for file in "${common_files[@]}"; do
        if [[ -f "$full_context_path/$file" ]]; then
            info "Found dependency file: $file"
        fi
    done

    return 0
}

# Test Docker build
test_docker_build() {
    local service=$1
    local context=$2
    local dockerfile=$3

    info "Testing Docker build for $service"

    local full_context_path
    if [[ "$context" = /* ]]; then
        full_context_path="$context"
    else
        full_context_path="$PROJECT_ROOT/$context"
    fi

    # Build with dry-run (syntax check only)
    if docker build --dry-run -f "$full_context_path/$dockerfile" "$full_context_path" >/dev/null 2>&1; then
        success "Docker build syntax valid for $service"
        return 0
    else
        error "Docker build syntax invalid for $service"
        return 1
    fi
}

# Main validation function
main() {
    info "Starting Docker context validation for AEIMS infrastructure"
    info "Environment: $ENVIRONMENT"
    info "Project root: $PROJECT_ROOT"

    local failed_validations=0
    local total_validations=0

    # Source directories validation
    info ""
    info "Phase 1: Source Directory Validation"
    info "===================================="

    local source_dirs=(
        "../aeims:AEIMS Core"
        "../aeims.app:AEIMS App"
        "../aeimsLib:AEIMS Lib"
    )

    for dir_info in "${source_dirs[@]}"; do
        IFS=':' read -r dir desc <<< "$dir_info"
        if ! check_directory "$PROJECT_ROOT/$dir" "$desc"; then
            ((failed_validations++))
        fi
        ((total_validations++))
    done

    # Docker context validation
    info ""
    info "Phase 2: Docker Context Validation"
    info "=================================="

    # Define services and their contexts
    declare -A docker_contexts=(
        ["aeims-core"]="../aeims/telephony-platform:Dockerfile"
        ["aeims-app"]="../aeims.app:infrastructure/Dockerfile"
        ["aeims-lib"]="../aeimsLib:Dockerfile"
        ["user-service"]="../aeims/telephony-platform/services/user-service:Dockerfile"
        ["billing-service"]="../aeims/telephony-platform/services/billing-service:Dockerfile"
        ["call-service"]="../aeims/telephony-platform/services/call-service:Dockerfile"
        ["operator-service"]="../aeims/telephony-platform/services/operator-service:Dockerfile"
        ["conference-service"]="../aeims/telephony-platform/services/conference-service:Dockerfile"
        ["notification-service"]="../aeims/telephony-platform/services/notification-service:Dockerfile"
        ["analytics-service"]="../aeims/telephony-platform/services/analytics-service:Dockerfile"
        ["frontend"]="../aeims/telephony-platform/frontend:Dockerfile"
    )

    for service in "${!docker_contexts[@]}"; do
        IFS=':' read -r context dockerfile <<< "${docker_contexts[$service]}"
        if ! validate_docker_context "$service" "$context" "$dockerfile"; then
            ((failed_validations++))
        fi
        ((total_validations++))
    done

    # Docker Compose validation
    info ""
    info "Phase 3: Docker Compose Validation"
    info "=================================="

    if check_file "$PROJECT_ROOT/docker-compose.yml" "Main Docker Compose file"; then
        # Validate compose file syntax
        if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" config >/dev/null 2>&1; then
            success "Docker Compose syntax valid"
        else
            error "Docker Compose syntax invalid"
            ((failed_validations++))
        fi
    else
        ((failed_validations++))
    fi
    ((total_validations++))

    # Dockerfile build test (optional)
    if [[ "${TEST_BUILDS:-false}" == "true" ]]; then
        info ""
        info "Phase 4: Docker Build Testing"
        info "============================="

        for service in "${!docker_contexts[@]}"; do
            IFS=':' read -r context dockerfile <<< "${docker_contexts[$service]}"
            if ! test_docker_build "$service" "$context" "$dockerfile"; then
                ((failed_validations++))
            fi
            ((total_validations++))
        done
    fi

    # Environment file validation
    info ""
    info "Phase 5: Environment Configuration"
    info "================================="

    local env_files=(
        ".env.example:Environment template"
        "../aeims/.env.example:AEIMS Core environment template"
        "../aeims.app/.env.example:AEIMS App environment template"
        "../aeimsLib/.env.example:AEIMS Lib environment template"
    )

    for env_info in "${env_files[@]}"; do
        IFS=':' read -r file desc <<< "$env_info"
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            success "$desc exists"
        else
            warning "$desc missing (optional): $file"
        fi
    done

    # Results summary
    info ""
    info "Validation Results"
    info "=================="
    info "Total validations: $total_validations"
    info "Passed: $((total_validations - failed_validations))"
    info "Failed: $failed_validations"

    if [[ $failed_validations -eq 0 ]]; then
        success "All Docker context validations passed! ✨"
        return 0
    else
        error "$failed_validations validation(s) failed"
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
Docker Context Validation Script for AEIMS

Usage: $0 [OPTIONS]

OPTIONS:
    --test-builds    Also test Docker builds (slower)
    --environment    Set environment (dev, staging, prod)
    --help, -h       Show this help message

EXAMPLES:
    # Basic validation
    $0

    # Full validation with build tests
    $0 --test-builds

    # Validate for staging environment
    $0 --environment staging

ENVIRONMENT VARIABLES:
    TEST_BUILDS      Set to 'true' to enable build testing
    ENVIRONMENT      Environment to validate for (dev, staging, prod)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-builds)
            TEST_BUILDS=true
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi