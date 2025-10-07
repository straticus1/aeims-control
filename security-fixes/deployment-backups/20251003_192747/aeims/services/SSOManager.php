<?php

namespace AEIMS\Services;

use Exception;

/**
 * Single Sign-On (SSO) Manager
 * Handles unified authentication across all After Dark Systems domains
 */
class SSOManager
{
    private CustomerManager $customerManager;
    private string $ssoTokenFile;
    private string $secretKey;
    private array $trustedDomains;

    public function __construct()
    {
        $this->customerManager = new CustomerManager();
        $this->ssoTokenFile = __DIR__ . '/../data/sso_tokens.json';
        $this->secretKey = $this->getSecretKey();
        $this->trustedDomains = [
            'flirts.nyc',
            'nycflirts.com',
            'aeims.app',
            'afterdarksystems.net',
            // Add more domains as needed
        ];
    }

    /**
     * Generate secure secret key for JWT signing
     */
    private function getSecretKey(): string
    {
        $keyFile = __DIR__ . '/../data/sso_secret.key';

        if (!file_exists($keyFile)) {
            $secretKey = bin2hex(random_bytes(32));
            $dataDir = dirname($keyFile);
            if (!is_dir($dataDir)) {
                mkdir($dataDir, 0755, true);
            }
            file_put_contents($keyFile, $secretKey);
            chmod($keyFile, 0600);
        } else {
            $secretKey = file_get_contents($keyFile);
        }

        return $secretKey;
    }

    /**
     * Authenticate user and create SSO token
     */
    public function authenticate(string $username, string $password, string $originDomain): array
    {
        $customer = $this->customerManager->authenticate($username, $password, $originDomain);

        if (!$customer) {
            throw new Exception('Invalid credentials');
        }

        // Generate SSO token
        $ssoToken = $this->generateSSOToken($customer, $originDomain);

        return [
            'customer' => $customer,
            'sso_token' => $ssoToken,
            'success' => true
        ];
    }

    /**
     * Generate JWT-like SSO token
     */
    private function generateSSOToken(array $customer, string $originDomain): string
    {
        $tokenId = 'sso_' . uniqid();
        $issuedAt = time();
        $expiresAt = $issuedAt + (24 * 60 * 60); // 24 hours

        $payload = [
            'jti' => $tokenId,
            'iat' => $issuedAt,
            'exp' => $expiresAt,
            'customer_id' => $customer['customer_id'],
            'username' => $customer['username'],
            'email' => $customer['email'],
            'origin_domain' => $originDomain,
            'domains' => $this->trustedDomains
        ];

        $header = [
            'typ' => 'JWT',
            'alg' => 'HS256'
        ];

        $headerEncoded = $this->base64UrlEncode(json_encode($header));
        $payloadEncoded = $this->base64UrlEncode(json_encode($payload));

        $signature = hash_hmac('sha256', $headerEncoded . '.' . $payloadEncoded, $this->secretKey, true);
        $signatureEncoded = $this->base64UrlEncode($signature);

        $token = $headerEncoded . '.' . $payloadEncoded . '.' . $signatureEncoded;

        // Store token for tracking
        $this->storeToken($tokenId, [
            'token' => $token,
            'customer_id' => $customer['customer_id'],
            'origin_domain' => $originDomain,
            'created_at' => date('Y-m-d H:i:s'),
            'expires_at' => date('Y-m-d H:i:s', $expiresAt),
            'active' => true
        ]);

        return $token;
    }

    /**
     * Validate SSO token
     */
    public function validateToken(string $token): ?array
    {
        try {
            $parts = explode('.', $token);
            if (count($parts) !== 3) {
                return null;
            }

            [$headerEncoded, $payloadEncoded, $signatureEncoded] = $parts;

            // Verify signature
            $expectedSignature = hash_hmac('sha256', $headerEncoded . '.' . $payloadEncoded, $this->secretKey, true);
            $expectedSignatureEncoded = $this->base64UrlEncode($expectedSignature);

            if (!hash_equals($expectedSignatureEncoded, $signatureEncoded)) {
                return null;
            }

            $payload = json_decode($this->base64UrlDecode($payloadEncoded), true);

            // Check expiration
            if ($payload['exp'] < time()) {
                $this->invalidateToken($payload['jti']);
                return null;
            }

            // Check if token is still active
            if (!$this->isTokenActive($payload['jti'])) {
                return null;
            }

            return $payload;
        } catch (Exception $e) {
            return null;
        }
    }

    /**
     * Get customer data from valid SSO token
     */
    public function getCustomerFromToken(string $token): ?array
    {
        $payload = $this->validateToken($token);
        if (!$payload) {
            return null;
        }

        return $this->customerManager->getCustomerById($payload['customer_id']);
    }

    /**
     * Create SSO login URL for cross-domain authentication
     */
    public function createSSOLoginUrl(string $targetDomain, string $ssoToken, string $returnPath = '/'): string
    {
        if (!in_array($targetDomain, $this->trustedDomains)) {
            throw new Exception('Untrusted domain');
        }

        $params = http_build_query([
            'sso_token' => $ssoToken,
            'return_path' => $returnPath
        ]);

        return "https://{$targetDomain}/sso/login?{$params}";
    }

    /**
     * Process SSO login from another domain
     */
    public function processSSOLogin(string $ssoToken, string $targetDomain): array
    {
        $customer = $this->getCustomerFromToken($ssoToken);

        if (!$customer) {
            throw new Exception('Invalid or expired SSO token');
        }

        // Log cross-domain login
        $this->customerManager->logActivity($customer['customer_id'], 'sso_login', [
            'target_domain' => $targetDomain,
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
        ]);

        return $customer;
    }

    /**
     * Logout user from all domains
     */
    public function globalLogout(string $customerId): array
    {
        // Get all active tokens for this customer
        $tokens = $this->getCustomerTokens($customerId);

        // Invalidate all tokens
        foreach ($tokens as $tokenData) {
            $this->invalidateToken($tokenData['jti']);
        }

        // Create logout URLs for all trusted domains
        $logoutUrls = [];
        foreach ($this->trustedDomains as $domain) {
            $logoutUrls[] = "https://{$domain}/sso/logout?customer_id={$customerId}";
        }

        return [
            'tokens_invalidated' => count($tokens),
            'logout_urls' => $logoutUrls
        ];
    }

    /**
     * Store SSO token
     */
    private function storeToken(string $tokenId, array $tokenData): void
    {
        $tokens = $this->loadTokens();
        $tokens[$tokenId] = $tokenData;
        $this->saveTokens($tokens);
    }

    /**
     * Check if token is active
     */
    private function isTokenActive(string $tokenId): bool
    {
        $tokens = $this->loadTokens();
        return isset($tokens[$tokenId]) && $tokens[$tokenId]['active'];
    }

    /**
     * Invalidate token
     */
    private function invalidateToken(string $tokenId): void
    {
        $tokens = $this->loadTokens();
        if (isset($tokens[$tokenId])) {
            $tokens[$tokenId]['active'] = false;
            $tokens[$tokenId]['invalidated_at'] = date('Y-m-d H:i:s');
            $this->saveTokens($tokens);
        }
    }

    /**
     * Get all tokens for a customer
     */
    private function getCustomerTokens(string $customerId): array
    {
        $tokens = $this->loadTokens();
        $customerTokens = [];

        foreach ($tokens as $tokenId => $tokenData) {
            if ($tokenData['customer_id'] === $customerId && $tokenData['active']) {
                $payload = $this->validateToken($tokenData['token']);
                if ($payload) {
                    $customerTokens[] = array_merge($tokenData, ['jti' => $tokenId]);
                }
            }
        }

        return $customerTokens;
    }

    /**
     * Load tokens from storage
     */
    private function loadTokens(): array
    {
        if (!file_exists($this->ssoTokenFile)) {
            return [];
        }

        $data = json_decode(file_get_contents($this->ssoTokenFile), true);
        return $data['tokens'] ?? [];
    }

    /**
     * Save tokens to storage
     */
    private function saveTokens(array $tokens): void
    {
        $dataDir = dirname($this->ssoTokenFile);
        if (!is_dir($dataDir)) {
            mkdir($dataDir, 0755, true);
        }

        $data = [
            'tokens' => $tokens,
            'last_updated' => date('Y-m-d H:i:s')
        ];

        file_put_contents($this->ssoTokenFile, json_encode($data, JSON_PRETTY_PRINT));
    }

    /**
     * Clean expired tokens
     */
    public function cleanExpiredTokens(): int
    {
        $tokens = $this->loadTokens();
        $cleaned = 0;

        foreach ($tokens as $tokenId => $tokenData) {
            $payload = json_decode($this->base64UrlDecode(explode('.', $tokenData['token'])[1]), true);
            if ($payload['exp'] < time()) {
                unset($tokens[$tokenId]);
                $cleaned++;
            }
        }

        if ($cleaned > 0) {
            $this->saveTokens($tokens);
        }

        return $cleaned;
    }

    /**
     * Base64 URL encode
     */
    private function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /**
     * Base64 URL decode
     */
    private function base64UrlDecode(string $data): string
    {
        return base64_decode(str_pad(strtr($data, '-_', '+/'), strlen($data) % 4, '=', STR_PAD_RIGHT));
    }
}