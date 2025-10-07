#!/bin/bash

# AEIMS Login Fix Deployment Script
# Restarts services with updated nginx configuration and API settings

set -e

echo "================================="
echo "🚀 AEIMS Login Fix Deployment"
echo "================================="

# Navigate to aeims-control directory
cd "$(dirname "$0")"

echo "📍 Current directory: $(pwd)"

# Check if docker compose is available (try new version first, then old)
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Neither 'docker compose' nor 'docker-compose' found. Please install Docker Compose first."
    exit 1
fi

echo "📦 Using: $DOCKER_COMPOSE"

# Stop existing services
echo "🛑 Stopping existing services..."
$DOCKER_COMPOSE down --remove-orphans

# Remove old frontend image to force rebuild
echo "🗑️ Removing old frontend image..."
docker image rm aeims-control-aeims-frontend:latest 2>/dev/null || true

# Pull latest base images
echo "📥 Pulling latest base images..."
$DOCKER_COMPOSE pull aeims-core-postgres aeims-app-mysql aeims-redis

# Rebuild and start services
echo "🏗️ Building and starting services..."
$DOCKER_COMPOSE up -d --build

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Check service status
echo "🔍 Checking service health..."
$DOCKER_COMPOSE ps

# Show important URLs and credentials
echo ""
echo "================================="
echo "✅ DEPLOYMENT COMPLETE!"
echo "================================="
echo ""
echo "🌐 IMPORTANT URLS:"
echo "   Login Portal: https://login.sexacomms.com"
echo "   API Gateway: https://api.sexacomms.com"
echo "   Admin Panel: https://login.sexacomms.com/admin"
echo ""
echo "🔐 INITIAL CREDENTIALS:"
echo "   Email: admin@sexacomms.com"
echo "   Password: admin123"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   1. CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
echo "   2. The admin user has full system access"
echo "   3. Additional users available:"
echo "      - operator@sexacomms.com (password: admin123)"
echo "      - user@sexacomms.com (password: admin123)"
echo ""
echo "📊 MONITORING:"
echo "   Grafana: http://localhost:3001 (admin/admin123)"
echo "   Prometheus: http://localhost:9090"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "   Check logs: $DOCKER_COMPOSE logs -f [service-name]"
echo "   Service status: $DOCKER_COMPOSE ps"
echo "   Restart service: $DOCKER_COMPOSE restart [service-name]"
echo ""
echo "================================="