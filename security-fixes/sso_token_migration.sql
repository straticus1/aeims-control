
-- SSO Token Security Migration
-- Run this to create secure token storage

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clean up old JSON token files (manual step)
-- rm /path/to/sso_tokens.json
