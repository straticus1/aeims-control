#!/bin/bash

# AEIMS Unified Deployment Pipeline
# Orchestrates deployment of aeims, aeims-control, and aeimsLib
# Implements universal-agent-mcp-kit methodology

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AEIMS_ROOT="/Users/ryan/development"
DEPLOY_LOG="$SCRIPT_DIR/.agent/logs/$(date +%Y-%m-%d)/deploy-$(date +%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${timestamp} [${level}] ${message}" | tee -a "${DEPLOY_LOG}"

    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} ${message}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${message}" ;;
    esac
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Ensure log directory exists
mkdir -p "$(dirname "$DEPLOY_LOG")"

log "INFO" "🚀 Starting AEIMS Unified Deployment Pipeline"
log "INFO" "Timestamp: $(date)"
log "INFO" "Deployment log: $DEPLOY_LOG"

# Step 1: Pre-deployment checks
log "INFO" "Step 1: Pre-deployment checks"

# Check if all repositories exist
for repo in aeims aeims-control aeimsLib; do
    if [ ! -d "$AEIMS_ROOT/$repo" ]; then
        error_exit "Repository $repo not found at $AEIMS_ROOT/$repo"
    fi
    log "SUCCESS" "✓ Repository $repo found"
done

# Check Docker
if ! command -v docker &> /dev/null; then
    error_exit "Docker is not installed or not in PATH"
fi
log "SUCCESS" "✓ Docker is available"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    error_exit "Docker Compose is not installed or not available"
fi
log "SUCCESS" "✓ Docker Compose is available"

# Check if environment file exists
if [ ! -f "$SCRIPT_DIR/.env.master" ]; then
    error_exit "Master environment file not found at $SCRIPT_DIR/.env.master"
fi
log "SUCCESS" "✓ Master environment configuration found"

# Step 2: Environment setup
log "INFO" "Step 2: Environment configuration setup"

# Copy master environment to each repository
cp "$SCRIPT_DIR/.env.master" "$AEIMS_ROOT/aeims/.env" || error_exit "Failed to copy .env to aeims"
cp "$SCRIPT_DIR/.env.master" "$AEIMS_ROOT/aeimsLib/.env" || error_exit "Failed to copy .env to aeimsLib"
cp "$SCRIPT_DIR/.env.master" "$SCRIPT_DIR/.env" || error_exit "Failed to copy .env to aeims-control"

log "SUCCESS" "✓ Environment files distributed to all repositories"

# Step 3: Infrastructure deployment (Terraform)
log "INFO" "Step 3: Infrastructure deployment"

cd "$SCRIPT_DIR/terraform"

# Initialize Terraform
log "INFO" "Initializing Terraform..."
terraform init -upgrade || error_exit "Terraform initialization failed"

# Validate Terraform configuration
log "INFO" "Validating Terraform configuration..."
terraform validate || error_exit "Terraform validation failed"

# Plan infrastructure changes
log "INFO" "Planning infrastructure changes..."
terraform plan -out=tfplan || error_exit "Terraform plan failed"

# Apply infrastructure changes (with confirmation)
if [ "${AUTO_APPROVE:-false}" = "true" ]; then
    log "INFO" "Applying infrastructure changes (auto-approved)..."
    terraform apply -auto-approve tfplan || error_exit "Terraform apply failed"
else
    log "WARN" "Infrastructure plan ready. Set AUTO_APPROVE=true to auto-apply, or run manually:"
    log "WARN" "cd $SCRIPT_DIR/terraform && terraform apply tfplan"
fi

cd "$SCRIPT_DIR"
log "SUCCESS" "✓ Infrastructure deployment completed"

# Step 4: Application builds
log "INFO" "Step 4: Building application services"

# Stop existing services
log "INFO" "Stopping existing services..."
docker compose down --remove-orphans || log "WARN" "Some services may not have been running"

# Pull latest base images
log "INFO" "Pulling latest base images..."
docker compose pull || log "WARN" "Some base images may not be available"

# Build all services in parallel
log "INFO" "Building all services..."
docker compose build --parallel || error_exit "Docker build failed"

log "SUCCESS" "✓ All services built successfully"

# Step 5: Service deployment
log "INFO" "Step 5: Deploying services"

# Start databases first
log "INFO" "Starting database services..."
docker compose up -d aeims-core-postgres aeims-app-mysql aeims-redis

# Wait for databases to be healthy
log "INFO" "Waiting for databases to be healthy..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker compose ps | grep -E "(postgres|mysql|redis)" | grep -q "healthy"; then
        log "SUCCESS" "✓ Databases are healthy"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log "INFO" "Waiting for databases... (${elapsed}s/${timeout}s)"
done

if [ $elapsed -ge $timeout ]; then
    error_exit "Databases failed to become healthy within ${timeout} seconds"
fi

# Start core services
log "INFO" "Starting core services..."
docker compose up -d aeims-core aeims-lib

# Wait for core services
sleep 30

# Start application services
log "INFO" "Starting application services..."
docker compose up -d aeims-app aeims-frontend

# Start reverse proxy and monitoring
log "INFO" "Starting reverse proxy and monitoring..."
docker compose up -d aeims-nginx aeims-health-monitor

log "SUCCESS" "✓ All services deployed"

# Step 6: Health verification
log "INFO" "Step 6: Health verification"

# Function to check service health
check_service_health() {
    local service_name=$1
    local health_url=$2
    local max_attempts=30
    local attempt=1

    log "INFO" "Checking health of $service_name..."

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "$health_url" > /dev/null 2>&1; then
            log "SUCCESS" "✓ $service_name is healthy"
            return 0
        fi

        log "INFO" "Attempt $attempt/$max_attempts: $service_name not ready yet..."
        sleep 10
        attempt=$((attempt + 1))
    done

    log "ERROR" "✗ $service_name failed health check"
    return 1
}

# Check all services
health_checks_passed=true

# Check individual services
check_service_health "AEIMS Core" "http://localhost:8000/health" || health_checks_passed=false
check_service_health "AEIMS App" "http://localhost/health.php" || health_checks_passed=false
check_service_health "AEIMS Lib" "http://localhost:8081/health" || health_checks_passed=false
check_service_health "Health Monitor" "http://localhost:8090/health" || health_checks_passed=false

if [ "$health_checks_passed" = true ]; then
    log "SUCCESS" "✓ All health checks passed"
else
    error_exit "Some health checks failed"
fi

# Step 7: Integration tests
log "INFO" "Step 7: Running integration tests"

# Test WebSocket connectivity
log "INFO" "Testing WebSocket connectivity..."
if command -v node &> /dev/null; then
    cat > /tmp/websocket_test.js << 'EOF'
const WebSocket = require('ws');
const ws = new WebSocket('ws://localhost:8081');

ws.on('open', () => {
    console.log('WebSocket connection successful');
    ws.close();
    process.exit(0);
});

ws.on('error', (error) => {
    console.error('WebSocket connection failed:', error.message);
    process.exit(1);
});

setTimeout(() => {
    console.error('WebSocket connection timeout');
    process.exit(1);
}, 10000);
EOF

    if node /tmp/websocket_test.js; then
        log "SUCCESS" "✓ WebSocket connectivity test passed"
    else
        log "ERROR" "✗ WebSocket connectivity test failed"
        health_checks_passed=false
    fi
    rm -f /tmp/websocket_test.js
else
    log "WARN" "Node.js not available, skipping WebSocket test"
fi

# Test service communication
log "INFO" "Testing service communication..."
if curl -f -s "http://localhost:8000/api/health" > /dev/null 2>&1; then
    log "SUCCESS" "✓ AEIMS Core API accessible"
else
    log "ERROR" "✗ AEIMS Core API not accessible"
    health_checks_passed=false
fi

# Step 8: Deployment summary
log "INFO" "Step 8: Deployment summary"

echo ""
echo "==============================================="
echo "     AEIMS Unified Deployment Summary"
echo "==============================================="

# Show running services
echo ""
echo "Running Services:"
docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Ports}}"

echo ""
echo "Service URLs:"
echo "  AEIMS Core:        http://localhost:8000"
echo "  AEIMS App:         http://localhost"
echo "  AEIMS Lib:         http://localhost:8081"
echo "  Health Monitor:    http://localhost:8090"
echo "  Prometheus:        http://localhost:9090"
echo "  Grafana:           http://localhost:3001"

echo ""
echo "Health Check URLs:"
echo "  Overall Health:    http://localhost:8090/health"
echo "  Core Health:       http://localhost:8000/health"
echo "  App Health:        http://localhost/health.php"
echo "  Lib Health:        http://localhost:8081/health"
echo "  Status Dashboard:  http://localhost:8090/status"

echo ""
if [ "$health_checks_passed" = true ]; then
    log "SUCCESS" "🎉 AEIMS Unified Deployment completed successfully!"
    echo "All services are healthy and ready to use."
else
    log "ERROR" "⚠️  AEIMS Deployment completed with warnings"
    echo "Some health checks failed. Check the logs for details."
fi

echo ""
echo "Deployment log saved to: $DEPLOY_LOG"
echo "To view logs: docker-compose logs -f [service-name]"
echo "To stop all services: docker-compose down"
echo ""

# Return appropriate exit code
if [ "$health_checks_passed" = true ]; then
    exit 0
else
    exit 1
fi