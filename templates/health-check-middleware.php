<?php
/**
 * Standardized Health Check Middleware for AEIMS Services (PHP)
 * Implements the AEIMS Health Check Specification
 */

class HealthCheckManager {
    private $serviceName;
    private $version;
    private $startTime;
    private $checks;

    public function __construct($config = []) {
        $this->serviceName = $config['serviceName'] ?? 'unknown-service';
        $this->version = $config['version'] ?? '1.0.0';
        $this->startTime = time();
        $this->checks = [];
    }

    /**
     * Register a health check
     */
    public function registerCheck($name, $checkFunction, $options = []) {
        $this->checks[$name] = [
            'fn' => $checkFunction,
            'timeout' => $options['timeout'] ?? 5,
            'critical' => $options['critical'] ?? true
        ];
    }

    /**
     * Handle health check requests
     */
    public function handleRequest($path) {
        header('Content-Type: application/json');

        try {
            switch ($path) {
                case '/health':
                    return $this->basicHealthCheck();
                case '/health/ready':
                    return $this->readinessCheck();
                case '/health/live':
                    return $this->livenessCheck();
                case '/health/deep':
                    return $this->deepHealthCheck();
                default:
                    http_response_code(404);
                    return json_encode(['error' => 'Not found']);
            }
        } catch (Exception $e) {
            http_response_code(503);
            return json_encode([
                'status' => 'unhealthy',
                'timestamp' => date('c'),
                'service' => $this->serviceName,
                'error' => $e->getMessage()
            ]);
        }
    }

    /**
     * Basic health check
     */
    private function basicHealthCheck() {
        $checks = $this->runCriticalChecks();
        $status = $this->determineStatus($checks);

        http_response_code($status === 'healthy' ? 200 : 503);

        return json_encode([
            'status' => $status,
            'timestamp' => date('c'),
            'service' => $this->serviceName,
            'version' => $this->version,
            'uptime' => time() - $this->startTime,
            'checks' => $this->simplifyChecks($checks)
        ]);
    }

    /**
     * Readiness check
     */
    private function readinessCheck() {
        $checks = $this->runCriticalChecks();
        $ready = $this->allChecksHealthy($checks);

        http_response_code($ready ? 200 : 503);

        return json_encode([
            'ready' => $ready,
            'timestamp' => date('c'),
            'service' => $this->serviceName,
            'checks' => $this->simplifyChecks($checks)
        ]);
    }

    /**
     * Liveness check
     */
    private function livenessCheck() {
        http_response_code(200);

        return json_encode([
            'alive' => true,
            'timestamp' => date('c'),
            'service' => $this->serviceName,
            'uptime' => time() - $this->startTime
        ]);
    }

    /**
     * Deep health check
     */
    private function deepHealthCheck() {
        $checks = $this->runAllChecks();
        $status = $this->determineStatus($checks);

        http_response_code($status === 'healthy' ? 200 : 503);

        return json_encode([
            'status' => $status,
            'timestamp' => date('c'),
            'service' => $this->serviceName,
            'version' => $this->version,
            'uptime' => time() - $this->startTime,
            'checks' => $checks
        ]);
    }

    /**
     * Run critical checks only
     */
    private function runCriticalChecks() {
        $criticalChecks = array_filter($this->checks, function($check) {
            return $check['critical'];
        });

        return $this->executeChecks($criticalChecks);
    }

    /**
     * Run all checks
     */
    private function runAllChecks() {
        return $this->executeChecks($this->checks);
    }

    /**
     * Execute checks with timeout
     */
    private function executeChecks($checks) {
        $results = [];

        foreach ($checks as $name => $config) {
            try {
                $start = microtime(true);

                // Set timeout
                $oldTimeout = ini_get('max_execution_time');
                set_time_limit($config['timeout']);

                $result = call_user_func($config['fn']);

                // Restore timeout
                set_time_limit($oldTimeout);

                $results[$name] = array_merge([
                    'status' => 'healthy',
                    'response_time_ms' => round((microtime(true) - $start) * 1000, 2)
                ], $result ?: []);

            } catch (Exception $e) {
                $results[$name] = [
                    'status' => 'unhealthy',
                    'error' => $e->getMessage(),
                    'response_time_ms' => round((microtime(true) - $start) * 1000, 2)
                ];
            }
        }

        return $results;
    }

    /**
     * Determine overall status
     */
    private function determineStatus($checks) {
        $statuses = array_column($checks, 'status');

        if (count(array_unique($statuses)) === 1 && $statuses[0] === 'healthy') {
            return 'healthy';
        } elseif (in_array('healthy', $statuses)) {
            return 'degraded';
        } else {
            return 'unhealthy';
        }
    }

    /**
     * Check if all checks are healthy
     */
    private function allChecksHealthy($checks) {
        foreach ($checks as $check) {
            if ($check['status'] !== 'healthy') {
                return false;
            }
        }
        return true;
    }

    /**
     * Simplify checks for basic response
     */
    private function simplifyChecks($checks) {
        $simplified = [];
        foreach ($checks as $name => $check) {
            $simplified[$name] = $check['status'];
        }
        return $simplified;
    }
}

/**
 * Common health check functions
 */
class CommonChecks {
    /**
     * Database health check (PDO)
     */
    public static function database($pdo) {
        return function() use ($pdo) {
            $start = microtime(true);
            $stmt = $pdo->query('SELECT 1');
            $responseTime = round((microtime(true) - $start) * 1000, 2);

            return [
                'response_time_ms' => $responseTime,
                'connection_status' => $pdo->getAttribute(PDO::ATTR_CONNECTION_STATUS)
            ];
        };
    }

    /**
     * Redis health check
     */
    public static function redis($redis) {
        return function() use ($redis) {
            $start = microtime(true);
            $redis->ping();
            $responseTime = round((microtime(true) - $start) * 1000, 2);

            $info = $redis->info('memory');
            $memoryUsage = $info['used_memory_human'] ?? 'unknown';

            return [
                'ping_response_ms' => $responseTime,
                'memory_usage' => $memoryUsage,
                'connected_clients' => $redis->info('clients')['connected_clients'] ?? 0
            ];
        };
    }

    /**
     * HTTP API health check
     */
    public static function httpApi($name, $url) {
        return function() use ($name, $url) {
            $start = microtime(true);

            $context = stream_context_create([
                'http' => [
                    'timeout' => 3,
                    'ignore_errors' => true
                ]
            ]);

            $response = file_get_contents($url, false, $context);
            $responseTime = round((microtime(true) - $start) * 1000, 2);

            $httpCode = 0;
            if (isset($http_response_header)) {
                preg_match('/HTTP\/\d\.\d\s+(\d+)/', $http_response_header[0], $matches);
                $httpCode = (int)$matches[1];
            }

            return [
                'status' => $httpCode < 400 ? 'healthy' : 'degraded',
                'response_time_ms' => $responseTime,
                'last_check' => date('c'),
                'http_status' => $httpCode
            ];
        };
    }

    /**
     * File system health check
     */
    public static function filesystem($path) {
        return function() use ($path) {
            $start = microtime(true);

            if (!is_readable($path)) {
                throw new Exception("Path not readable: $path");
            }

            $responseTime = round((microtime(true) - $start) * 1000, 2);

            return [
                'response_time_ms' => $responseTime,
                'readable' => true,
                'writable' => is_writable($path)
            ];
        };
    }
}

// Example usage for AEIMS App
if (basename($_SERVER['PHP_SELF']) === basename(__FILE__)) {
    $healthCheck = new HealthCheckManager([
        'serviceName' => 'aeims-app',
        'version' => '1.0.0'
    ]);

    // Register checks (example)
    if (class_exists('PDO')) {
        try {
            $pdo = new PDO(
                "mysql:host=" . ($_ENV['DB_HOST'] ?? 'localhost') . ";dbname=" . ($_ENV['DB_NAME'] ?? 'aeims_app'),
                $_ENV['DB_USER'] ?? 'aeims_user',
                $_ENV['DB_PASS'] ?? 'secure_password_123'
            );
            $healthCheck->registerCheck('database', CommonChecks::database($pdo));
        } catch (Exception $e) {
            // Database not available
        }
    }

    // Handle request
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    echo $healthCheck->handleRequest($path);
}
?>