<?php
/**
 * AEIMS Security Patch: Authentication Cookie Security Fix
 * Fixes critical CSRF vulnerability in cookie configuration
 */

$patch_files = [
    '/Users/ryan/development/aeims/sites/nycflirts.com/auth.php',
    // Add other auth files as discovered
];

foreach ($patch_files as $file) {
    if (!file_exists($file)) {
        echo "Warning: File not found: $file\n";
        continue;
    }

    $content = file_get_contents($file);
    $original_content = $content;

    // Fix 1: Change SameSite from Lax to Strict for security
    $content = str_replace(
        "'samesite' => 'Lax'",
        "'samesite' => 'Strict'",
        $content
    );

    // Fix 2: Restrict domain scope - remove overly broad domain
    $content = str_replace(
        "'domain' => '.afterdarksystems.net',",
        "'domain' => null, // Site-specific cookies only",
        $content
    );

    // Fix 3: Add CSRF token validation
    $csrf_check = "
        // CSRF Protection
        if (!\$_SESSION['csrf_token']) {
            \$_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        }

        if (\$_SERVER['REQUEST_METHOD'] === 'POST') {
            \$submitted_token = \$_POST['csrf_token'] ?? '';
            if (!hash_equals(\$_SESSION['csrf_token'], \$submitted_token)) {
                http_response_code(403);
                die('CSRF token mismatch');
            }
        }
    ";

    // Insert CSRF check after session_start()
    $content = str_replace(
        "session_start();",
        "session_start();\n" . $csrf_check,
        $content
    );

    if ($content !== $original_content) {
        // Create backup
        copy($file, $file . '.backup.' . date('Y-m-d-H-i-s'));

        // Apply fix
        file_put_contents($file, $content);
        echo "Fixed: $file\n";
    } else {
        echo "No changes needed: $file\n";
    }
}

echo "Authentication security patch completed.\n";
?>