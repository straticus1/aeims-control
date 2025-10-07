<?php
/**
 * AEIMS Security Patch: Command Injection Prevention
 * Fixes critical command injection vulnerabilities in exec() calls
 */

$patch_files = [
    '/Users/ryan/development/aeims/services/NginxManager.php',
    // Add other files with exec() vulnerabilities as discovered
];

function createSecureNginxManager() {
    $secure_manager = '<?php
/**
 * Secure Nginx Manager with Command Injection Prevention
 */

namespace AEIMS\Services;

class SecureNginxManager {
    private $nginxBinary;
    private $allowedCommands = [\'test\', \'reload\', \'status\'];

    public function __construct() {
        // Only allow specific nginx binary paths
        $this->nginxBinary = \'/usr/sbin/nginx\'; // Fixed path, no user input
    }

    /**
     * Test nginx configuration safely
     */
    public function testConfiguration(): bool {
        // No user input allowed - fixed command only
        $command = escapeshellcmd($this->nginxBinary) . \' -t 2>&1\';
        $output = [];
        $returnCode = 0;

        exec($command, $output, $returnCode);
        return $returnCode === 0;
    }

    /**
     * Reload nginx configuration safely
     */
    public function reload(): bool {
        // No user input allowed - fixed command only
        $command = escapeshellcmd($this->nginxBinary) . \' -s reload 2>&1\';
        $output = [];
        $returnCode = 0;

        exec($command, $output, $returnCode);
        return $returnCode === 0;
    }

    /**
     * Get nginx status safely
     */
    public function getStatus(): array {
        // Use specific commands only - no user input
        $commands = [
            \'pgrep nginx\',
            \'nginx -v 2>&1\'
        ];

        $status = [
            \'running\' => false,
            \'version\' => \'unknown\',
            \'config_valid\' => false
        ];

        // Check if running
        exec(\'pgrep nginx\', $output, $returnCode);
        $status[\'running\'] = $returnCode === 0 && !empty($output);

        // Get version safely
        exec(\'nginx -v 2>&1\', $versionOutput, $versionCode);
        if ($versionCode === 0 && !empty($versionOutput)) {
            $status[\'version\'] = $versionOutput[0] ?? \'unknown\';
        }

        // Test configuration
        $status[\'config_valid\'] = $this->testConfiguration();

        return $status;
    }

    /**
     * Validate file paths to prevent directory traversal
     */
    private function validatePath(string $path): bool {
        $realPath = realpath($path);
        $basePath = realpath(\'/etc/nginx/\');

        return $realPath !== false &&
               $basePath !== false &&
               strpos($realPath, $basePath) === 0;
    }
}
?>';

    return $secure_manager;
}

foreach ($patch_files as $file) {
    if (!file_exists($file)) {
        echo "Warning: File not found: $file\n";
        continue;
    }

    // Create backup
    copy($file, $file . '.backup.' . date('Y-m-d-H-i-s'));

    // For NginxManager.php, replace with secure version
    if (strpos($file, 'NginxManager.php') !== false) {
        file_put_contents($file, createSecureNginxManager());
        echo "Replaced with secure version: $file\n";
        continue;
    }

    $content = file_get_contents($file);
    $original_content = $content;

    // Fix 1: Add input validation for exec() calls
    $patterns = [
        // Pattern for exec with variable commands
        '/exec\(\s*\$([^,\)]+)/' => 'exec(escapeshellcmd($\\1)',

        // Pattern for exec with string interpolation
        '/exec\(\s*"([^"]*\$[^"]*)"/' => 'exec(escapeshellcmd("\\1")',

        // Pattern for system() calls
        '/system\(\s*\$([^,\)]+)/' => 'system(escapeshellcmd($\\1)',

        // Pattern for shell_exec() calls
        '/shell_exec\(\s*\$([^,\)]+)/' => 'shell_exec(escapeshellcmd($\\1)',
    ];

    foreach ($patterns as $pattern => $replacement) {
        $content = preg_replace($pattern, $replacement, $content);
    }

    // Add input validation function if not present
    if (strpos($content, 'function validateCommand') === false) {
        $validation_function = '
    /**
     * Validate command input to prevent injection
     */
    private function validateCommand(string $command): bool {
        // Allow only alphanumeric characters, spaces, hyphens, and specific safe characters
        if (!preg_match('/^[a-zA-Z0-9 \\-\\.\\/]+$/', $command)) {
            return false;
        }

        // Blacklist dangerous commands
        $dangerous = ['rm', 'wget', 'curl', 'nc', 'netcat', 'telnet', 'ssh', 'scp'];
        foreach ($dangerous as $danger) {
            if (strpos($command, $danger) !== false) {
                return false;
            }
        }

        return true;
    }
';

        // Insert before the last closing brace
        $content = substr_replace($content, $validation_function . "\n}", -1);
    }

    if ($content !== $original_content) {
        file_put_contents($file, $content);
        echo "Fixed command injection vulnerabilities: $file\n";
    } else {
        echo "No changes needed: $file\n";
    }
}

echo "Command injection security patch completed.\n";
?>