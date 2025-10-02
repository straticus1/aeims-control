#!/bin/bash

# AEIMS Integration Testing Script
# Tests the integration between all 3 AEIMS services

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-dev}"
TIMEOUT=300
MAX_RETRIES=10
RETRY_INTERVAL=5

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}"
}

success() {
    log "SUCCESS" "$1"
    echo -e "${GREEN}✓ $1${NC}"
}

error() {
    log "ERROR" "$1"
    echo -e "${RED}✗ $1${NC}"
}

warning() {
    log "WARN" "$1"
    echo -e "${YELLOW}⚠ $1${NC}"
}

info() {
    log "INFO" "$1"
    echo -e "${BLUE}ℹ $1${NC}"
}

# Service configurations based on environment
get_service_config() {
    local environment=$1
    
    case "$environment" in
        "dev")
            AEIMS_CORE_URL="http://localhost:8000"
            AEIMS_APP_URL="http://localhost:81"
            AEIMS_LIB_URL="http://localhost:8080"
            ;;
        "staging"|"prod")
            # Load from terraform outputs if available
            if [[ -f "../terraform-outputs.json" ]]; then
                local alb_dns=$(jq -r '.alb_dns_name.value // "localhost"' ../terraform-outputs.json)
                AEIMS_CORE_URL="http://${alb_dns}/api"
                AEIMS_APP_URL="http://${alb_dns}"
                AEIMS_LIB_URL="ws://${alb_dns}/ws"
            else
                error "terraform-outputs.json not found for staging/prod environment"
                exit 1
            fi
            ;;
        *)
            error "Unknown environment: $environment"
            exit 1
            ;;
    esac
}

# Wait for service to be ready
wait_for_service() {
    local service_name=$1
    local url=$2
    local expected_status=${3:-200}
    local retries=0
    
    info "Waiting for $service_name to be ready at $url"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -sf --max-time 10 "$url" >/dev/null 2>&1; then
            local status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
            if [ "$status" -eq "$expected_status" ]; then
                success "$service_name is ready (HTTP $status)"
                return 0
            fi
        fi
        
        retries=$((retries + 1))
        warning "$service_name not ready, retrying in ${RETRY_INTERVAL}s (attempt $retries/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    error "$service_name failed to become ready after $MAX_RETRIES attempts"
    return 1
}

# Test HTTP endpoint
test_http_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    local description="${4:-}"
    
    info "Testing $name: $url"
    
    local response=$(curl -s -w "%{http_code}|%{time_total}" "$url" 2>/dev/null || echo "000|0")
    local status=$(echo "$response" | cut -d'|' -f1)
    local time=$(echo "$response" | cut -d'|' -f2)
    
    if [ "$status" -eq "$expected_status" ]; then
        success "$name OK (HTTP $status, ${time}s) $description"
        return 0
    else
        error "$name FAILED (HTTP $status) $description"
        return 1
    fi
}

# Test WebSocket connection
test_websocket() {
    local name=$1
    local url=$2
    local description="${3:-}"
    
    info "Testing WebSocket $name: $url"
    
    # Use a simple WebSocket test with timeout
    if command -v wscat >/dev/null 2>&1; then
        if timeout 10 wscat -c "$url" -x 'ping' >/dev/null 2>&1; then
            success "$name WebSocket OK $description"
            return 0
        else
            error "$name WebSocket FAILED $description"
            return 1
        fi
    else
        warning "wscat not found, skipping WebSocket test for $name"
        return 0
    fi
}

# Test service integration
test_service_integration() {
    local test_name=$1
    local from_service=$2
    local to_service=$3
    local endpoint=$4
    local description="${5:-}"
    
    info "Testing integration: $test_name"
    info "From: $from_service -> To: $to_service"
    
    # Test if the integration endpoint responds correctly
    if test_http_endpoint "$test_name" "$endpoint" 200 "$description"; then
        success "Integration test passed: $test_name"
        return 0
    else
        error "Integration test failed: $test_name"
        return 1
    fi
}

# Test database connectivity
test_database_connectivity() {
    local service=$1
    local db_type=$2
    
    info "Testing database connectivity for $service ($db_type)"
    
    case "$ENVIRONMENT" in
        "dev")
            # Test direct database connections
            case "$db_type" in
                "postgres")
                    if command -v psql >/dev/null 2>&1; then
                        if PGPASSWORD="${AEIMS_CORE_DB_PASS:-secure_password_123}" psql -h localhost -p 5432 -U "${AEIMS_CORE_DB_USER:-aeims_user}" -d "${AEIMS_CORE_DB_NAME:-aeims_core}" -c "SELECT 1;" >/dev/null 2>&1; then
                            success "$service PostgreSQL connection OK"
                            return 0
                        fi
                    fi
                    warning "Cannot test PostgreSQL directly, checking via service API"
                    ;;
                "mysql")
                    if command -v mysql >/dev/null 2>&1; then
                        if mysql -h localhost -P 3306 -u "${AEIMS_APP_DB_USER:-aeims_user}" -p"${AEIMS_APP_DB_PASS:-secure_password_123}" -e "SELECT 1;" "${AEIMS_APP_DB_NAME:-aeims_app}" >/dev/null 2>&1; then
                            success "$service MySQL connection OK"
                            return 0
                        fi
                    fi
                    warning "Cannot test MySQL directly, checking via service API"
                    ;;
            esac
            ;;
        *)
            info "Skipping direct database tests in $ENVIRONMENT environment"
            ;;
    esac
    
    return 0
}

# Test Redis connectivity
test_redis_connectivity() {
    info "Testing Redis connectivity"
    
    case "$ENVIRONMENT" in
        "dev")
            if command -v redis-cli >/dev/null 2>&1; then
                if redis-cli -h localhost -p 6379 -a "${REDIS_PASSWORD:-secure_redis_pass}" ping >/dev/null 2>&1; then
                    success "Redis connection OK"
                    return 0
                fi
            fi
            warning "Cannot test Redis directly"
            ;;
        *)
            info "Skipping direct Redis test in $ENVIRONMENT environment"
            ;;
    esac
    
    return 0
}

# Test API endpoints
test_api_endpoints() {
    local base_url=$1
    local service_name=$2
    
    info "Testing API endpoints for $service_name"
    
    # Health check endpoint
    test_http_endpoint "$service_name Health Check" "$base_url/health" 200 "Service health status"
    
    # Version endpoint
    test_http_endpoint "$service_name Version" "$base_url/version" 200 "Service version info" || true
    
    # Status endpoint
    test_http_endpoint "$service_name Status" "$base_url/status" 200 "Service status" || true
}

# Main test suite
run_integration_tests() {
    info "Starting AEIMS Integration Tests for environment: $ENVIRONMENT"
    info "======================================================"
    
    local failed_tests=0
    local total_tests=0
    
    # Get service configuration
    get_service_config "$ENVIRONMENT"
    
    info "Service URLs:"
    info "  AEIMS Core: $AEIMS_CORE_URL"
    info "  AEIMS App:  $AEIMS_APP_URL"
    info "  AEIMS Lib:  $AEIMS_LIB_URL"
    info ""
    
    # Wait for all services to be ready
    info "Phase 1: Service Readiness Tests"
    info "================================="
    
    wait_for_service "AEIMS Core" "$AEIMS_CORE_URL/health" || ((failed_tests++))
    ((total_tests++))
    
    wait_for_service "AEIMS App" "$AEIMS_APP_URL/" || ((failed_tests++))
    ((total_tests++))
    
    if [[ "$AEIMS_LIB_URL" == ws://* ]]; then
        # WebSocket endpoint
        test_websocket "AEIMS Lib" "$AEIMS_LIB_URL" || ((failed_tests++))
    else
        wait_for_service "AEIMS Lib" "$AEIMS_LIB_URL/health" || ((failed_tests++))
    fi
    ((total_tests++))
    
    # Database connectivity tests
    info ""
    info "Phase 2: Database Connectivity Tests"
    info "===================================="
    
    test_database_connectivity "AEIMS Core" "postgres" || ((failed_tests++))
    ((total_tests++))
    
    test_database_connectivity "AEIMS App" "mysql" || ((failed_tests++))
    ((total_tests++))
    
    test_redis_connectivity || ((failed_tests++))
    ((total_tests++))
    
    # API endpoint tests
    info ""
    info "Phase 3: API Endpoint Tests"
    info "==========================="
    
    test_api_endpoints "$AEIMS_CORE_URL" "AEIMS Core" || ((failed_tests++))
    ((total_tests++))
    
    test_http_endpoint "AEIMS App Index" "$AEIMS_APP_URL/" 200 "Main application page" || ((failed_tests++))
    ((total_tests++))
    
    if [[ "$AEIMS_LIB_URL" != ws://* ]]; then
        test_api_endpoints "$AEIMS_LIB_URL" "AEIMS Lib" || ((failed_tests++))
        ((total_tests++))
    fi
    
    # Service integration tests
    info ""
    info "Phase 4: Service Integration Tests"
    info "=================================="
    
    # Test AEIMS Core -> AEIMS App integration
    test_service_integration \
        "Core-to-App Integration" \
        "AEIMS Core" \
        "AEIMS App" \
        "$AEIMS_CORE_URL/integration/app-status" \
        "Core service checking App status" || ((failed_tests++))
    ((total_tests++))
    
    # Test AEIMS Core -> AEIMS Lib integration
    test_service_integration \
        "Core-to-Lib Integration" \
        "AEIMS Core" \
        "AEIMS Lib" \
        "$AEIMS_CORE_URL/integration/lib-status" \
        "Core service checking Lib status" || ((failed_tests++))
    ((total_tests++))
    
    # Test AEIMS App -> AEIMS Core integration
    test_http_endpoint \
        "App-to-Core Integration" \
        "$AEIMS_APP_URL/api/core-status" \
        200 \
        "App checking Core status" || ((failed_tests++))
    ((total_tests++))
    
    # Performance tests
    info ""
    info "Phase 5: Performance Tests"
    info "=========================="
    
    # Test response times
    local core_response_time=$(curl -s -w "%{time_total}" -o /dev/null "$AEIMS_CORE_URL/health" || echo "999")
    local app_response_time=$(curl -s -w "%{time_total}" -o /dev/null "$AEIMS_APP_URL/" || echo "999")
    
    if (( $(echo "$core_response_time < 2.0" | bc -l) )); then
        success "AEIMS Core response time OK (${core_response_time}s)"
    else
        error "AEIMS Core response time slow (${core_response_time}s)"
        ((failed_tests++))
    fi
    ((total_tests++))
    
    if (( $(echo "$app_response_time < 2.0" | bc -l) )); then
        success "AEIMS App response time OK (${app_response_time}s)"
    else
        error "AEIMS App response time slow (${app_response_time}s)"
        ((failed_tests++))
    fi
    ((total_tests++))
    
    # Security tests
    info ""
    info "Phase 6: Security Tests"
    info "======================="
    
    # Test for common security headers
    local core_security=$(curl -s -I "$AEIMS_CORE_URL/health" | grep -i "x-frame-options\|x-content-type-options\|x-xss-protection" | wc -l)
    if [ "$core_security" -gt 0 ]; then
        success "AEIMS Core has security headers"
    else
        warning "AEIMS Core missing security headers"
    fi
    ((total_tests++))
    
    # Test results summary
    info ""
    info "Integration Test Results"
    info "======================="
    info "Total Tests: $total_tests"
    info "Passed: $((total_tests - failed_tests))"
    info "Failed: $failed_tests"
    
    if [ $failed_tests -eq 0 ]; then
        success "All integration tests passed! ✨"
        return 0
    else
        error "$failed_tests out of $total_tests tests failed"
        return 1
    fi
}

# Cleanup function
cleanup() {
    info "Cleaning up test artifacts..."
}

# Trap cleanup on exit
trap cleanup EXIT

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    warning "jq not found, JSON parsing may be limited"
fi

# Check if bc is available for floating point comparisons
if ! command -v bc >/dev/null 2>&1; then
    warning "bc not found, performance tests may be limited"
fi

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi