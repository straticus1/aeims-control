<?php
/**
 * AEIMS PHP Debug Helper
 * Comprehensive debugging utility for PHP applications
 * Include this at the top of any PHP entry point to capture all errors
 */

// Enable all error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
ini_set('log_errors', 1);
ini_set('html_errors', 1);

// Set custom error log location
$logDir = getenv('LOG_DIR') ?: '/app/logs';
if (!is_dir($logDir)) {
    mkdir($logDir, 0755, true);
}
ini_set('error_log', $logDir . '/php_errors.log');

/**
 * Debug output buffer for collecting all output
 */
$GLOBALS['debug_output'] = [];
$GLOBALS['debug_start_time'] = microtime(true);

/**
 * Add debug message to output buffer
 */
function debug_log($message, $type = 'INFO') {
    $timestamp = date('Y-m-d H:i:s');
    $memory = round(memory_get_usage() / 1024 / 1024, 2) . 'MB';
    $entry = "[$timestamp] [$type] [Memory: $memory] $message";

    $GLOBALS['debug_output'][] = $entry;
    error_log($entry);
}

/**
 * Custom error handler
 */
function debug_error_handler($errno, $errstr, $errfile, $errline) {
    $error_types = [
        E_ERROR => 'ERROR',
        E_WARNING => 'WARNING',
        E_PARSE => 'PARSE',
        E_NOTICE => 'NOTICE',
        E_CORE_ERROR => 'CORE_ERROR',
        E_CORE_WARNING => 'CORE_WARNING',
        E_COMPILE_ERROR => 'COMPILE_ERROR',
        E_COMPILE_WARNING => 'COMPILE_WARNING',
        E_USER_ERROR => 'USER_ERROR',
        E_USER_WARNING => 'USER_WARNING',
        E_USER_NOTICE => 'USER_NOTICE',
        E_STRICT => 'STRICT',
        E_RECOVERABLE_ERROR => 'RECOVERABLE_ERROR',
        E_DEPRECATED => 'DEPRECATED',
        E_USER_DEPRECATED => 'USER_DEPRECATED'
    ];

    $type = $error_types[$errno] ?? 'UNKNOWN';
    $message = "PHP $type: $errstr in $errfile on line $errline";
    debug_log($message, 'PHP_ERROR');

    // Don't execute PHP internal error handler
    return true;
}

/**
 * Custom exception handler
 */
function debug_exception_handler($exception) {
    $message = "Uncaught Exception: " . $exception->getMessage() .
               " in " . $exception->getFile() .
               " on line " . $exception->getLine();
    debug_log($message, 'EXCEPTION');
    debug_log("Stack trace:\n" . $exception->getTraceAsString(), 'STACK_TRACE');

    // Output debug information
    output_debug_info();
    exit(1);
}

/**
 * Shutdown function to catch fatal errors
 */
function debug_shutdown_handler() {
    $error = error_get_last();
    if ($error !== null && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        $message = "Fatal Error: {$error['message']} in {$error['file']} on line {$error['line']}";
        debug_log($message, 'FATAL');
        output_debug_info();
    }
}

/**
 * Output comprehensive debug information
 */
function output_debug_info() {
    $execution_time = round((microtime(true) - $GLOBALS['debug_start_time']) * 1000, 2);
    $peak_memory = round(memory_get_peak_usage() / 1024 / 1024, 2);

    // Check if this is a web request or CLI
    $is_web = isset($_SERVER['HTTP_HOST']);

    if ($is_web) {
        // Web output - JSON for APIs, HTML for browsers
        $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
        if (strpos($accept, 'application/json') !== false ||
            strpos($_SERVER['REQUEST_URI'] ?? '', '/api/') !== false ||
            strpos($_SERVER['REQUEST_URI'] ?? '', '.json') !== false) {
            header('Content-Type: application/json');
            echo json_encode([
                'debug' => true,
                'status' => 'error',
                'execution_time_ms' => $execution_time,
                'peak_memory_mb' => $peak_memory,
                'php_version' => PHP_VERSION,
                'server' => $_SERVER['SERVER_NAME'] ?? 'unknown',
                'timestamp' => date('c'),
                'messages' => $GLOBALS['debug_output'],
                'environment' => $_ENV,
                'server_info' => $_SERVER
            ], JSON_PRETTY_PRINT);
        } else {
            // HTML output for browsers
            header('Content-Type: text/html');
            echo "<!DOCTYPE html>\n<html><head><title>AEIMS Debug Info</title>";
            echo "<style>body{font-family:monospace;margin:20px;background:#f0f0f0;} ";
            echo ".debug{background:white;padding:20px;border-radius:5px;margin:10px 0;} ";
            echo ".error{background:#ffe6e6;border-left:4px solid #ff0000;} ";
            echo ".info{background:#e6f3ff;border-left:4px solid #0066cc;} ";
            echo "pre{white-space:pre-wrap;}</style></head><body>";
            echo "<h1>🐛 AEIMS PHP Debug Information</h1>";
            echo "<div class='debug info'>";
            echo "<h2>📊 System Information</h2>";
            echo "<strong>Execution Time:</strong> {$execution_time}ms<br>";
            echo "<strong>Peak Memory:</strong> {$peak_memory}MB<br>";
            echo "<strong>PHP Version:</strong> " . PHP_VERSION . "<br>";
            echo "<strong>Server:</strong> " . ($_SERVER['SERVER_NAME'] ?? 'unknown') . "<br>";
            echo "<strong>Timestamp:</strong> " . date('c') . "<br>";
            echo "</div>";

            echo "<div class='debug error'>";
            echo "<h2>🚨 Debug Messages</h2>";
            echo "<pre>";
            foreach ($GLOBALS['debug_output'] as $message) {
                echo htmlspecialchars($message) . "\n";
            }
            echo "</pre></div>";

            echo "<div class='debug info'>";
            echo "<h2>🌍 Environment Variables</h2>";
            echo "<pre>" . htmlspecialchars(print_r($_ENV, true)) . "</pre>";
            echo "</div>";

            echo "<div class='debug info'>";
            echo "<h2>🌐 Server Variables</h2>";
            echo "<pre>" . htmlspecialchars(print_r($_SERVER, true)) . "</pre>";
            echo "</div>";
            echo "</body></html>";
        }
    } else {
        // CLI output
        echo "\n=== AEIMS PHP DEBUG INFORMATION ===\n";
        echo "Execution Time: {$execution_time}ms\n";
        echo "Peak Memory: {$peak_memory}MB\n";
        echo "PHP Version: " . PHP_VERSION . "\n";
        echo "Timestamp: " . date('c') . "\n";
        echo "\n=== DEBUG MESSAGES ===\n";
        foreach ($GLOBALS['debug_output'] as $message) {
            echo $message . "\n";
        }
        echo "\n=== ENVIRONMENT ===\n";
        print_r($_ENV);
    }
}

/**
 * Check common requirements and dependencies
 */
function check_system_requirements() {
    debug_log("=== SYSTEM REQUIREMENTS CHECK ===");

    // PHP version
    debug_log("PHP Version: " . PHP_VERSION);

    // Required extensions
    $required_extensions = ['json', 'pdo', 'curl', 'mbstring', 'openssl'];
    foreach ($required_extensions as $ext) {
        if (extension_loaded($ext)) {
            debug_log("✅ Extension $ext: LOADED");
        } else {
            debug_log("❌ Extension $ext: MISSING", 'ERROR');
        }
    }

    // Memory limit
    $memory_limit = ini_get('memory_limit');
    debug_log("Memory Limit: $memory_limit");

    // Database connectivity (if PDO available)
    if (extension_loaded('pdo')) {
        try {
            // Check for database environment variables
            $db_host = getenv('DB_HOST') ?: getenv('DATABASE_HOST');
            $db_name = getenv('DB_NAME') ?: getenv('DATABASE_NAME');
            $db_user = getenv('DB_USER') ?: getenv('DATABASE_USER');

            if ($db_host && $db_name && $db_user) {
                debug_log("Database config found - Host: $db_host, DB: $db_name, User: $db_user");
            } else {
                debug_log("Database environment variables not fully configured", 'WARNING');
            }
        } catch (Exception $e) {
            debug_log("Database check failed: " . $e->getMessage(), 'WARNING');
        }
    }

    // File permissions
    $write_dirs = ['/tmp', '/app/logs', getcwd()];
    foreach ($write_dirs as $dir) {
        if (is_dir($dir) && is_writable($dir)) {
            debug_log("✅ Write access to $dir: OK");
        } else {
            debug_log("❌ Write access to $dir: FAILED", 'WARNING');
        }
    }
}

/**
 * Health check endpoint handler
 */
function handle_health_check() {
    if (isset($_SERVER['REQUEST_URI']) && $_SERVER['REQUEST_URI'] === '/health') {
        header('Content-Type: application/json');
        http_response_code(200);

        $health_data = [
            'status' => 'healthy',
            'service' => 'aeims-php',
            'timestamp' => date('c'),
            'php_version' => PHP_VERSION,
            'memory_usage' => round(memory_get_usage() / 1024 / 1024, 2) . 'MB',
            'uptime' => round(microtime(true) - $GLOBALS['debug_start_time'], 3) . 's'
        ];

        echo json_encode($health_data, JSON_PRETTY_PRINT);
        exit;
    }
}

/**
 * Enhanced var_dump replacement
 */
function debug_dump($var, $label = 'DEBUG DUMP') {
    $output = "\n=== $label ===\n";
    $output .= print_r($var, true);
    $output .= "\n=== END $label ===\n";
    debug_log($output, 'DUMP');
}

// Set up error handlers
set_error_handler('debug_error_handler');
set_exception_handler('debug_exception_handler');
register_shutdown_function('debug_shutdown_handler');

// Initialize debug session
debug_log("=== AEIMS PHP DEBUG SESSION STARTED ===");
debug_log("Request URI: " . ($_SERVER['REQUEST_URI'] ?? 'CLI'));
debug_log("Request Method: " . ($_SERVER['REQUEST_METHOD'] ?? 'CLI'));
debug_log("User Agent: " . ($_SERVER['HTTP_USER_AGENT'] ?? 'CLI'));

// Handle health check requests immediately
handle_health_check();

// Check system requirements
check_system_requirements();

debug_log("=== DEBUG HELPER INITIALIZATION COMPLETE ===");

// Add a helper function to output debug info on demand
function show_debug_info() {
    output_debug_info();
}

// Add emergency debug trigger (useful for testing)
if (isset($_GET['debug']) || isset($_POST['debug']) || in_array('--debug', $argv ?? [])) {
    debug_log("Emergency debug mode activated");
    show_debug_info();
    exit;
}

?>