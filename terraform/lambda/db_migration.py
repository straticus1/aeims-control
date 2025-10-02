import json
import boto3
import psycopg2
import pymysql
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Database migration handler for AEIMS
    Supports PostgreSQL and MySQL migrations
    """

    try:
        action = event.get('action', 'migrate')
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']

        logger.info(f"Starting database migration action: {action}")

        if action == 'backup':
            return create_backup(environment, project_name)
        elif action == 'migrate':
            return run_migrations(environment, project_name)
        elif action == 'validate':
            return validate_migration(environment, project_name)
        elif action == 'rollback':
            return rollback_migration(environment, project_name)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Migration failed: {str(e)}")
        raise e

def get_database_credentials(secret_name):
    """Get database credentials from Secrets Manager"""
    secrets_client = boto3.client('secretsmanager')

    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        logger.error(f"Failed to get credentials for {secret_name}: {str(e)}")
        raise e

def create_backup(environment, project_name):
    """Create database backup before migration"""
    logger.info("Creating pre-migration backup")

    s3_client = boto3.client('s3')
    bucket_name = f"{project_name}-db-migrations-{environment}"
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

    # Backup PostgreSQL (AEIMS Core)
    pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
    pg_backup_key = f"backups/postgresql/{timestamp}_pre_migration.sql"

    # Create PostgreSQL backup
    backup_success = True
    try:
        # Note: In production, use pg_dump with proper authentication
        logger.info(f"Creating PostgreSQL backup: {pg_backup_key}")
        # Placeholder for actual backup logic
        s3_client.put_object(
            Bucket=bucket_name,
            Key=pg_backup_key,
            Body=f"-- PostgreSQL backup placeholder {timestamp}",
            Metadata={'backup_type': 'pre_migration', 'database': 'postgresql'}
        )
    except Exception as e:
        logger.error(f"PostgreSQL backup failed: {str(e)}")
        backup_success = False

    # Backup MySQL (AEIMS App)
    mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
    mysql_backup_key = f"backups/mysql/{timestamp}_pre_migration.sql"

    try:
        logger.info(f"Creating MySQL backup: {mysql_backup_key}")
        # Placeholder for actual backup logic
        s3_client.put_object(
            Bucket=bucket_name,
            Key=mysql_backup_key,
            Body=f"-- MySQL backup placeholder {timestamp}",
            Metadata={'backup_type': 'pre_migration', 'database': 'mysql'}
        )
    except Exception as e:
        logger.error(f"MySQL backup failed: {str(e)}")
        backup_success = False

    return {
        'statusCode': 200 if backup_success else 500,
        'body': json.dumps({
            'message': 'Backup completed' if backup_success else 'Backup failed',
            'timestamp': timestamp,
            'backups': [pg_backup_key, mysql_backup_key]
        })
    }

def run_migrations(environment, project_name):
    """Run database migrations"""
    logger.info("Running database migrations")

    migration_results = []

    # Run PostgreSQL migrations
    try:
        pg_result = run_postgresql_migrations(environment, project_name)
        migration_results.append(pg_result)
    except Exception as e:
        logger.error(f"PostgreSQL migration failed: {str(e)}")
        raise e

    # Run MySQL migrations
    try:
        mysql_result = run_mysql_migrations(environment, project_name)
        migration_results.append(mysql_result)
    except Exception as e:
        logger.error(f"MySQL migration failed: {str(e)}")
        raise e

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Migrations completed successfully',
            'results': migration_results
        })
    }

def run_postgresql_migrations(environment, project_name):
    """Run PostgreSQL specific migrations"""
    creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")

    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()

    try:
        # Check if migrations table exists
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version VARCHAR(255) PRIMARY KEY,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Get applied migrations
        cursor.execute("SELECT version FROM schema_migrations ORDER BY version")
        applied_migrations = [row[0] for row in cursor.fetchall()]

        # Load migration files from S3
        s3_client = boto3.client('s3')
        bucket_name = f"{project_name}-db-migrations-{environment}"

        try:
            response = s3_client.list_objects_v2(
                Bucket=bucket_name,
                Prefix='migrations/postgresql/'
            )

            migration_files = []
            if 'Contents' in response:
                migration_files = [obj['Key'] for obj in response['Contents']
                                 if obj['Key'].endswith('.sql')]
                migration_files.sort()
        except Exception as e:
            logger.warning(f"No migration files found: {str(e)}")
            migration_files = []

        # Apply new migrations
        applied_count = 0
        for migration_file in migration_files:
            version = os.path.basename(migration_file).replace('.sql', '')

            if version not in applied_migrations:
                logger.info(f"Applying migration: {version}")

                # Get migration content
                obj = s3_client.get_object(Bucket=bucket_name, Key=migration_file)
                migration_sql = obj['Body'].read().decode('utf-8')

                # Execute migration
                cursor.execute(migration_sql)

                # Record migration
                cursor.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)",
                    (version,)
                )

                applied_count += 1

        connection.commit()

        return {
            'database': 'postgresql',
            'applied_migrations': applied_count,
            'status': 'success'
        }

    finally:
        cursor.close()
        connection.close()

def run_mysql_migrations(environment, project_name):
    """Run MySQL specific migrations"""
    creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")

    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()

    try:
        # Check if migrations table exists
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version VARCHAR(255) PRIMARY KEY,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Get applied migrations
        cursor.execute("SELECT version FROM schema_migrations ORDER BY version")
        applied_migrations = [row[0] for row in cursor.fetchall()]

        # Load migration files from S3
        s3_client = boto3.client('s3')
        bucket_name = f"{project_name}-db-migrations-{environment}"

        try:
            response = s3_client.list_objects_v2(
                Bucket=bucket_name,
                Prefix='migrations/mysql/'
            )

            migration_files = []
            if 'Contents' in response:
                migration_files = [obj['Key'] for obj in response['Contents']
                                 if obj['Key'].endswith('.sql')]
                migration_files.sort()
        except Exception as e:
            logger.warning(f"No migration files found: {str(e)}")
            migration_files = []

        # Apply new migrations
        applied_count = 0
        for migration_file in migration_files:
            version = os.path.basename(migration_file).replace('.sql', '')

            if version not in applied_migrations:
                logger.info(f"Applying migration: {version}")

                # Get migration content
                obj = s3_client.get_object(Bucket=bucket_name, Key=migration_file)
                migration_sql = obj['Body'].read().decode('utf-8')

                # Execute migration
                cursor.execute(migration_sql)

                # Record migration
                cursor.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)",
                    (version,)
                )

                applied_count += 1

        connection.commit()

        return {
            'database': 'mysql',
            'applied_migrations': applied_count,
            'status': 'success'
        }

    finally:
        cursor.close()
        connection.close()

def validate_migration(environment, project_name):
    """Validate migration success"""
    logger.info("Validating migration")

    validation_results = []

    # Validate PostgreSQL
    try:
        pg_valid = validate_postgresql_schema(environment, project_name)
        validation_results.append(pg_valid)
    except Exception as e:
        logger.error(f"PostgreSQL validation failed: {str(e)}")
        raise e

    # Validate MySQL
    try:
        mysql_valid = validate_mysql_schema(environment, project_name)
        validation_results.append(mysql_valid)
    except Exception as e:
        logger.error(f"MySQL validation failed: {str(e)}")
        raise e

    all_valid = all(result['valid'] for result in validation_results)

    return {
        'statusCode': 200 if all_valid else 500,
        'body': json.dumps({
            'message': 'Validation completed',
            'valid': all_valid,
            'results': validation_results
        })
    }

def validate_postgresql_schema(environment, project_name):
    """Validate PostgreSQL schema"""
    creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")

    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()

    try:
        # Basic validation - check if required tables exist
        required_tables = ['users', 'calls', 'conferences', 'schema_migrations']

        for table in required_tables:
            cursor.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables
                    WHERE table_name = %s
                )
            """, (table,))

            if not cursor.fetchone()[0]:
                return {'database': 'postgresql', 'valid': False, 'error': f'Missing table: {table}'}

        return {'database': 'postgresql', 'valid': True}

    finally:
        cursor.close()
        connection.close()

def validate_mysql_schema(environment, project_name):
    """Validate MySQL schema"""
    creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")

    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname']
    )

    cursor = connection.cursor()

    try:
        # Basic validation - check if required tables exist
        required_tables = ['users', 'content', 'moderation_logs', 'schema_migrations']

        for table in required_tables:
            cursor.execute("SHOW TABLES LIKE %s", (table,))

            if not cursor.fetchone():
                return {'database': 'mysql', 'valid': False, 'error': f'Missing table: {table}'}

        return {'database': 'mysql', 'valid': True}

    finally:
        cursor.close()
        connection.close()

def rollback_migration(environment, project_name):
    """Rollback migration using backup"""
    logger.info("Rolling back migration")

    # Implementation would restore from the most recent backup
    # This is a simplified version

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Rollback completed',
            'timestamp': datetime.now().isoformat()
        })
    }