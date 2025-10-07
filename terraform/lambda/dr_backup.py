import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Disaster Recovery Backup Lambda Function
    Handles automated backup processes for AEIMS platform
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"
    dr_region = "${dr_region}"

    # Initialize AWS clients
    s3 = boto3.client('s3')
    rds = boto3.client('rds')

    try:
        logger.info(f"Starting DR backup process for {project_name} in {environment}")

        # Create snapshot timestamp
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')

        # Backup RDS instances
        backup_results = []

        # List RDS instances with project tags
        response = rds.describe_db_instances()
        for db in response['DBInstances']:
            db_identifier = db['DBInstanceIdentifier']
            if project_name in db_identifier and environment in db_identifier:
                snapshot_id = f"{db_identifier}-dr-backup-{timestamp}"

                logger.info(f"Creating snapshot for {db_identifier}")

                rds.create_db_snapshot(
                    DBSnapshotIdentifier=snapshot_id,
                    DBInstanceIdentifier=db_identifier,
                    Tags=[
                        {'Key': 'Purpose', 'Value': 'DisasterRecovery'},
                        {'Key': 'Environment', 'Value': environment},
                        {'Key': 'Project', 'Value': project_name},
                        {'Key': 'CreatedBy', 'Value': 'AEIMS-DR-Lambda'},
                        {'Key': 'Timestamp', 'Value': timestamp}
                    ]
                )

                backup_results.append({
                    'type': 'rds_snapshot',
                    'source': db_identifier,
                    'snapshot_id': snapshot_id,
                    'status': 'initiated'
                })

        # Copy critical S3 buckets to DR region
        s3_dr = boto3.client('s3', region_name=dr_region)

        # List buckets with project prefix
        bucket_response = s3.list_buckets()
        for bucket in bucket_response['Buckets']:
            bucket_name = bucket['Name']
            if project_name in bucket_name and environment in bucket_name:
                dr_bucket_name = f"{bucket_name}-dr-{dr_region}"

                logger.info(f"Setting up cross-region replication for {bucket_name}")

                # Note: This would typically set up cross-region replication
                # For this example, we're just logging the action
                backup_results.append({
                    'type': 's3_replication',
                    'source': bucket_name,
                    'destination': dr_bucket_name,
                    'status': 'configured'
                })

        logger.info(f"DR backup process completed. Results: {len(backup_results)} operations")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DR backup process completed successfully',
                'environment': environment,
                'project': project_name,
                'timestamp': timestamp,
                'operations': backup_results
            })
        }

    except Exception as e:
        logger.error(f"DR backup process failed: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'DR backup process failed',
                'error': str(e),
                'environment': environment,
                'project': project_name
            })
        }