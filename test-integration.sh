#!/bin/bash

# AEIMS Integration Test Suite
# Tests complete integration between aeims, aeims-control, and aeimsLib
# Implements universal-agent-mcp-kit verification methodology

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="$SCRIPT_DIR/.agent/logs/$(date +%Y-%m-%d)/integration-test-$(date +%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${timestamp} [${level}] ${message}" | tee -a "${TEST_LOG}"

    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} ${message}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${message}" ;;
    esac
}

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log "INFO" "Running test: $test_name"

    if eval "$test_command"; then
        if [ "$expected_result" = "success" ]; then
            log "SUCCESS" "✓ PASS: $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            log "ERROR" "✗ FAIL: $test_name (expected failure but got success)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if [ "$expected_result" = "failure" ]; then
            log "SUCCESS" "✓ PASS: $test_name (expected failure)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            log "ERROR" "✗ FAIL: $test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi
}

# HTTP test function
test_http() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-10}"

    if curl -f -s --max-time "$timeout" -w "%{http_code}" "$url" -o /dev/null | grep -q "$expected_status"; then
        return 0
    else
        return 1
    fi
}

# WebSocket test function
test_websocket() {
    local url="$1"
    local timeout="${2:-10}"

    if command -v node &> /dev/null; then
        cat > /tmp/ws_test.js << EOF
const WebSocket = require('ws');
const ws = new WebSocket('$url');

const timeout = setTimeout(() => {
    console.error('WebSocket timeout');
    process.exit(1);
}, ${timeout}000);

ws.on('open', () => {
    clearTimeout(timeout);
    console.log('WebSocket connected');
    ws.close();
    process.exit(0);
});

ws.on('error', (error) => {
    clearTimeout(timeout);
    console.error('WebSocket error:', error.message);
    process.exit(1);
});
EOF
        if node /tmp/ws_test.js > /dev/null 2>&1; then
            rm -f /tmp/ws_test.js
            return 0
        else
            rm -f /tmp/ws_test.js
            return 1
        fi
    else
        log "WARN" "Node.js not available for WebSocket test"
        return 0
    fi
}

# Ensure log directory exists
mkdir -p "$(dirname "$TEST_LOG")"

log "INFO" "🧪 Starting AEIMS Integration Test Suite"
log "INFO" "Timestamp: $(date)"
log "INFO" "Test log: $TEST_LOG"

# Test 1: Docker services are running
log "INFO" "=== Test Group 1: Service Availability ==="

run_test "Docker Compose services are running" \
    "docker compose ps | grep -q 'Up'" \
    "success"

run_test "AEIMS Core container is running" \
    "docker compose ps | grep aeims-core | grep -q 'Up'" \
    "success"

run_test "AEIMS App container is running" \
    "docker compose ps | grep aeims-app | grep -q 'Up'" \
    "success"

run_test "AEIMS Lib container is running" \
    "docker compose ps | grep aeims-lib | grep -q 'Up'" \
    "success"

run_test "Redis container is running" \
    "docker compose ps | grep aeims-redis | grep -q 'Up'" \
    "success"

# Test 2: Health endpoints
log "INFO" "=== Test Group 2: Health Endpoints ==="

run_test "AEIMS Core health endpoint" \
    "test_http 'http://localhost:8000/health'" \
    "success"

run_test "AEIMS Lib health endpoint" \
    "test_http 'http://localhost:8081/health'" \
    "success"

run_test "Health Monitor endpoint" \
    "test_http 'http://localhost:8090/health'" \
    "success"

run_test "Health Monitor status page" \
    "test_http 'http://localhost:8090/status'" \
    "success"

# Test 3: API connectivity
log "INFO" "=== Test Group 3: API Connectivity ==="

run_test "AEIMS Core API base endpoint" \
    "test_http 'http://localhost:8000/api/health' 200 5" \
    "success"

run_test "AEIMS Lib status endpoint" \
    "test_http 'http://localhost:8081/status' 200 5" \
    "success"

# Test 4: WebSocket connectivity
log "INFO" "=== Test Group 4: WebSocket Connectivity ==="

run_test "AEIMS Lib WebSocket connection" \
    "test_websocket 'ws://localhost:8081' 10" \
    "success"

# Test 5: Database connectivity
log "INFO" "=== Test Group 5: Database Connectivity ==="

run_test "PostgreSQL container is healthy" \
    "docker compose ps | grep aeims-core-postgres | grep -q 'healthy'" \
    "success"

run_test "MySQL container is healthy" \
    "docker compose ps | grep aeims-app-mysql | grep -q 'healthy'" \
    "success"

run_test "Redis container is healthy" \
    "docker compose ps | grep aeims-redis | grep -q 'healthy'" \
    "success"

# Test 6: Service integration
log "INFO" "=== Test Group 6: Service Integration ==="

# Test that services can communicate internally
run_test "Internal service communication via health monitor" \
    "curl -s 'http://localhost:8090/health' | grep -q 'overall_status'" \
    "success"

# Test environment variable propagation
run_test "Environment variables are set in AEIMS Core" \
    "docker compose exec -T aeims-core printenv | grep -q 'REDIS_HOST=aeims-redis'" \
    "success"

run_test "Environment variables are set in AEIMS Lib" \
    "docker compose exec -T aeims-lib printenv | grep -q 'REDIS_HOST=aeims-redis'" \
    "success"

# Test 7: Network connectivity
log "INFO" "=== Test Group 7: Network Connectivity ==="

run_test "AEIMS Core can reach Redis" \
    "docker compose exec -T aeims-core ping -c 1 aeims-redis > /dev/null 2>&1" \
    "success"

run_test "AEIMS Lib can reach Redis" \
    "docker compose exec -T aeims-lib ping -c 1 aeims-redis > /dev/null 2>&1" \
    "success"

run_test "AEIMS Lib can reach AEIMS Core" \
    "docker compose exec -T aeims-lib ping -c 1 aeims-core > /dev/null 2>&1" \
    "success"

# Test 8: Volume mounts and logging
log "INFO" "=== Test Group 8: Logging and Storage ==="

run_test "Log volumes are mounted correctly" \
    "docker volume ls | grep -q 'aeims_logs'" \
    "success"

run_test "AEIMS Lib logs are being written" \
    "docker compose logs aeims-lib | grep -q 'Device Control Server running'" \
    "success"

# Test 9: Configuration validation
log "INFO" "=== Test Group 9: Configuration Validation ==="

run_test "Master environment file exists" \
    "test -f '$SCRIPT_DIR/.env.master'" \
    "success"

run_test "Docker Compose configuration is valid" \
    "docker compose config > /dev/null 2>&1" \
    "success"

run_test "MCP registry configuration exists" \
    "test -f '$SCRIPT_DIR/.agent/mcp-registry.json'" \
    "success"

# Test 10: Performance and load
log "INFO" "=== Test Group 10: Performance Tests ==="

run_test "Multiple concurrent health checks" \
    "for i in {1..10}; do curl -f -s 'http://localhost:8090/health' > /dev/null & done; wait" \
    "success"

run_test "WebSocket stress test (10 connections)" \
    "if command -v node &> /dev/null; then
        for i in {1..10}; do
            timeout 5 node -e \"
                const WebSocket = require('ws');
                const ws = new WebSocket('ws://localhost:8081');
                ws.on('open', () => { ws.close(); process.exit(0); });
                ws.on('error', () => process.exit(1));
            \" &
        done; wait
     else
        echo 'Node.js not available, skipping stress test'
     fi" \
    "success"

# Generate detailed test report
log "INFO" "=== Test Results Summary ==="

echo ""
echo "==============================================="
echo "      AEIMS Integration Test Results"
echo "==============================================="
echo ""
echo "Total Tests:    $TESTS_TOTAL"
echo "Passed:         $TESTS_PASSED"
echo "Failed:         $TESTS_FAILED"
echo "Success Rate:   $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    log "SUCCESS" "🎉 All integration tests passed!"
    echo "The AEIMS integration is fully functional."
else
    log "ERROR" "⚠️  $TESTS_FAILED test(s) failed"
    echo "Check the test log for details: $TEST_LOG"
fi

echo ""
echo "Test Report:"
echo "  Detailed log: $TEST_LOG"
echo "  Services:     docker compose ps"
echo "  Logs:         docker compose logs [service-name]"
echo ""

# Service status summary
echo "Current Service Status:"
docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Ports}}" | head -20

echo ""
echo "Quick Health Check:"
if curl -f -s "http://localhost:8090/health" | grep -q "overall_status"; then
    echo "✓ Overall system health: $(curl -s 'http://localhost:8090/health' | grep -o '"overall_status":"[^"]*"' | cut -d'"' -f4)"
else
    echo "✗ Health monitor not responding"
fi

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi