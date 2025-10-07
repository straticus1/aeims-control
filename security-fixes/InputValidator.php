<?php
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
        $input = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', '', $input);

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
        $filename = preg_replace('/[^a-zA-Z0-9._-]/', '', $filename);

        // Prevent hidden files
        $filename = ltrim($filename, '.');

        return $filename;
    }

    /**
     * Validate and sanitize username
     */
    public static function validateUsername(string $username): ?string {
        $username = self::sanitizeString($username, 50);

        // Allow only alphanumeric, underscore, hyphen
        if (!preg_match('/^[a-zA-Z0-9_-]+$/', $username)) {
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
            $errors[] = 'Password must be at least 8 characters';
        }

        if (!preg_match('/[A-Z]/', $password)) {
            $errors[] = 'Password must contain at least one uppercase letter';
        }

        if (!preg_match('/[a-z]/', $password)) {
            $errors[] = 'Password must contain at least one lowercase letter';
        }

        if (!preg_match('/[0-9]/', $password)) {
            $errors[] = 'Password must contain at least one number';
        }

        if (!preg_match('/[^a-zA-Z0-9]/', $password)) {
            $errors[] = 'Password must contain at least one special character';
        }

        return $errors;
    }

    /**
     * Sanitize HTML content
     */
    public static function sanitizeHTML(string $html): string {
        // Use HTMLPurifier or similar for more comprehensive cleaning
        // For basic sanitization:
        return htmlspecialchars($html, ENT_QUOTES | ENT_HTML5, 'UTF-8');
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

        $key = "rate_limit_" . hash('sha256', $identifier);
        $now = time();

        if (!isset($_SESSION[$key])) {
            $_SESSION[$key] = ['count' => 1, 'first_attempt' => $now];
            return true;
        }

        $data = $_SESSION[$key];

        // Reset if time window expired
        if ($now - $data['first_attempt'] > $timeWindow) {
            $_SESSION[$key] = ['count' => 1, 'first_attempt' => $now];
            return true;
        }

        // Check if limit exceeded
        if ($data['count'] >= $maxAttempts) {
            return false;
        }

        // Increment counter
        $_SESSION[$key]['count']++;
        return true;
    }
}
?>