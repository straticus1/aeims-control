import json
import boto3
import psycopg2
import pymysql
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Data retention processor for GDPR compliance
    Automatically removes data based on retention policies
    """

    try:
        action = event.get('action', 'cleanup_expired')
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        audit_bucket = os.environ['AUDIT_BUCKET']

        logger.info(f"Processing data retention action: {action}")

        if action == 'cleanup_expired':
            return cleanup_expired_data(environment, project_name, audit_bucket)
        elif action == 'audit_retention':
            return audit_retention_compliance(environment, project_name, audit_bucket)
        elif action == 'anonymize_data':
            return anonymize_old_data(environment, project_name, audit_bucket)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Data retention processing failed: {str(e)}")
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

def audit_action(bucket_name, action_type, details):
    """Log audit action to S3"""
    s3_client = boto3.client('s3')
    timestamp = datetime.utcnow().isoformat()

    audit_record = {
        "timestamp": timestamp,
        "action_type": action_type,
        "details": details
    }

    key = f"retention-audit/{datetime.utcnow().strftime('%Y/%m/%d')}/{timestamp}_{action_type}.json"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(audit_record, indent=2),
            ContentType='application/json'
        )
    except Exception as e:
        logger.error(f"Failed to write audit record: {str(e)}")

def cleanup_expired_data(environment, project_name, audit_bucket):
    """Clean up data that has exceeded retention periods"""
    logger.info("Starting expired data cleanup")

    retention_policies = get_retention_policies()
    cleanup_results = {}

    # Cleanup PostgreSQL data
    try:
        pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
        pg_result = cleanup_postgresql_data(pg_creds, retention_policies)
        cleanup_results['postgresql'] = pg_result
    except Exception as e:
        logger.error(f"PostgreSQL cleanup failed: {str(e)}")
        cleanup_results['postgresql'] = {'error': str(e)}

    # Cleanup MySQL data
    try:
        mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
        mysql_result = cleanup_mysql_data(mysql_creds, retention_policies)
        cleanup_results['mysql'] = mysql_result
    except Exception as e:
        logger.error(f"MySQL cleanup failed: {str(e)}")
        cleanup_results['mysql'] = {'error': str(e)}

    # Cleanup S3 objects
    try:
        s3_result = cleanup_s3_objects(audit_bucket, retention_policies)
        cleanup_results['s3'] = s3_result
    except Exception as e:
        logger.error(f"S3 cleanup failed: {str(e)}")
        cleanup_results['s3'] = {'error': str(e)}

    audit_action(audit_bucket, "DATA_RETENTION_CLEANUP", {
        "cleanup_results": cleanup_results,
        "retention_policies": retention_policies
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Data retention cleanup completed',
            'cleanup_results': cleanup_results
        })
    }

def get_retention_policies():
    """Define data retention policies in days"""
    return {
        'call_logs': 2555,      # 7 years
        'user_sessions': 90,     # 3 months
        'chat_messages': 365,    # 1 year
        'user_content': 2555,    # 7 years
        'moderation_logs': 2555, # 7 years
        'audit_logs': 2922,      # 8 years
        'temp_files': 30,        # 1 month
        'inactive_users': 1095   # 3 years
    }

def cleanup_postgresql_data(creds, retention_policies):
    """Clean up expired PostgreSQL data"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    cleanup_results = {}

    try:
        # Clean up call logs
        call_log_cutoff = datetime.utcnow() - timedelta(days=retention_policies['call_logs'])
        cursor.execute(
            "DELETE FROM calls WHERE created_at < %s",
            (call_log_cutoff,)
        )
        cleanup_results['calls'] = cursor.rowcount

        # Clean up user sessions
        session_cutoff = datetime.utcnow() - timedelta(days=retention_policies['user_sessions'])
        cursor.execute(
            "DELETE FROM user_sessions WHERE created_at < %s",
            (session_cutoff,)
        )
        cleanup_results['user_sessions'] = cursor.rowcount

        # Clean up inactive users (no activity for specified period)
        inactive_cutoff = datetime.utcnow() - timedelta(days=retention_policies['inactive_users'])
        cursor.execute("""
            DELETE FROM users
            WHERE last_active < %s
            AND NOT EXISTS (
                SELECT 1 FROM calls WHERE user_id = users.id AND created_at > %s
            )
        """, (inactive_cutoff, inactive_cutoff))
        cleanup_results['inactive_users'] = cursor.rowcount

        # Clean up old conference records
        cursor.execute(
            "DELETE FROM conferences WHERE created_at < %s AND status = 'ended'",
            (call_log_cutoff,)
        )
        cleanup_results['conferences'] = cursor.rowcount

        connection.commit()

        return {
            'status': 'success',
            'deleted_records': cleanup_results
        }

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def cleanup_mysql_data(creds, retention_policies):
    """Clean up expired MySQL data"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    cleanup_results = {}

    try:
        # Clean up old content
        content_cutoff = datetime.utcnow() - timedelta(days=retention_policies['user_content'])
        cursor.execute(
            "DELETE FROM content WHERE created_at < %s AND status = 'deleted'",
            (content_cutoff,)
        )
        cleanup_results['content'] = cursor.rowcount

        # Keep moderation logs for compliance but clean up old ones
        moderation_cutoff = datetime.utcnow() - timedelta(days=retention_policies['moderation_logs'])
        cursor.execute(
            "DELETE FROM moderation_logs WHERE created_at < %s",
            (moderation_cutoff,)
        )
        cleanup_results['moderation_logs'] = cursor.rowcount

        # Clean up inactive users
        inactive_cutoff = datetime.utcnow() - timedelta(days=retention_policies['inactive_users'])
        cursor.execute(
            "DELETE FROM users WHERE last_active < %s AND status = 'inactive'",
            (inactive_cutoff,)
        )
        cleanup_results['inactive_users'] = cursor.rowcount

        connection.commit()

        return {
            'status': 'success',
            'deleted_records': cleanup_results
        }

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def cleanup_s3_objects(bucket_name, retention_policies):
    """Clean up expired S3 objects"""
    s3_client = boto3.client('s3')
    cleanup_results = {}

    try:
        # Clean up temporary files
        temp_cutoff = datetime.utcnow() - timedelta(days=retention_policies['temp_files'])

        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name, Prefix='temp/')

        objects_to_delete = []
        for page in pages:
            for obj in page.get('Contents', []):
                if obj['LastModified'].replace(tzinfo=None) < temp_cutoff:
                    objects_to_delete.append({'Key': obj['Key']})

        if objects_to_delete:
            # Delete in batches of 1000 (S3 limit)
            deleted_count = 0
            for i in range(0, len(objects_to_delete), 1000):
                batch = objects_to_delete[i:i+1000]
                response = s3_client.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': batch}
                )
                deleted_count += len(response.get('Deleted', []))

            cleanup_results['temp_files'] = deleted_count
        else:
            cleanup_results['temp_files'] = 0

        # Clean up old audit logs (beyond retention period)
        audit_cutoff = datetime.utcnow() - timedelta(days=retention_policies['audit_logs'])

        pages = paginator.paginate(Bucket=bucket_name, Prefix='gdpr-audit/')
        audit_objects_to_delete = []

        for page in pages:
            for obj in page.get('Contents', []):
                if obj['LastModified'].replace(tzinfo=None) < audit_cutoff:
                    audit_objects_to_delete.append({'Key': obj['Key']})

        if audit_objects_to_delete:
            deleted_count = 0
            for i in range(0, len(audit_objects_to_delete), 1000):
                batch = audit_objects_to_delete[i:i+1000]
                response = s3_client.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': batch}
                )
                deleted_count += len(response.get('Deleted', []))

            cleanup_results['old_audit_logs'] = deleted_count
        else:
            cleanup_results['old_audit_logs'] = 0

        return {
            'status': 'success',
            'deleted_objects': cleanup_results
        }

    except Exception as e:
        logger.error(f"S3 cleanup failed: {str(e)}")
        raise e

def audit_retention_compliance(environment, project_name, audit_bucket):
    """Audit current retention compliance status"""
    logger.info("Auditing retention compliance")

    retention_policies = get_retention_policies()
    compliance_report = {}

    # Audit PostgreSQL compliance
    try:
        pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
        pg_compliance = audit_postgresql_compliance(pg_creds, retention_policies)
        compliance_report['postgresql'] = pg_compliance
    except Exception as e:
        logger.error(f"PostgreSQL compliance audit failed: {str(e)}")
        compliance_report['postgresql'] = {'error': str(e)}

    # Audit MySQL compliance
    try:
        mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
        mysql_compliance = audit_mysql_compliance(mysql_creds, retention_policies)
        compliance_report['mysql'] = mysql_compliance
    except Exception as e:
        logger.error(f"MySQL compliance audit failed: {str(e)}")
        compliance_report['mysql'] = {'error': str(e)}

    # Audit S3 compliance
    try:
        s3_compliance = audit_s3_compliance(audit_bucket, retention_policies)
        compliance_report['s3'] = s3_compliance
    except Exception as e:
        logger.error(f"S3 compliance audit failed: {str(e)}")
        compliance_report['s3'] = {'error': str(e)}

    audit_action(audit_bucket, "RETENTION_COMPLIANCE_AUDIT", {
        "compliance_report": compliance_report,
        "retention_policies": retention_policies
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Retention compliance audit completed',
            'compliance_report': compliance_report
        })
    }

def audit_postgresql_compliance(creds, retention_policies):
    """Audit PostgreSQL retention compliance"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    compliance_data = {}

    try:
        # Check for expired call logs
        call_log_cutoff = datetime.utcnow() - timedelta(days=retention_policies['call_logs'])
        cursor.execute(
            "SELECT COUNT(*) FROM calls WHERE created_at < %s",
            (call_log_cutoff,)
        )
        compliance_data['expired_calls'] = cursor.fetchone()[0]

        # Check for expired sessions
        session_cutoff = datetime.utcnow() - timedelta(days=retention_policies['user_sessions'])
        cursor.execute(
            "SELECT COUNT(*) FROM user_sessions WHERE created_at < %s",
            (session_cutoff,)
        )
        compliance_data['expired_sessions'] = cursor.fetchone()[0]

        # Check for inactive users
        inactive_cutoff = datetime.utcnow() - timedelta(days=retention_policies['inactive_users'])
        cursor.execute(
            "SELECT COUNT(*) FROM users WHERE last_active < %s",
            (inactive_cutoff,)
        )
        compliance_data['inactive_users'] = cursor.fetchone()[0]

        return compliance_data

    finally:
        cursor.close()
        connection.close()

def audit_mysql_compliance(creds, retention_policies):
    """Audit MySQL retention compliance"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    compliance_data = {}

    try:
        # Check for expired content
        content_cutoff = datetime.utcnow() - timedelta(days=retention_policies['user_content'])
        cursor.execute(
            "SELECT COUNT(*) FROM content WHERE created_at < %s AND status = 'deleted'",
            (content_cutoff,)
        )
        compliance_data['expired_content'] = cursor.fetchone()[0]

        # Check for old moderation logs
        moderation_cutoff = datetime.utcnow() - timedelta(days=retention_policies['moderation_logs'])
        cursor.execute(
            "SELECT COUNT(*) FROM moderation_logs WHERE created_at < %s",
            (moderation_cutoff,)
        )
        compliance_data['old_moderation_logs'] = cursor.fetchone()[0]

        return compliance_data

    finally:
        cursor.close()
        connection.close()

def audit_s3_compliance(bucket_name, retention_policies):
    """Audit S3 retention compliance"""
    s3_client = boto3.client('s3')
    compliance_data = {}

    try:
        # Check for old temporary files
        temp_cutoff = datetime.utcnow() - timedelta(days=retention_policies['temp_files'])

        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name, Prefix='temp/')

        old_temp_count = 0
        for page in pages:
            for obj in page.get('Contents', []):
                if obj['LastModified'].replace(tzinfo=None) < temp_cutoff:
                    old_temp_count += 1

        compliance_data['old_temp_files'] = old_temp_count

        return compliance_data

    except Exception as e:
        logger.error(f"S3 compliance audit failed: {str(e)}")
        raise e

def anonymize_old_data(environment, project_name, audit_bucket):
    """Anonymize old data instead of deleting (for some use cases)"""
    logger.info("Starting data anonymization")

    anonymization_results = {}

    # Anonymize PostgreSQL data
    try:
        pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
        pg_result = anonymize_postgresql_data(pg_creds)
        anonymization_results['postgresql'] = pg_result
    except Exception as e:
        logger.error(f"PostgreSQL anonymization failed: {str(e)}")
        anonymization_results['postgresql'] = {'error': str(e)}

    # Anonymize MySQL data
    try:
        mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
        mysql_result = anonymize_mysql_data(mysql_creds)
        anonymization_results['mysql'] = mysql_result
    except Exception as e:
        logger.error(f"MySQL anonymization failed: {str(e)}")
        anonymization_results['mysql'] = {'error': str(e)}

    audit_action(audit_bucket, "DATA_ANONYMIZED", {
        "anonymization_results": anonymization_results
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Data anonymization completed',
            'anonymization_results': anonymization_results
        })
    }

def anonymize_postgresql_data(creds):
    """Anonymize old PostgreSQL data"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    anonymized_records = {}

    try:
        # Anonymize old user records (keep for analytics but remove PII)
        anonymization_cutoff = datetime.utcnow() - timedelta(days=1095)  # 3 years

        cursor.execute("""
            UPDATE users
            SET email = CONCAT('anonymized_', id, '@example.com'),
                name = CONCAT('User', id),
                phone = NULL,
                address = NULL
            WHERE last_active < %s AND email NOT LIKE 'anonymized_%'
        """, (anonymization_cutoff,))
        anonymized_records['users'] = cursor.rowcount

        connection.commit()

        return {
            'status': 'success',
            'anonymized_records': anonymized_records
        }

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def anonymize_mysql_data(creds):
    """Anonymize old MySQL data"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    anonymized_records = {}

    try:
        # Anonymize old user content (keep for moderation purposes but remove PII)
        anonymization_cutoff = datetime.utcnow() - timedelta(days=1095)  # 3 years

        cursor.execute("""
            UPDATE content
            SET user_metadata = JSON_OBJECT('anonymized', true, 'original_user', user_id),
                user_id = 'anonymized'
            WHERE created_at < %s AND user_id != 'anonymized'
        """, (anonymization_cutoff,))
        anonymized_records['content'] = cursor.rowcount

        connection.commit()

        return {
            'status': 'success',
            'anonymized_records': anonymized_records
        }

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()