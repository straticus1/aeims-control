<?php

namespace AEIMS\Services;

use Exception;

/**
 * Nginx Configuration Manager
 * Handles automatic generation, deployment, and management of nginx configurations
 */
class NginxManager
{
    private string $sitesAvailablePath;
    private string $sitesEnabledPath;
    private string $sslPath;
    private string $nginxBinary;
    private string $templatePath;

    public function __construct()
    {
        $this->sitesAvailablePath = $_ENV['NGINX_SITES_AVAILABLE'] ?? '/etc/nginx/sites-available';
        $this->sitesEnabledPath = $_ENV['NGINX_SITES_ENABLED'] ?? '/etc/nginx/sites-enabled';
        $this->sslPath = $_ENV['NGINX_SSL_PATH'] ?? '/etc/nginx/ssl';
        $this->nginxBinary = $_ENV['NGINX_BINARY'] ?? 'nginx';
        $this->templatePath = __DIR__ . '/../templates/nginx';
    }

    /**
     * Generate nginx site configuration from domain configuration
     */
    public function generateSiteConfig(array $domainConfig): string
    {
        $template = $this->loadTemplate('site.conf.tpl');
        
        // Extract domain information
        $domain = $domainConfig['domain'];
        $domainId = $domainConfig['domain_id'];
        $siteId = str_replace('domain_', '', $domainId);
        $sslEnabled = $domainConfig['ssl_enabled'] ?? true;
        
        // Template variables
        $variables = [
            '{{DOMAIN}}' => $domain,
            '{{DOMAIN_ID}}' => $domainId,
            '{{SITE_ID}}' => $siteId,
            '{{SSL_CERTIFICATE}}' => "{$this->sslPath}/{$domain}.crt",
            '{{SSL_CERTIFICATE_KEY}}' => "{$this->sslPath}/{$domain}.key",
            '{{SSL_ENABLED}}' => $sslEnabled ? 'true' : 'false',
            '{{CLIENT_MAX_BODY_SIZE}}' => $domainConfig['max_upload_size'] ?? '50M',
            '{{ACCESS_LOG}}' => "/var/log/nginx/{$domain}.access.log",
            '{{ERROR_LOG}}' => "/var/log/nginx/{$domain}.error.log",
            '{{FEATURES}}' => $this->generateFeaturesConfig($domainConfig['features'] ?? []),
            '{{SECURITY_HEADERS}}' => $this->generateSecurityHeaders($domainConfig),
            '{{RATE_LIMITS}}' => $this->generateRateLimits($domainConfig['rate_limits'] ?? [])
        ];

        return str_replace(array_keys($variables), array_values($variables), $template);
    }

    /**
     * Load nginx configuration template
     */
    private function loadTemplate(string $templateName): string
    {
        $templateFile = "{$this->templatePath}/{$templateName}";
        
        if (!file_exists($templateFile)) {
            // Return default template if file doesn't exist
            return $this->getDefaultTemplate();
        }

        return file_get_contents($templateFile);
    }

    /**
     * Get default nginx site configuration template
     */
    private function getDefaultTemplate(): string
    {
        return <<<'TEMPLATE'
server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}} www.{{DOMAIN}};
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name {{DOMAIN}} www.{{DOMAIN}};

    # SSL Configuration
    ssl_certificate {{SSL_CERTIFICATE}};
    ssl_certificate_key {{SSL_CERTIFICATE_KEY}};

    {{SECURITY_HEADERS}}

    # Root directory for PHP application
    root /var/www/html/public;
    index index.php index.html;

    # Client upload limit
    client_max_body_size {{CLIENT_MAX_BODY_SIZE}};

    {{RATE_LIMITS}}

    # PHP application handling
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # PHP-FPM configuration
    location ~ \.php$ {
        fastcgi_pass php-fpm:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_HOST $server_name;
        fastcgi_param SERVER_NAME $server_name;
        fastcgi_param DOMAIN_ID "{{DOMAIN_ID}}";
        include fastcgi_params;
    }

    # API routes
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        try_files $uri $uri/ /index.php?$query_string;
    }

    # WebSocket proxy for real-time features
    location /ws {
        proxy_pass http://frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Site-ID "{{SITE_ID}}";
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }

    {{FEATURES}}

    # Static assets
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # Media files (uploads)
    location /media/ {
        expires 30d;
        add_header Cache-Control "public";
        try_files $uri =404;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~ /\.ht {
        deny all;
    }

    # Logging
    access_log {{ACCESS_LOG}} main;
    error_log {{ERROR_LOG}};
}
TEMPLATE;
    }

    /**
     * Generate security headers configuration
     */
    private function generateSecurityHeaders(array $domainConfig): string
    {
        $headers = [
            'Strict-Transport-Security' => 'max-age=63072000; includeSubDomains; preload',
            'Content-Security-Policy' => "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://js.stripe.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.stripe.com wss:; media-src 'self' https:; frame-src https://js.stripe.com;",
            'X-Frame-Options' => 'DENY',
            'X-Content-Type-Options' => 'nosniff',
            'X-XSS-Protection' => '1; mode=block',
            'Referrer-Policy' => 'strict-origin-when-cross-origin'
        ];

        // Override with custom headers if provided
        if (isset($domainConfig['security_headers'])) {
            $headers = array_merge($headers, $domainConfig['security_headers']);
        }

        $headerConfig = "# Security headers\n";
        foreach ($headers as $header => $value) {
            $headerConfig .= "    add_header {$header} \"{$value}\";\n";
        }

        return $headerConfig;
    }

    /**
     * Generate rate limiting configuration
     */
    private function generateRateLimits(array $rateLimits): string
    {
        if (empty($rateLimits)) {
            return '';
        }

        $config = "# Rate limiting\n";
        foreach ($rateLimits as $zone => $limit) {
            $config .= "    limit_req zone={$zone} burst={$limit['burst']} nodelay;\n";
        }

        return $config;
    }

    /**
     * Generate feature-specific configuration
     */
    private function generateFeaturesConfig(array $features): string
    {
        $config = "# Feature-specific configurations\n";

        // Video/audio streaming configuration
        if ($features['video_calls'] ?? false) {
            $config .= <<<'CONFIG'
    # Video streaming configuration
    location /stream/ {
        proxy_pass http://streaming-service;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        proxy_buffering off;
    }

CONFIG;
        }

        // File upload configuration
        if ($features['file_uploads'] ?? false) {
            $config .= <<<'CONFIG'
    # File upload configuration
    location /upload/ {
        client_max_body_size 100M;
        proxy_pass http://upload-service;
        proxy_request_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

CONFIG;
        }

        return $config;
    }

    /**
     * Write nginx site configuration to file
     */
    public function writeSiteConfig(string $domain, string $config): bool
    {
        $configFile = "{$this->sitesAvailablePath}/{$domain}";
        
        // Ensure directory exists
        if (!is_dir($this->sitesAvailablePath)) {
            mkdir($this->sitesAvailablePath, 0755, true);
        }

        return file_put_contents($configFile, $config) !== false;
    }

    /**
     * Enable nginx site (create symlink)
     */
    public function enableSite(string $domain): bool
    {
        $availableFile = "{$this->sitesAvailablePath}/{$domain}";
        $enabledFile = "{$this->sitesEnabledPath}/{$domain}";

        // Ensure directory exists
        if (!is_dir($this->sitesEnabledPath)) {
            mkdir($this->sitesEnabledPath, 0755, true);
        }

        // Remove existing symlink if it exists
        if (is_link($enabledFile)) {
            unlink($enabledFile);
        }

        return symlink("../sites-available/{$domain}", $enabledFile);
    }

    /**
     * Disable nginx site (remove symlink)
     */
    public function disableSite(string $domain): bool
    {
        $enabledFile = "{$this->sitesEnabledPath}/{$domain}";
        
        if (is_link($enabledFile) || file_exists($enabledFile)) {
            return unlink($enabledFile);
        }

        return true; // Already disabled
    }

    /**
     * Remove nginx site configuration
     */
    public function removeSiteConfig(string $domain): bool
    {
        $configFile = "{$this->sitesAvailablePath}/{$domain}";
        
        if (file_exists($configFile)) {
            return unlink($configFile);
        }

        return true; // Already removed
    }

    /**
     * Test nginx configuration
     */
    public function testConfiguration(): bool
    {
        $command = "{$this->nginxBinary} -t 2>&1";
        $output = [];
        $returnCode = 0;

        exec($command, $output, $returnCode);

        return $returnCode === 0;
    }

    /**
     * Reload nginx configuration
     */
    public function reload(): bool
    {
        $command = "{$this->nginxBinary} -s reload 2>&1";
        $output = [];
        $returnCode = 0;

        exec($command, $output, $returnCode);

        return $returnCode === 0;
    }

    /**
     * Get nginx status information
     */
    public function getStatus(): array
    {
        // Check if nginx is running
        $command = "pgrep nginx";
        $output = [];
        $returnCode = 0;
        
        exec($command, $output, $returnCode);
        $isRunning = $returnCode === 0 && !empty($output);

        // Get configuration test status
        $configValid = $this->testConfiguration();

        // Get enabled sites
        $enabledSites = [];
        if (is_dir($this->sitesEnabledPath)) {
            $enabledSites = array_diff(scandir($this->sitesEnabledPath), ['.', '..']);
        }

        // Get available sites
        $availableSites = [];
        if (is_dir($this->sitesAvailablePath)) {
            $availableSites = array_diff(scandir($this->sitesAvailablePath), ['.', '..']);
        }

        return [
            'running' => $isRunning,
            'config_valid' => $configValid,
            'enabled_sites' => array_values($enabledSites),
            'available_sites' => array_values($availableSites),
            'sites_available_path' => $this->sitesAvailablePath,
            'sites_enabled_path' => $this->sitesEnabledPath
        ];
    }

    /**
     * Validate domain format
     */
    public function validateDomainFormat(string $domain): bool
    {
        return filter_var($domain, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME) !== false;
    }
}