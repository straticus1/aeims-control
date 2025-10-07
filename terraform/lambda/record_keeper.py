import json
import boto3
import logging
from datetime import datetime
import hashlib

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Federal Compliance Record Keeper Lambda Function
    Maintains detailed records for federal compliance requirements
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"

    # Initialize AWS clients
    dynamodb = boto3.resource('dynamodb')
    s3 = boto3.client('s3')

    try:
        logger.info(f"Processing compliance record for {project_name} in {environment}")

        # Parse the incoming event
        record_type = event.get('record_type', 'general')
        user_id = event.get('user_id', 'unknown')
        session_id = event.get('session_id', 'unknown')
        action = event.get('action', 'unknown')
        details = event.get('details', {})

        # Generate record ID
        timestamp = datetime.utcnow()
        record_id = hashlib.sha256(
            f"{user_id}-{session_id}-{timestamp.isoformat()}".encode()
        ).hexdigest()[:16]

        # Store in DynamoDB
        table_name = f"{project_name}-compliance-records-{environment}"
        table = dynamodb.Table(table_name)

        record_item = {
            'record_id': record_id,
            'timestamp': timestamp.isoformat(),
            'record_type': record_type,
            'user_id': user_id,
            'session_id': session_id,
            'action': action,
            'details': json.dumps(details),
            'environment': environment,
            'project': project_name,
            'compliance_flags': {
                'federal_requirement': True,
                'age_verification': details.get('age_verified', False),
                'consent_recorded': details.get('consent_given', False),
                'geographic_restriction': details.get('geo_compliant', True)
            }
        }

        # Add 2257 compliance fields if applicable
        if record_type in ['content_access', 'performer_verification']:
            record_item['section_2257'] = {
                'record_required': True,
                'performer_age_verified': details.get('performer_age_verified', False),
                'documentation_type': details.get('id_type', 'unknown'),
                'custodian_record': True
            }

        table.put_item(Item=record_item)

        # Also store a backup copy in S3 for long-term retention
        bucket_name = f"{project_name}-compliance-records-{environment}"
        s3_key = f"records/{timestamp.strftime('%Y/%m/%d')}/{record_id}.json"

        s3.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(record_item, indent=2),
            ServerSideEncryption='aws:kms',
            Metadata={
                'record-type': record_type,
                'user-id': user_id,
                'compliance-level': 'federal'
            }
        )

        logger.info(f"Compliance record {record_id} stored successfully")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Compliance record stored successfully',
                'record_id': record_id,
                'timestamp': timestamp.isoformat(),
                'record_type': record_type,
                'environment': environment,
                'project': project_name
            })
        }

    except Exception as e:
        logger.error(f"Failed to store compliance record: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Failed to store compliance record',
                'error': str(e),
                'environment': environment,
                'project': project_name
            })
        }