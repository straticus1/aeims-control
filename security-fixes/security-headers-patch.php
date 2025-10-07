<?php
/**
 * AEIMS Security Patch: Security Headers and Input Validation
 * Adds essential security headers and input validation middleware
 */

// Create security headers middleware
$security_middleware = '<?php
/**
 * Security Headers Middleware
 * Adds essential security headers to all responses
 */

namespace AEIMS\Security;

class SecurityHeaders {
    private static $headers = [
        // Prevent XSS attacks
        "X-XSS-Protection" => "1; mode=block",

        // Prevent clickjacking
        "X-Frame-Options" => "SAMEORIGIN",

        // Prevent MIME sniffing
        "X-Content-Type-Options" => "nosniff",

        // Prevent information disclosure
        "X-Powered-By" => "", // Remove server info

        // Force HTTPS (adjust max-age as needed)
        "Strict-Transport-Security" => "max-age=31536000; includeSubDomains; preload",

        // Referrer policy for privacy
        "Referrer-Policy" => "strict-origin-when-cross-origin",

        // Permissions policy
        "Permissions-Policy" => "geolocation=(), microphone=(), camera=()",

        // Content Security Policy (restrictive - adjust as needed)
        "Content-Security-Policy" => "default-src \'self\'; script-src \'self\' \'unsafe-inline\' https://cdnjs.cloudflare.com; style-src \'self\' \'unsafe-inline\' https://fonts.googleapis.com; font-src \'self\' https://fonts.gstatic.com; img-src \'self\' data: https:; connect-src \'self\'; frame-ancestors \'none\'; base-uri \'self\'; form-action \'self\';"
    ];

    /**
     * Apply security headers
     */
    public static function apply(): void {
        foreach (self::$headers as $header => $value) {
            if ($value === "") {
                header_remove($header);
            } else {
                header("$header: $value");
            }
        }
    }

    /**
     * Apply CSRF token to forms
     */
    public static function getCSRFToken(): string {
        if (session_status() === PHP_SESSION_NONE) {
            session_start();
        }

        if (!isset($_SESSION[\'csrf_token\'])) {
            $_SESSION[\'csrf_token\'] = bin2hex(random_bytes(32));
        }

        return $_SESSION[\'csrf_token\'];
    }

    /**
     * Validate CSRF token
     */
    public static function validateCSRFToken(string $token): bool {
        if (session_status() === PHP_SESSION_NONE) {
            session_start();
        }

        return isset($_SESSION[\'csrf_token\']) && hash_equals($_SESSION[\'csrf_token\'], $token);
    }

    /**
     * Generate secure form token field
     */
    public static function getCSRFField(): string {
        return \'<input type="hidden" name="csrf_token" value="\' . htmlspecialchars(self::getCSRFToken()) . \'">\';
    }
}
?>';

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/SecurityHeaders.php', $security_middleware);

// Create input validation class
$input_validator = '<?php
/**
 * Input Validation and Sanitization
 * Prevents various injection attacks
 */

namespace AEIMS\Security;

class InputValidator {
    /**
     * Sanitize string input
     */
    public static function sanitizeString(string $input, int $maxLength = 255): string {
        // Remove null bytes and control characters
        $input = preg_replace(\'/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/\', \'\', $input);

        // Trim whitespace
        $input = trim($input);

        // Limit length
        $input = substr($input, 0, $maxLength);

        return $input;
    }

    /**
     * Validate email address
     */
    public static function validateEmail(string $email): bool {
        return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
    }

    /**
     * Validate integer
     */
    public static function validateInteger(string $input, int $min = null, int $max = null): ?int {
        $value = filter_var($input, FILTER_VALIDATE_INT);

        if ($value === false) {
            return null;
        }

        if ($min !== null && $value < $min) {
            return null;
        }

        if ($max !== null && $value > $max) {
            return null;
        }

        return $value;
    }

    /**
     * Validate URL
     */
    public static function validateURL(string $url): bool {
        return filter_var($url, FILTER_VALIDATE_URL) !== false;
    }

    /**
     * Sanitize filename
     */
    public static function sanitizeFilename(string $filename): string {
        // Remove path traversal attempts
        $filename = basename($filename);

        // Remove dangerous characters
        $filename = preg_replace(\'/[^a-zA-Z0-9._-]/\', \'\', $filename);

        // Prevent hidden files
        $filename = ltrim($filename, \'.\');

        return $filename;
    }

    /**
     * Validate and sanitize username
     */
    public static function validateUsername(string $username): ?string {
        $username = self::sanitizeString($username, 50);

        // Allow only alphanumeric, underscore, hyphen
        if (!preg_match(\'/^[a-zA-Z0-9_-]+$/\', $username)) {
            return null;
        }

        // Must be between 3-50 characters
        if (strlen($username) < 3 || strlen($username) > 50) {
            return null;
        }

        return $username;
    }

    /**
     * Validate password strength
     */
    public static function validatePassword(string $password): array {
        $errors = [];

        if (strlen($password) < 8) {
            $errors[] = \'Password must be at least 8 characters\';
        }

        if (!preg_match(\'/[A-Z]/\', $password)) {
            $errors[] = \'Password must contain at least one uppercase letter\';
        }

        if (!preg_match(\'/[a-z]/\', $password)) {
            $errors[] = \'Password must contain at least one lowercase letter\';
        }

        if (!preg_match(\'/[0-9]/\', $password)) {
            $errors[] = \'Password must contain at least one number\';
        }

        if (!preg_match(\'/[^a-zA-Z0-9]/\', $password)) {
            $errors[] = \'Password must contain at least one special character\';
        }

        return $errors;
    }

    /**
     * Sanitize HTML content
     */
    public static function sanitizeHTML(string $html): string {
        // Use HTMLPurifier or similar for more comprehensive cleaning
        // For basic sanitization:
        return htmlspecialchars($html, ENT_QUOTES | ENT_HTML5, \'UTF-8\');
    }

    /**
     * Validate IP address
     */
    public static function validateIP(string $ip): bool {
        return filter_var($ip, FILTER_VALIDATE_IP) !== false;
    }

    /**
     * Rate limiting check
     */
    public static function checkRateLimit(string $identifier, int $maxAttempts = 5, int $timeWindow = 300): bool {
        session_start();

        $key = "rate_limit_" . hash(\'sha256\', $identifier);
        $now = time();

        if (!isset($_SESSION[$key])) {
            $_SESSION[$key] = [\'count\' => 1, \'first_attempt\' => $now];
            return true;
        }

        $data = $_SESSION[$key];

        // Reset if time window expired
        if ($now - $data[\'first_attempt\'] > $timeWindow) {
            $_SESSION[$key] = [\'count\' => 1, \'first_attempt\' => $now];
            return true;
        }

        // Check if limit exceeded
        if ($data[\'count\'] >= $maxAttempts) {
            return false;
        }

        // Increment counter
        $_SESSION[$key][\'count\']++;
        return true;
    }
}
?>';

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/InputValidator.php', $input_validator);

// Create security initialization script
$security_init = '<?php
/**
 * Security Initialization
 * Include this at the top of all public-facing scripts
 */

// Apply security headers immediately
require_once __DIR__ . \'/SecurityHeaders.php\';
require_once __DIR__ . \'/InputValidator.php\';

use AEIMS\Security\SecurityHeaders;
use AEIMS\Security\InputValidator;

// Apply security headers
SecurityHeaders::apply();

// Start secure session
if (session_status() === PHP_SESSION_NONE) {
    ini_set(\'session.cookie_httponly\', 1);
    ini_set(\'session.cookie_secure\', 1);
    ini_set(\'session.cookie_samesite\', \'Strict\');
    ini_set(\'session.use_strict_mode\', 1);
    ini_set(\'session.use_only_cookies\', 1);

    session_start();
}

// Regenerate session ID periodically
if (!isset($_SESSION[\'last_regeneration\'])) {
    $_SESSION[\'last_regeneration\'] = time();
} elseif (time() - $_SESSION[\'last_regeneration\'] > 300) { // 5 minutes
    session_regenerate_id(true);
    $_SESSION[\'last_regeneration\'] = time();
}

// Basic request validation
if ($_SERVER[\'REQUEST_METHOD\'] === \'POST\') {
    // CSRF protection for POST requests
    if (!isset($_POST[\'csrf_token\']) || !SecurityHeaders::validateCSRFToken($_POST[\'csrf_token\'])) {
        http_response_code(403);
        die(\'CSRF token validation failed\');
    }
}

// Rate limiting for sensitive endpoints
$sensitive_endpoints = [\'/login.php\', \'/auth.php\', \'/admin.php\'];
$current_script = $_SERVER[\'SCRIPT_NAME\'] ?? \'\';

foreach ($sensitive_endpoints as $endpoint) {
    if (strpos($current_script, $endpoint) !== false) {
        $client_ip = $_SERVER[\'REMOTE_ADDR\'] ?? \'unknown\';
        if (!InputValidator::checkRateLimit($client_ip, 10, 600)) { // 10 attempts per 10 minutes
            http_response_code(429);
            die(\'Rate limit exceeded. Please try again later.\');
        }
        break;
    }
}

?>';

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/security-init.php', $security_init);

// Create automated patch application script
$patch_script = '#!/bin/bash
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
                echo "require_once __DIR__ . \'/../../aeims-control/security-fixes/security-init.php\';"
                tail -n +2 "$file"
            ) > "$file.tmp"
            mv "$file.tmp" "$file"
            echo "  - Added security initialization"
        fi

        # Add CSRF tokens to forms
        if grep -q "<form" "$file"; then
            sed -i.bak \'s/<form/<form\n<?php echo AEIMS\\Security\\SecurityHeaders::getCSRFField(); ?>/g\' "$file"
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

';

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/apply-security-headers.sh', $patch_script);
chmod('/Users/ryan/development/aeims-control/security-fixes/apply-security-headers.sh', 0755);

echo "Security headers and validation patches created:\n";
echo "1. SecurityHeaders.php - Security headers middleware\n";
echo "2. InputValidator.php - Input validation and sanitization\n";
echo "3. security-init.php - Security initialization script\n";
echo "4. apply-security-headers.sh - Automated patch application\n";
echo "\nTo apply:\n";
echo "1. Run ./apply-security-headers.sh\n";
echo "2. Test all functionality thoroughly\n";
echo "3. Update CSP policy as needed for your specific requirements\n";

?>