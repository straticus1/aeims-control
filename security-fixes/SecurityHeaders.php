<?php
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
        "Content-Security-Policy" => "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self';"
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

        if (!isset($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        }

        return $_SESSION['csrf_token'];
    }

    /**
     * Validate CSRF token
     */
    public static function validateCSRFToken(string $token): bool {
        if (session_status() === PHP_SESSION_NONE) {
            session_start();
        }

        return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token);
    }

    /**
     * Generate secure form token field
     */
    public static function getCSRFField(): string {
        return '<input type="hidden" name="csrf_token" value="' . htmlspecialchars(self::getCSRFToken()) . '">';
    }
}
?>