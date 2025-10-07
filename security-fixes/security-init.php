<?php
/**
 * Security Initialization
 * Include this at the top of all public-facing scripts
 */

// Apply security headers immediately
require_once __DIR__ . '/SecurityHeaders.php';
require_once __DIR__ . '/InputValidator.php';

use AEIMS\Security\SecurityHeaders;
use AEIMS\Security\InputValidator;

// Apply security headers
SecurityHeaders::apply();

// Start secure session
if (session_status() === PHP_SESSION_NONE) {
    ini_set('session.cookie_httponly', 1);
    ini_set('session.cookie_secure', 1);
    ini_set('session.cookie_samesite', 'Strict');
    ini_set('session.use_strict_mode', 1);
    ini_set('session.use_only_cookies', 1);

    session_start();
}

// Regenerate session ID periodically
if (!isset($_SESSION['last_regeneration'])) {
    $_SESSION['last_regeneration'] = time();
} elseif (time() - $_SESSION['last_regeneration'] > 300) { // 5 minutes
    session_regenerate_id(true);
    $_SESSION['last_regeneration'] = time();
}

// Basic request validation
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // CSRF protection for POST requests
    if (!isset($_POST['csrf_token']) || !SecurityHeaders::validateCSRFToken($_POST['csrf_token'])) {
        http_response_code(403);
        die('CSRF token validation failed');
    }
}

// Rate limiting for sensitive endpoints
$sensitive_endpoints = ['/login.php', '/auth.php', '/admin.php'];
$current_script = $_SERVER['SCRIPT_NAME'] ?? '';

foreach ($sensitive_endpoints as $endpoint) {
    if (strpos($current_script, $endpoint) !== false) {
        $client_ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
        if (!InputValidator::checkRateLimit($client_ip, 10, 600)) { // 10 attempts per 10 minutes
            http_response_code(429);
            die('Rate limit exceeded. Please try again later.');
        }
        break;
    }
}

?>