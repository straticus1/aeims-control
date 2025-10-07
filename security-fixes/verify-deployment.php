<?php
/**
 * Deployment Verification Script
 */

echo "AEIMS Security Fixes Verification\n";
echo "================================\n\n";

$checks = [
    'Security Headers Class' => '/Users/ryan/development/aeims/src/Security/SecurityHeaders.php',
    'Input Validator Class' => '/Users/ryan/development/aeims/src/Security/InputValidator.php',
    'Security Init Script' => '/Users/ryan/development/aeims/src/Security/security-init.php',
    'Secure Database Helper' => '/Users/ryan/development/aeims/src/Security/SecureDatabase.php',
    'Secure SSO Manager' => '/Users/ryan/development/aeims/services/SecureSSOManager.php',
];

$all_good = true;

foreach ($checks as $name => $file) {
    if (file_exists($file)) {
        echo "✓ $name: DEPLOYED\n";
    } else {
        echo "✗ $name: MISSING\n";
        $all_good = false;
    }
}

echo "\n";

if ($all_good) {
    echo "✓ All security components deployed successfully!\n";
} else {
    echo "✗ Some security components are missing. Check deployment.\n";
    exit(1);
}

echo "\nNext Steps:\n";
echo "1. Run database migration: sso_token_migration.sql\n";
echo "2. Test authentication flows\n";
echo "3. Test all form submissions\n";
echo "4. Verify security headers in browser\n";
echo "5. Update any hardcoded references to old classes\n";
echo "6. Monitor error logs for issues\n";

?>
