<?php
/**
 * Secure Database Helper - Prevents SQL Injection
 */

namespace AEIMS\Security;

class SecureDatabase {
    private $pdo;

    public function __construct(\PDO $pdo) {
        $this->pdo = $pdo;

        // Set secure PDO options
        $this->pdo->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
        $this->pdo->setAttribute(\PDO::ATTR_EMULATE_PREPARES, false);
        $this->pdo->setAttribute(\PDO::ATTR_DEFAULT_FETCH_MODE, \PDO::FETCH_ASSOC);
    }

    /**
     * Execute secure prepared statement
     */
    public function execute(string $sql, array $params = []): \PDOStatement {
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    /**
     * Secure SELECT query
     */
    public function select(string $sql, array $params = []): array {
        $stmt = $this->execute($sql, $params);
        return $stmt->fetchAll();
    }

    /**
     * Secure SELECT single row
     */
    public function selectOne(string $sql, array $params = []): ?array {
        $stmt = $this->execute($sql, $params);
        $result = $stmt->fetch();
        return $result ?: null;
    }

    /**
     * Secure INSERT query
     */
    public function insert(string $table, array $data): int {
        $columns = array_keys($data);
        $placeholders = array_map(fn($col) => ":$col", $columns);

        $sql = "INSERT INTO `$table` (`" . implode("`, `", $columns) . "`)
                VALUES (" . implode(", ", $placeholders) . ")";

        $stmt = $this->execute($sql, $data);
        return $this->pdo->lastInsertId();
    }

    /**
     * Secure UPDATE query
     */
    public function update(string $table, array $data, string $where, array $whereParams = []): int {
        $setClause = array_map(fn($col) => "`$col` = :$col", array_keys($data));

        $sql = "UPDATE `$table` SET " . implode(", ", $setClause) . " WHERE $where";

        $params = array_merge($data, $whereParams);
        $stmt = $this->execute($sql, $params);
        return $stmt->rowCount();
    }

    /**
     * Secure DELETE query
     */
    public function delete(string $table, string $where, array $params = []): int {
        $sql = "DELETE FROM `$table` WHERE $where";
        $stmt = $this->execute($sql, $params);
        return $stmt->rowCount();
    }

    /**
     * Validate table/column names to prevent injection
     */
    public function validateIdentifier(string $identifier): bool {
        return preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $identifier);
    }

    /**
     * Escape identifier (table/column names)
     */
    public function escapeIdentifier(string $identifier): string {
        if (!$this->validateIdentifier($identifier)) {
            throw new \InvalidArgumentException("Invalid identifier: $identifier");
        }
        return "`$identifier`";
    }

    /**
     * Begin transaction
     */
    public function beginTransaction(): bool {
        return $this->pdo->beginTransaction();
    }

    /**
     * Commit transaction
     */
    public function commit(): bool {
        return $this->pdo->commit();
    }

    /**
     * Rollback transaction
     */
    public function rollback(): bool {
        return $this->pdo->rollBack();
    }

    /**
     * Get last insert ID
     */
    public function getLastInsertId(): string {
        return $this->pdo->lastInsertId();
    }
}
?>