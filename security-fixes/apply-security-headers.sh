#!/bin/bash
# Apply Security Headers and Validation Patches

echo "Applying security headers and validation patches..."

# Backup existing files
mkdir -p /Users/ryan/development/aeims-control/security-fixes/backups/headers

# Find all PHP files that need security headers
find /Users/ryan/development/aeims -name "*.php" -type f | grep -E "(index|login|auth|admin|dashboard)" | while read file; do
    if [ -f "$file" ]; then
        echo "Patching: $file"

        # Create backup
        cp "$file" "/Users/ryan/development/aeims-control/security-fixes/backups/headers/$(basename $file).backup.$(date +%Y%m%d_%H%M%S)"

        # Add security initialization at the top (after opening PHP tag)
        if ! grep -q "security-init.php" "$file"; then
            # Create temporary file with security init added
            (
                echo "<?php"
                echo "require_once __DIR__ . '/../../aeims-control/security-fixes/security-init.php';"
                tail -n +2 "$file"
            ) > "$file.tmp"
            mv "$file.tmp" "$file"
            echo "  - Added security initialization"
        fi

        # Add CSRF tokens to forms
        if grep -q "<form" "$file"; then
            sed -i.bak 's/<form/<form\n<?php echo AEIMS\Security\SecurityHeaders::getCSRFField(); ?>/g' "$file"
            echo "  - Added CSRF tokens to forms"
        fi
    fi
done

# Update nginx configuration for security headers
if [ -f "/etc/nginx/nginx.conf" ]; then
    echo "Adding security headers to nginx configuration..."

    # Add security headers block if not present
    if ! grep -q "# Security Headers" /etc/nginx/nginx.conf; then
        cat >> /etc/nginx/conf.d/security-headers.conf << EOF
# Security Headers
add_header X-Frame-Options SAMEORIGIN always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# Hide server information
server_tokens off;
more_clear_headers "Server";
EOF
        echo "  - Added nginx security headers configuration"
    fi
fi

echo "Security headers patch completed!"
echo ""
echo "IMPORTANT: Test all functionality after applying these patches!"
echo "1. Test form submissions (CSRF tokens)"
echo "2. Test authentication flows"
echo "3. Verify security headers are present"
echo "4. Check for any broken functionality"

