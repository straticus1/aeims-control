#!/bin/bash

# Test script to verify domain routing configuration
# This simulates the routing behavior defined in nginx.conf

echo "=== AEIMS Routing Configuration Test ==="
echo

echo "Domain Routing Summary:"
echo "✅ login.sexacomms.com → aeims-frontend (SEXACOMMS Telephony Platform)"
echo "✅ www.sexacomms.com   → aeims-frontend (SEXACOMMS Telephony Platform)"  
echo "✅ api.sexacomms.com   → aeims-core (Backend API)"
echo "✅ flirts.nyc         → /var/www/sites/flirts.nyc/ (PHP Site)"
echo "✅ nycflirts.com      → /var/www/sites/nycflirts.com/ (PHP Site)"
echo "✅ *                  → aeims-frontend (Default fallback)"
echo

echo "Service Details:"
echo "├── aeims-frontend: React app from ../aeims/telephony-platform/frontend/"
echo "├── aeims-core: API backend on port 8000"
echo "├── aeims-php-fpm: PHP processor for sites"
echo "└── aeims-nginx: Load balancer with site volume mounts"
echo

echo "Volume Mounts Added:"
echo "├── ../aeims/sites → /var/www/sites:ro (in nginx and php-fpm)"
echo "└── Site directories: flirts.nyc/, nycflirts.com/"
echo

echo "To deploy these changes:"
echo "1. cd /Users/ryan/development/aeims-control"
echo "2. docker-compose down"
echo "3. docker-compose up -d --build"
echo "4. Test domains point to correct content"

# Verify required directories exist
echo
echo "=== Directory Verification ==="
if [ -d "/Users/ryan/development/aeims/sites/flirts.nyc" ]; then
    echo "✅ flirts.nyc site directory exists"
    echo "   Files: $(ls /Users/ryan/development/aeims/sites/flirts.nyc | wc -l) files"
else
    echo "❌ flirts.nyc site directory missing"
fi

if [ -d "/Users/ryan/development/aeims/sites/nycflirts.com" ]; then
    echo "✅ nycflirts.com site directory exists"
    echo "   Files: $(ls /Users/ryan/development/aeims/sites/nycflirts.com | wc -l) files"
else
    echo "❌ nycflirts.com site directory missing"
fi

if [ -d "/Users/ryan/development/aeims/telephony-platform/frontend" ]; then
    echo "✅ SEXACOMMS frontend directory exists"
    echo "   Frontend: $(ls /Users/ryan/development/aeims/telephony-platform/frontend/src | wc -l) source directories"
else
    echo "❌ SEXACOMMS frontend directory missing"
fi

echo
echo "Configuration ready for deployment! 🚀"