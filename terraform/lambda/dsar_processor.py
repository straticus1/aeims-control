import json
import boto3
import psycopg2
import pymysql
import os
from datetime import datetime, timedelta
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Data Subject Access Request (DSAR) processor for GDPR compliance
    Handles user data requests, deletions, and corrections
    """

    try:
        action = event.get('action', 'process_pending')
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        audit_bucket = os.environ['AUDIT_BUCKET']

        logger.info(f"Processing DSAR action: {action}")

        if action == 'process_pending':
            return process_pending_requests(environment, project_name, audit_bucket)
        elif action == 'extract_data':
            return extract_user_data(event, environment, project_name, audit_bucket)
        elif action == 'delete_data':
            return delete_user_data(event, environment, project_name, audit_bucket)
        elif action == 'rectify_data':
            return rectify_user_data(event, environment, project_name, audit_bucket)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"DSAR processing failed: {str(e)}")
        audit_action(audit_bucket, "DSAR_ERROR", {"error": str(e), "event": event})
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
        "details": details,
        "request_id": str(uuid.uuid4())
    }

    key = f"gdpr-audit/{datetime.utcnow().strftime('%Y/%m/%d')}/{timestamp}_{action_type}.json"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(audit_record, indent=2),
            ContentType='application/json'
        )
    except Exception as e:
        logger.error(f"Failed to write audit record: {str(e)}")

def process_pending_requests(environment, project_name, audit_bucket):
    """Process pending DSAR requests"""
    logger.info("Processing pending DSAR requests")

    # Check DynamoDB for pending requests
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-consent-management-{environment}"

    try:
        table = dynamodb.Table(table_name)

        # Scan for pending DSAR requests
        response = table.scan(
            FilterExpression="consent_type = :ct AND attribute_exists(dsar_status) AND dsar_status = :status",
            ExpressionAttributeValues={
                ':ct': 'DSAR_REQUEST',
                ':status': 'PENDING'
            }
        )

        processed_count = 0
        for item in response.get('Items', []):
            try:
                request_id = item['user_id']
                request_type = item.get('request_details', {}).get('type', 'EXPORT')

                if request_type == 'EXPORT':
                    result = extract_user_data_by_id(request_id, environment, project_name, audit_bucket)
                elif request_type == 'DELETE':
                    result = delete_user_data_by_id(request_id, environment, project_name, audit_bucket)
                elif request_type == 'RECTIFY':
                    result = rectify_user_data_by_id(request_id, item.get('request_details', {}), environment, project_name, audit_bucket)

                # Update request status
                table.update_item(
                    Key={
                        'user_id': request_id,
                        'consent_type': 'DSAR_REQUEST'
                    },
                    UpdateExpression="SET dsar_status = :status, processed_at = :timestamp",
                    ExpressionAttributeValues={
                        ':status': 'COMPLETED',
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )

                processed_count += 1

            except Exception as e:
                logger.error(f"Failed to process DSAR request {item.get('user_id')}: {str(e)}")

                # Mark as failed
                table.update_item(
                    Key={
                        'user_id': item['user_id'],
                        'consent_type': 'DSAR_REQUEST'
                    },
                    UpdateExpression="SET dsar_status = :status, error_message = :error, processed_at = :timestamp",
                    ExpressionAttributeValues={
                        ':status': 'FAILED',
                        ':error': str(e),
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )

        audit_action(audit_bucket, "DSAR_BATCH_PROCESSED", {
            "processed_count": processed_count,
            "total_pending": len(response.get('Items', []))
        })

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {processed_count} DSAR requests',
                'processed_count': processed_count
            })
        }

    except Exception as e:
        logger.error(f"Failed to process pending requests: {str(e)}")
        raise e

def extract_user_data(event, environment, project_name, audit_bucket):
    """Extract all user data for GDPR compliance"""
    user_id = event.get('user_id')
    if not user_id:
        raise ValueError("user_id is required for data extraction")

    return extract_user_data_by_id(user_id, environment, project_name, audit_bucket)

def extract_user_data_by_id(user_id, environment, project_name, audit_bucket):
    """Extract user data by ID"""
    logger.info(f"Extracting data for user: {user_id}")

    user_data = {
        'user_id': user_id,
        'extraction_timestamp': datetime.utcnow().isoformat(),
        'data_sources': {}
    }

    # Extract from PostgreSQL (AEIMS Core)
    try:
        pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
        pg_data = extract_postgresql_data(user_id, pg_creds)
        user_data['data_sources']['aeims_core'] = pg_data
    except Exception as e:
        logger.error(f"PostgreSQL extraction failed: {str(e)}")
        user_data['data_sources']['aeims_core'] = {'error': str(e)}

    # Extract from MySQL (AEIMS App)
    try:
        mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
        mysql_data = extract_mysql_data(user_id, mysql_creds)
        user_data['data_sources']['aeims_app'] = mysql_data
    except Exception as e:
        logger.error(f"MySQL extraction failed: {str(e)}")
        user_data['data_sources']['aeims_app'] = {'error': str(e)}

    # Store extracted data in S3
    s3_client = boto3.client('s3')
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    key = f"dsar-exports/{user_id}/data_export_{timestamp}.json"

    try:
        s3_client.put_object(
            Bucket=audit_bucket,
            Key=key,
            Body=json.dumps(user_data, indent=2, default=str),
            ContentType='application/json'
        )

        audit_action(audit_bucket, "DATA_EXTRACTED", {
            "user_id": user_id,
            "export_location": f"s3://{audit_bucket}/{key}",
            "data_sources": list(user_data['data_sources'].keys())
        })

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data extraction completed',
                'user_id': user_id,
                'export_location': f"s3://{audit_bucket}/{key}"
            })
        }

    except Exception as e:
        logger.error(f"Failed to store extracted data: {str(e)}")
        raise e

def extract_postgresql_data(user_id, creds):
    """Extract user data from PostgreSQL"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    data = {}

    try:
        # User profile data
        cursor.execute("SELECT * FROM users WHERE id = %s OR email = %s", (user_id, user_id))
        user_record = cursor.fetchone()
        if user_record:
            columns = [desc[0] for desc in cursor.description]
            data['user_profile'] = dict(zip(columns, user_record))

        # Call history
        cursor.execute("SELECT * FROM calls WHERE user_id = %s OR participant_id = %s", (user_id, user_id))
        calls = cursor.fetchall()
        if calls:
            columns = [desc[0] for desc in cursor.description]
            data['call_history'] = [dict(zip(columns, call)) for call in calls]

        # Conference participation
        cursor.execute("SELECT * FROM conferences WHERE created_by = %s", (user_id,))
        conferences = cursor.fetchall()
        if conferences:
            columns = [desc[0] for desc in cursor.description]
            data['conferences'] = [dict(zip(columns, conf)) for conf in conferences]

        # Session data
        cursor.execute("SELECT * FROM user_sessions WHERE user_id = %s", (user_id,))
        sessions = cursor.fetchall()
        if sessions:
            columns = [desc[0] for desc in cursor.description]
            data['sessions'] = [dict(zip(columns, session)) for session in sessions]

        return data

    finally:
        cursor.close()
        connection.close()

def extract_mysql_data(user_id, creds):
    """Extract user data from MySQL"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    data = {}

    try:
        # User content
        cursor.execute("SELECT * FROM users WHERE id = %s OR email = %s", (user_id, user_id))
        user_record = cursor.fetchone()
        if user_record:
            columns = [desc[0] for desc in cursor.description]
            data['user_profile'] = dict(zip(columns, user_record))

        # Content created by user
        cursor.execute("SELECT * FROM content WHERE user_id = %s", (user_id,))
        content = cursor.fetchall()
        if content:
            columns = [desc[0] for desc in cursor.description]
            data['user_content'] = [dict(zip(columns, item)) for item in content]

        # Moderation logs
        cursor.execute("SELECT * FROM moderation_logs WHERE user_id = %s", (user_id,))
        mod_logs = cursor.fetchall()
        if mod_logs:
            columns = [desc[0] for desc in cursor.description]
            data['moderation_history'] = [dict(zip(columns, log)) for log in mod_logs]

        return data

    finally:
        cursor.close()
        connection.close()

def delete_user_data(event, environment, project_name, audit_bucket):
    """Delete user data (right to erasure)"""
    user_id = event.get('user_id')
    if not user_id:
        raise ValueError("user_id is required for data deletion")

    return delete_user_data_by_id(user_id, environment, project_name, audit_bucket)

def delete_user_data_by_id(user_id, environment, project_name, audit_bucket):
    """Delete user data by ID"""
    logger.info(f"Deleting data for user: {user_id}")

    # First, extract data for audit purposes
    extraction_result = extract_user_data_by_id(user_id, environment, project_name, audit_bucket)

    deletion_results = {}

    # Delete from PostgreSQL
    try:
        pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
        pg_result = delete_postgresql_data(user_id, pg_creds)
        deletion_results['postgresql'] = pg_result
    except Exception as e:
        logger.error(f"PostgreSQL deletion failed: {str(e)}")
        deletion_results['postgresql'] = {'error': str(e)}

    # Delete from MySQL
    try:
        mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
        mysql_result = delete_mysql_data(user_id, mysql_creds)
        deletion_results['mysql'] = mysql_result
    except Exception as e:
        logger.error(f"MySQL deletion failed: {str(e)}")
        deletion_results['mysql'] = {'error': str(e)}

    audit_action(audit_bucket, "DATA_DELETED", {
        "user_id": user_id,
        "deletion_results": deletion_results,
        "pre_deletion_backup": extraction_result.get('body', {})
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Data deletion completed',
            'user_id': user_id,
            'deletion_results': deletion_results
        })
    }

def delete_postgresql_data(user_id, creds):
    """Delete user data from PostgreSQL"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    deleted_records = {}

    try:
        # Delete in order of dependencies
        tables_to_clean = [
            ('user_sessions', 'user_id'),
            ('calls', 'user_id'),
            ('calls', 'participant_id'),
            ('conferences', 'created_by'),
            ('users', 'id'),
            ('users', 'email')
        ]

        for table, column in tables_to_clean:
            cursor.execute(f"DELETE FROM {table} WHERE {column} = %s", (user_id,))
            deleted_count = cursor.rowcount
            deleted_records[f"{table}_{column}"] = deleted_count

        connection.commit()
        return {'deleted_records': deleted_records, 'status': 'success'}

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def delete_mysql_data(user_id, creds):
    """Delete user data from MySQL"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    deleted_records = {}

    try:
        # Delete in order of dependencies
        tables_to_clean = [
            ('moderation_logs', 'user_id'),
            ('content', 'user_id'),
            ('users', 'id'),
            ('users', 'email')
        ]

        for table, column in tables_to_clean:
            cursor.execute(f"DELETE FROM {table} WHERE {column} = %s", (user_id,))
            deleted_count = cursor.rowcount
            deleted_records[f"{table}_{column}"] = deleted_count

        connection.commit()
        return {'deleted_records': deleted_records, 'status': 'success'}

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def rectify_user_data(event, environment, project_name, audit_bucket):
    """Rectify user data (right to rectification)"""
    user_id = event.get('user_id')
    corrections = event.get('corrections', {})

    if not user_id:
        raise ValueError("user_id is required for data rectification")
    if not corrections:
        raise ValueError("corrections are required for data rectification")

    return rectify_user_data_by_id(user_id, corrections, environment, project_name, audit_bucket)

def rectify_user_data_by_id(user_id, corrections, environment, project_name, audit_bucket):
    """Rectify user data by ID"""
    logger.info(f"Rectifying data for user: {user_id}")

    rectification_results = {}

    # Apply corrections to databases
    for database, updates in corrections.items():
        try:
            if database == 'postgresql':
                pg_creds = get_database_credentials(f"{project_name}/{environment}/aeims-core/database")
                result = apply_postgresql_corrections(user_id, updates, pg_creds)
                rectification_results['postgresql'] = result
            elif database == 'mysql':
                mysql_creds = get_database_credentials(f"{project_name}/{environment}/aeims-app/database")
                result = apply_mysql_corrections(user_id, updates, mysql_creds)
                rectification_results['mysql'] = result
        except Exception as e:
            logger.error(f"{database} rectification failed: {str(e)}")
            rectification_results[database] = {'error': str(e)}

    audit_action(audit_bucket, "DATA_RECTIFIED", {
        "user_id": user_id,
        "corrections_applied": corrections,
        "rectification_results": rectification_results
    })

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Data rectification completed',
            'user_id': user_id,
            'rectification_results': rectification_results
        })
    }

def apply_postgresql_corrections(user_id, updates, creds):
    """Apply corrections to PostgreSQL data"""
    connection = psycopg2.connect(
        host=creds['host'],
        database=creds['dbname'],
        user=creds['username'],
        password=creds['password']
    )

    cursor = connection.cursor()
    updated_records = {}

    try:
        for table, fields in updates.items():
            if not fields:
                continue

            # Build UPDATE query
            set_clause = ", ".join([f"{field} = %s" for field in fields.keys()])
            query = f"UPDATE {table} SET {set_clause} WHERE id = %s OR user_id = %s"

            values = list(fields.values()) + [user_id, user_id]
            cursor.execute(query, values)
            updated_records[table] = cursor.rowcount

        connection.commit()
        return {'updated_records': updated_records, 'status': 'success'}

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()

def apply_mysql_corrections(user_id, updates, creds):
    """Apply corrections to MySQL data"""
    connection = pymysql.connect(
        host=creds['host'],
        user=creds['username'],
        password=creds['password'],
        database=creds['dbname'],
        charset='utf8mb4'
    )

    cursor = connection.cursor()
    updated_records = {}

    try:
        for table, fields in updates.items():
            if not fields:
                continue

            # Build UPDATE query
            set_clause = ", ".join([f"{field} = %s" for field in fields.keys()])
            query = f"UPDATE {table} SET {set_clause} WHERE id = %s OR user_id = %s"

            values = list(fields.values()) + [user_id, user_id]
            cursor.execute(query, values)
            updated_records[table] = cursor.rowcount

        connection.commit()
        return {'updated_records': updated_records, 'status': 'success'}

    except Exception as e:
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()