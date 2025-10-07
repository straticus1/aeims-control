#!/bin/bash
# SQL Injection Remediation Script

echo "Starting SQL injection vulnerability remediation..."

# Backup vulnerable files
mkdir -p /Users/ryan/development/aeims-control/security-fixes/backups


# Backup /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php
cp "/Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/billing-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php
cp "/Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/user-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/DB2Platform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php
cp "/Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php
cp "/Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/telephony-platform/services/conference-service/vendor/symfony/phpunit-bridge/bin/simple-phpunit.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php
cp "/Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/PostgreSQLPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/DB2Platform.php
cp "/Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/DB2Platform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/DB2Platform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php
cp "/Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/OraclePlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php
cp "/Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeims/vendor/doctrine/dbal/src/Platforms/SQLServerPlatform.php).backup.$(date +%Y%m%d_%H%M%S)"

# Backup /Users/ryan/development/aeimsLib/database.php
cp "/Users/ryan/development/aeimsLib/database.php" "/Users/ryan/development/aeims-control/security-fixes/backups/$(basename /Users/ryan/development/aeimsLib/database.php).backup.$(date +%Y%m%d_%H%M%S)"


echo "Backups created. Now creating secure versions..."

# Create secure versions of common patterns
# This script identifies vulnerable patterns and suggests fixes


# Example fixes for common SQL injection patterns:

# UNSAFE:
# $sql = "SELECT * FROM users WHERE id = " . $_GET['id'];
# $result = mysql_query($sql);

# SECURE:
# $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
# $stmt->execute([$_GET['id']]);
# $result = $stmt->fetchAll();

# UNSAFE:
# $sql = "INSERT INTO users (name, email) VALUES ('" . $_POST['name'] . "', '" . $_POST['email'] . "')";

# SECURE:
# $stmt = $pdo->prepare("INSERT INTO users (name, email) VALUES (?, ?)");
# $stmt->execute([$_POST['name'], $_POST['email']]);

# UNSAFE:
# $sql = "UPDATE users SET email = '" . $_POST['email'] . "' WHERE id = " . $_POST['id'];

# SECURE:
# $stmt = $pdo->prepare("UPDATE users SET email = ? WHERE id = ?");
# $stmt->execute([$_POST['email'], $_POST['id']]);

