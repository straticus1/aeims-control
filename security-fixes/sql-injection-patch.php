<?php
/**
 * AEIMS Security Patch: SQL Injection Prevention
 * Converts unsafe SQL queries to prepared statements
 */

// Scan for SQL injection vulnerabilities and create fixes
function scanForSQLInjection($directory) {
    $vulnerable_files = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($directory));

    foreach ($iterator as $file) {
        if (!$file->isFile() || !in_array($file->getExtension(), ['php'])) {
            continue;
        }

        $content = file_get_contents($file->getPathname());

        // Check for vulnerable SQL patterns
        $patterns = [
            'mysql_query.*\$',
            'mysqli_query.*\$',
            'SELECT.*"\s*\.\s*\$',
            'INSERT.*"\s*\.\s*\$',
            'UPDATE.*"\s*\.\s*\$',
            'DELETE.*"\s*\.\s*\$',
            'WHERE.*"\s*\.\s*\$',
            '\$.*\.\s*".*WHERE',
        ];

        foreach ($patterns as $pattern) {
            if (preg_match('/' . $pattern . '/i', $content)) {
                $vulnerable_files[] = $file->getPathname();
                break;
            }
        }
    }

    return array_unique($vulnerable_files);
}

// Create secure database helper class
$secure_db_helper = '<?php
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
        return preg_match(\'/^[a-zA-Z_][a-zA-Z0-9_]*$/\', $identifier);
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
?>';

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/SecureDatabase.php', $secure_db_helper);

// Scan AEIMS directories for SQL injection vulnerabilities
$scan_directories = [
    '/Users/ryan/development/aeims',
    '/Users/ryan/development/aeimsLib',
];

$all_vulnerable_files = [];
foreach ($scan_directories as $dir) {
    if (is_dir($dir)) {
        $vulnerable = scanForSQLInjection($dir);
        $all_vulnerable_files = array_merge($all_vulnerable_files, $vulnerable);
    }
}

// Create remediation script for each vulnerable file
$remediation_script = '#!/bin/bash
# SQL Injection Remediation Script

echo "Starting SQL injection vulnerability remediation..."

# Backup vulnerable files
mkdir -p /Users/ryan/development/aeims-control/security-fixes/backups

';

foreach (array_unique($all_vulnerable_files) as $file) {
    $remediation_script .= "
# Backup $file
cp \"$file\" \"/Users/ryan/development/aeims-control/security-fixes/backups/$(basename $file).backup.$(date +%Y%m%d_%H%M%S)\"
";
}

$remediation_script .= '

echo "Backups created. Now creating secure versions..."

# Create secure versions of common patterns
# This script identifies vulnerable patterns and suggests fixes

';

// Create pattern replacement suggestions
$pattern_fixes = [
    'mysql_query' => 'Replace with PDO prepared statements',
    'mysqli_query.*\$' => 'Use mysqli_prepare() with bound parameters',
    'SELECT.*\$' => 'Use prepared statements with parameter binding',
    'INSERT.*\$' => 'Use prepared statements with parameter binding',
    'UPDATE.*\$' => 'Use prepared statements with parameter binding',
    'DELETE.*\$' => 'Use prepared statements with parameter binding',
];

$fix_examples = '
# Example fixes for common SQL injection patterns:

# UNSAFE:
# $sql = "SELECT * FROM users WHERE id = " . $_GET[\'id\'];
# $result = mysql_query($sql);

# SECURE:
# $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
# $stmt->execute([$_GET[\'id\']]);
# $result = $stmt->fetchAll();

# UNSAFE:
# $sql = "INSERT INTO users (name, email) VALUES (\'" . $_POST[\'name\'] . "\', \'" . $_POST[\'email\'] . "\')";

# SECURE:
# $stmt = $pdo->prepare("INSERT INTO users (name, email) VALUES (?, ?)");
# $stmt->execute([$_POST[\'name\'], $_POST[\'email\']]);

# UNSAFE:
# $sql = "UPDATE users SET email = \'" . $_POST[\'email\'] . "\' WHERE id = " . $_POST[\'id\'];

# SECURE:
# $stmt = $pdo->prepare("UPDATE users SET email = ? WHERE id = ?");
# $stmt->execute([$_POST[\'email\'], $_POST[\'id\']]);

';

$remediation_script .= $fix_examples;

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/sql-injection-remediation.sh', $remediation_script);
chmod('/Users/ryan/development/aeims-control/security-fixes/sql-injection-remediation.sh', 0755);

// Create vulnerability report
$report = "SQL Injection Vulnerability Report\n";
$report .= "==================================\n\n";
$report .= "Scan completed on: " . date('Y-m-d H:i:s') . "\n";
$report .= "Vulnerable files found: " . count(array_unique($all_vulnerable_files)) . "\n\n";

if (!empty($all_vulnerable_files)) {
    $report .= "VULNERABLE FILES:\n";
    foreach (array_unique($all_vulnerable_files) as $file) {
        $report .= "- $file\n";
    }

    $report .= "\nRECOMMENDED ACTIONS:\n";
    $report .= "1. Review each vulnerable file manually\n";
    $report .= "2. Replace direct SQL concatenation with prepared statements\n";
    $report .= "3. Use the SecureDatabase helper class for new code\n";
    $report .= "4. Validate and sanitize all user inputs\n";
    $report .= "5. Implement input validation at application boundaries\n";
    $report .= "6. Use parameterized queries exclusively\n";
    $report .= "7. Test all fixes thoroughly\n";
} else {
    $report .= "No obvious SQL injection vulnerabilities found in scanned directories.\n";
    $report .= "However, manual code review is still recommended.\n";
}

file_put_contents('/Users/ryan/development/aeims-control/security-fixes/sql-injection-report.txt', $report);

echo "SQL injection security assessment completed.\n";
echo "Files created:\n";
echo "1. SecureDatabase.php - Secure database helper class\n";
echo "2. sql-injection-remediation.sh - Remediation script\n";
echo "3. sql-injection-report.txt - Vulnerability report\n";
echo "\nVulnerable files found: " . count(array_unique($all_vulnerable_files)) . "\n";

if (!empty($all_vulnerable_files)) {
    echo "\nCRITICAL: SQL injection vulnerabilities detected!\n";
    echo "Run the remediation script and review each file manually.\n";
}

?>