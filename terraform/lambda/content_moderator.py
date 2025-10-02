import json
import boto3
import os
from datetime import datetime
import logging
import uuid
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Content Moderator for Federal Compliance
    Implements 18 USC 2257 compliance and content moderation
    """

    try:
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        moderation_bucket = os.environ['MODERATION_BUCKET']
        compliance_key = os.environ['COMPLIANCE_KMS_KEY']

        # Handle different event sources
        if 'Records' in event:
            # S3 event
            return process_s3_event(event, environment, project_name, moderation_bucket)
        else:
            # Direct invocation
            action = event.get('action', 'moderate_content')

            if action == 'moderate_content':
                return moderate_content_direct(event, environment, project_name, moderation_bucket)
            elif action == 'audit_content':
                return audit_content_compliance(event, environment, project_name, moderation_bucket)
            else:
                raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Content moderation failed: {str(e)}")
        audit_moderation_action(moderation_bucket, "MODERATION_ERROR", {"error": str(e), "event": event})
        raise e

def process_s3_event(event, environment, project_name, moderation_bucket):
    """Process S3 upload events for automatic content moderation"""
    results = []

    for record in event['Records']:
        try:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']

            logger.info(f"Processing uploaded content: {bucket}/{key}")

            result = moderate_uploaded_content(bucket, key, environment, project_name, moderation_bucket)
            results.append(result)

        except Exception as e:
            logger.error(f"Failed to process S3 record: {str(e)}")
            results.append({'status': 'error', 'error': str(e)})

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(results)} content items',
            'results': results
        })
    }

def moderate_uploaded_content(bucket, key, environment, project_name, moderation_bucket):
    """Moderate content uploaded to S3"""
    s3_client = boto3.client('s3')
    rekognition = boto3.client('rekognition')

    try:
        # Determine content type
        response = s3_client.head_object(Bucket=bucket, Key=key)
        content_type = response.get('ContentType', '')
        content_length = response.get('ContentLength', 0)

        moderation_result = {
            'bucket': bucket,
            'key': key,
            'content_type': content_type,
            'content_length': content_length,
            'timestamp': datetime.utcnow().isoformat(),
            'moderation_id': str(uuid.uuid4())
        }

        # Skip if file is too large (>15MB for Rekognition)
        if content_length > 15 * 1024 * 1024:
            moderation_result['status'] = 'SKIPPED'
            moderation_result['reason'] = 'File too large for analysis'
            return moderation_result

        # Moderate based on content type
        if content_type.startswith('image/'):
            image_result = moderate_image_content(bucket, key, rekognition)
            moderation_result.update(image_result)
        elif content_type.startswith('video/'):
            video_result = moderate_video_content(bucket, key, rekognition)
            moderation_result.update(video_result)
        else:
            moderation_result['status'] = 'SKIPPED'
            moderation_result['reason'] = 'Unsupported content type'

        # Store moderation result
        store_moderation_result(moderation_bucket, moderation_result)

        # Take action based on moderation result
        if moderation_result.get('status') == 'FLAGGED':
            handle_flagged_content(bucket, key, moderation_result, environment, project_name)

        # Update database with moderation status
        update_content_moderation_status(moderation_result, environment, project_name)

        audit_moderation_action(moderation_bucket, "CONTENT_MODERATED", moderation_result)

        return moderation_result

    except Exception as e:
        logger.error(f"Content moderation failed for {bucket}/{key}: {str(e)}")
        raise e

def moderate_image_content(bucket, key, rekognition):
    """Moderate image content using AWS Rekognition"""
    try:
        # Detect moderation labels
        moderation_response = rekognition.detect_moderation_labels(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            },
            MinConfidence=50.0
        )

        # Detect faces for age estimation
        faces_response = rekognition.detect_faces(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            },
            Attributes=['ALL']
        )

        # Detect text in image
        text_response = rekognition.detect_text(
            Image={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )

        # Analyze results
        moderation_labels = moderation_response.get('ModerationLabels', [])
        faces = faces_response.get('FaceDetails', [])
        text_detections = text_response.get('TextDetections', [])

        result = {
            'moderation_labels': moderation_labels,
            'faces_detected': len(faces),
            'text_detections': [t['DetectedText'] for t in text_detections if t.get('Type') == 'LINE'],
            'analysis_type': 'image'
        }

        # Determine if content should be flagged
        result['status'] = determine_content_status(moderation_labels, faces, text_detections)
        result['confidence_scores'] = [label['Confidence'] for label in moderation_labels]

        return result

    except Exception as e:
        logger.error(f"Image moderation failed: {str(e)}")
        return {'status': 'ERROR', 'error': str(e), 'analysis_type': 'image'}

def moderate_video_content(bucket, key, rekognition):
    """Moderate video content using AWS Rekognition Video"""
    try:
        # Start content moderation job
        job_response = rekognition.start_content_moderation(
            Video={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            },
            MinConfidence=50.0
        )

        job_id = job_response['JobId']

        # Note: In production, you would poll for job completion
        # For now, we'll mark as pending and process asynchronously
        result = {
            'status': 'PENDING',
            'job_id': job_id,
            'analysis_type': 'video',
            'message': 'Video analysis started, results will be available asynchronously'
        }

        return result

    except Exception as e:
        logger.error(f"Video moderation failed: {str(e)}")
        return {'status': 'ERROR', 'error': str(e), 'analysis_type': 'video'}

def determine_content_status(moderation_labels, faces, text_detections):
    """Determine if content should be flagged based on analysis"""

    # High-risk categories that require immediate flagging
    high_risk_categories = [
        'Explicit Nudity',
        'Suggestive',
        'Violence',
        'Weapons',
        'Drugs',
        'Tobacco',
        'Alcohol',
        'Gambling',
        'Hate Symbols'
    ]

    # Check moderation labels
    for label in moderation_labels:
        if label['Confidence'] > 80:
            if any(risk_cat in label['Name'] for risk_cat in high_risk_categories):
                return 'FLAGGED'
            elif label['Confidence'] > 90:
                return 'FLAGGED'

    # Check for potentially underage faces
    for face in faces:
        age_range = face.get('AgeRange', {})
        if age_range.get('High', 100) < 18:
            return 'FLAGGED'

    # Check for problematic text
    problematic_terms = [
        'underage', 'minor', 'child', 'teen', 'young',
        'school', 'barely legal', 'just turned 18'
    ]

    for detection in text_detections:
        text_lower = detection['DetectedText'].lower()
        if any(term in text_lower for term in problematic_terms):
            return 'REVIEW'

    # Default to approved if no issues found
    return 'APPROVED'

def handle_flagged_content(bucket, key, moderation_result, environment, project_name):
    """Handle content that has been flagged for review"""
    s3_client = boto3.client('s3')

    try:
        # Move flagged content to quarantine
        quarantine_key = f"quarantine/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"

        s3_client.copy_object(
            Bucket=bucket,
            CopySource={'Bucket': bucket, 'Key': key},
            Key=quarantine_key,
            TaggingDirective='REPLACE',
            Tagging='status=flagged&reason=content_moderation'
        )

        # Remove from public access
        s3_client.put_object_acl(
            Bucket=bucket,
            Key=key,
            ACL='private'
        )

        # Add metadata to indicate flagged status
        s3_client.copy_object(
            Bucket=bucket,
            CopySource={'Bucket': bucket, 'Key': key},
            Key=key,
            MetadataDirective='REPLACE',
            Metadata={
                'moderation-status': 'flagged',
                'moderation-id': moderation_result['moderation_id'],
                'flagged-timestamp': datetime.utcnow().isoformat()
            }
        )

        logger.info(f"Flagged content moved to quarantine: {bucket}/{quarantine_key}")

    except Exception as e:
        logger.error(f"Failed to handle flagged content: {str(e)}")
        raise e

def store_moderation_result(bucket, result):
    """Store moderation result in S3"""
    s3_client = boto3.client('s3')

    try:
        timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
        key = f"moderation-results/{timestamp}/{result['moderation_id']}.json"

        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(result, indent=2, default=str),
            ContentType='application/json'
        )

    except Exception as e:
        logger.error(f"Failed to store moderation result: {str(e)}")

def update_content_moderation_status(result, environment, project_name):
    """Update database with moderation status"""
    dynamodb = boto3.resource('dynamodb')

    try:
        table_name = f"{project_name}-compliance-records-{environment}"
        table = dynamodb.Table(table_name)

        record = {
            'record_id': result['moderation_id'],
            'record_type': 'CONTENT_MODERATION',
            'user_id': 'system',  # Would be actual user ID in production
            'timestamp': result['timestamp'],
            'content_location': f"{result['bucket']}/{result['key']}",
            'moderation_status': result['status'],
            'moderation_details': {
                'content_type': result['content_type'],
                'analysis_type': result.get('analysis_type'),
                'confidence_scores': result.get('confidence_scores', []),
                'moderation_labels': result.get('moderation_labels', [])
            }
        }

        table.put_item(Item=record)

    except Exception as e:
        logger.error(f"Failed to update moderation status in database: {str(e)}")

def moderate_content_direct(event, environment, project_name, moderation_bucket):
    """Handle direct content moderation requests"""
    content_url = event.get('content_url')
    content_id = event.get('content_id')

    if not content_url:
        raise ValueError("content_url is required for direct moderation")

    # Parse S3 URL
    if content_url.startswith('s3://'):
        parts = content_url.replace('s3://', '').split('/', 1)
        bucket = parts[0]
        key = parts[1] if len(parts) > 1 else ''
    else:
        raise ValueError("Only S3 URLs are supported")

    result = moderate_uploaded_content(bucket, key, environment, project_name, moderation_bucket)

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Content moderation completed',
            'content_id': content_id,
            'moderation_result': result
        })
    }

def audit_content_compliance(event, environment, project_name, moderation_bucket):
    """Audit content compliance across the platform"""
    logger.info("Starting content compliance audit")

    dynamodb = boto3.resource('dynamodb')
    s3_client = boto3.client('s3')

    try:
        table_name = f"{project_name}-compliance-records-{environment}"
        table = dynamodb.Table(table_name)

        # Get moderation statistics
        now = datetime.utcnow()
        one_week_ago = (now - timedelta(days=7)).isoformat()

        # Query recent moderation records
        response = table.query(
            IndexName='type-timestamp-index',
            KeyConditionExpression='record_type = :type AND #ts >= :timestamp',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':type': 'CONTENT_MODERATION',
                ':timestamp': one_week_ago
            }
        )

        records = response.get('Items', [])

        # Calculate statistics
        total_content = len(records)
        flagged_content = len([r for r in records if r.get('moderation_status') == 'FLAGGED'])
        approved_content = len([r for r in records if r.get('moderation_status') == 'APPROVED'])
        pending_content = len([r for r in records if r.get('moderation_status') == 'PENDING'])

        audit_report = {
            'audit_timestamp': now.isoformat(),
            'audit_period': '7_days',
            'statistics': {
                'total_content_moderated': total_content,
                'flagged_content': flagged_content,
                'approved_content': approved_content,
                'pending_content': pending_content,
                'flagged_percentage': (flagged_content / total_content * 100) if total_content > 0 else 0
            },
            'compliance_status': 'COMPLIANT' if flagged_percentage < 5 else 'REVIEW_REQUIRED'
        }

        # Store audit report
        audit_key = f"compliance-audits/{now.strftime('%Y/%m/%d')}/content_audit_{now.strftime('%H%M%S')}.json"
        s3_client.put_object(
            Bucket=moderation_bucket,
            Key=audit_key,
            Body=json.dumps(audit_report, indent=2),
            ContentType='application/json'
        )

        audit_moderation_action(moderation_bucket, "COMPLIANCE_AUDIT", audit_report)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content compliance audit completed',
                'audit_report': audit_report
            })
        }

    except Exception as e:
        logger.error(f"Content compliance audit failed: {str(e)}")
        raise e

def audit_moderation_action(bucket_name, action_type, details):
    """Log moderation audit action to S3"""
    s3_client = boto3.client('s3')
    timestamp = datetime.utcnow().isoformat()

    audit_record = {
        "timestamp": timestamp,
        "action_type": action_type,
        "details": details,
        "audit_id": str(uuid.uuid4())
    }

    key = f"moderation-audit/{datetime.utcnow().strftime('%Y/%m/%d')}/{timestamp}_{action_type}.json"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(audit_record, indent=2, default=str),
            ContentType='application/json'
        )
    except Exception as e:
        logger.error(f"Failed to write moderation audit record: {str(e)}")

# Helper function for time calculations
from datetime import timedelta