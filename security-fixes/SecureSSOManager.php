<?php
/**
 * Secure SSO Manager with Database Token Storage
 */

namespace AEIMS\Services;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

class SecureSSOManager {
    private $secretKey;
    private $trustedDomains;
    private $db;

    public function __construct() {
        $this->loadSecretKey();
        $this->loadTrustedDomains();
        $this->initializeDatabase();
    }

    /**
     * Initialize database connection with encryption
     */
    private function initializeDatabase(): void {
        $config = require __DIR__ . '/../config/database.php';

        try {
            $this->db = new \PDO(
                "mysql:host={$config['host']};dbname={$config['database']};charset=utf8mb4",
                $config['username'],
                $config['password'],
                [
                    \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
                    \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
                    \PDO::ATTR_EMULATE_PREPARES => false,
                ]
            );

            // Create secure token storage table if not exists
            $this->createTokenTable();
        } catch (\PDOException $e) {
            throw new \Exception('Database connection failed: ' . $e->getMessage());
        }
    }

    /**
     * Create encrypted token storage table
     */
    private function createTokenTable(): void {
        $sql = "
            CREATE TABLE IF NOT EXISTS sso_tokens (
                token_id VARCHAR(255) PRIMARY KEY,
                customer_id INT NOT NULL,
                origin_domain VARCHAR(255) NOT NULL,
                token_hash VARCHAR(512) NOT NULL,
                encrypted_payload TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                expires_at TIMESTAMP NOT NULL,
                invalidated_at TIMESTAMP NULL,
                active BOOLEAN DEFAULT TRUE,
                INDEX idx_customer_id (customer_id),
                INDEX idx_expires_at (expires_at),
                INDEX idx_active (active)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ";

        $this->db->exec($sql);
    }

    /**
     * Store token securely in database with encryption
     */
    private function storeToken(string $tokenId, array $tokenData): void {
        $encryptionKey = substr(hash('sha256', $this->secretKey), 0, 32);
        $iv = random_bytes(16);

        // Encrypt sensitive token data
        $payload = json_encode([
            'token' => $tokenData['token'],
            'additional_data' => $tokenData
        ]);

        $encryptedPayload = base64_encode($iv . openssl_encrypt(
            $payload,
            'AES-256-CBC',
            $encryptionKey,
            OPENSSL_RAW_DATA,
            $iv
        ));

        $sql = "
            INSERT INTO sso_tokens (
                token_id, customer_id, origin_domain, token_hash,
                encrypted_payload, expires_at, active
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                token_hash = VALUES(token_hash),
                encrypted_payload = VALUES(encrypted_payload),
                expires_at = VALUES(expires_at),
                active = VALUES(active)
        ";

        $stmt = $this->db->prepare($sql);
        $stmt->execute([
            $tokenId,
            $tokenData['customer_id'],
            $tokenData['origin_domain'],
            hash('sha256', $tokenData['token']),
            $encryptedPayload,
            $tokenData['expires_at'],
            $tokenData['active'] ? 1 : 0
        ]);
    }

    /**
     * Load token securely from database
     */
    private function loadToken(string $tokenId): ?array {
        $sql = "SELECT * FROM sso_tokens WHERE token_id = ? AND active = 1 AND expires_at > NOW()";
        $stmt = $this->db->prepare($sql);
        $stmt->execute([$tokenId]);

        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }

        $encryptionKey = substr(hash('sha256', $this->secretKey), 0, 32);
        $encryptedData = base64_decode($row['encrypted_payload']);
        $iv = substr($encryptedData, 0, 16);
        $encrypted = substr($encryptedData, 16);

        $decrypted = openssl_decrypt(
            $encrypted,
            'AES-256-CBC',
            $encryptionKey,
            OPENSSL_RAW_DATA,
            $iv
        );

        if ($decrypted === false) {
            throw new \Exception('Token decryption failed');
        }

        return json_decode($decrypted, true);
    }

    /**
     * Invalidate token securely
     */
    private function invalidateToken(string $tokenId): void {
        $sql = "UPDATE sso_tokens SET active = 0, invalidated_at = NOW() WHERE token_id = ?";
        $stmt = $this->db->prepare($sql);
        $stmt->execute([$tokenId]);
    }

    /**
     * Check if token is active and valid
     */
    private function isTokenActive(string $tokenId): bool {
        $sql = "SELECT COUNT(*) FROM sso_tokens WHERE token_id = ? AND active = 1 AND expires_at > NOW()";
        $stmt = $this->db->prepare($sql);
        $stmt->execute([$tokenId]);

        return $stmt->fetchColumn() > 0;
    }

    /**
     * Clean up expired tokens (should be run via cron)
     */
    public function cleanupExpiredTokens(): int {
        $sql = "DELETE FROM sso_tokens WHERE expires_at < NOW() OR invalidated_at < DATE_SUB(NOW(), INTERVAL 30 DAY)";
        $stmt = $this->db->prepare($sql);
        $stmt->execute();

        return $stmt->rowCount();
    }

    /**
     * Get active token count for monitoring
     */
    public function getActiveTokenCount(): int {
        $sql = "SELECT COUNT(*) FROM sso_tokens WHERE active = 1 AND expires_at > NOW()";
        $stmt = $this->db->prepare($sql);
        $stmt->execute();

        return $stmt->fetchColumn();
    }

    /**
     * Load secret key securely
     */
    private function loadSecretKey(): void {
        $keyFile = __DIR__ . '/../config/sso_secret.key';

        if (!file_exists($keyFile)) {
            // Generate secure random key
            $secretKey = base64_encode(random_bytes(64));
            file_put_contents($keyFile, $secretKey, LOCK_EX);
            chmod($keyFile, 0600); // Read-only for owner
        }

        $this->secretKey = file_get_contents($keyFile);
    }

    /**
     * Load trusted domains
     */
    private function loadTrustedDomains(): void {
        $domainsFile = __DIR__ . '/../config/trusted_domains.json';

        if (file_exists($domainsFile)) {
            $this->trustedDomains = json_decode(file_get_contents($domainsFile), true) ?: [];
        } else {
            $this->trustedDomains = [];
        }
    }

    /**
     * Generate secure JWT token
     */
    public function generateToken(array $customer, string $originDomain): string {
        if (!in_array($originDomain, $this->trustedDomains)) {
            throw new \Exception("Domain not trusted: $originDomain");
        }

        $tokenId = 'sso_' . bin2hex(random_bytes(16)); // More secure random
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

        $token = JWT::encode($payload, $this->secretKey, 'HS256');

        // Store token securely in database
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
     * Validate JWT token securely
     */
    public function validateToken(string $token): ?array {
        try {
            $decoded = JWT::decode($token, new Key($this->secretKey, 'HS256'));
            $tokenData = (array) $decoded;

            $tokenId = $tokenData['jti'] ?? null;
            if (!$tokenId || !$this->isTokenActive($tokenId)) {
                return null;
            }

            return $tokenData;
        } catch (\Exception $e) {
            error_log('JWT validation failed: ' . $e->getMessage());
            return null;
        }
    }

    // ... Additional SSO methods (authenticate, etc.)
}
?>