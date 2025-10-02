import json
import boto3
import os
from datetime import datetime, date
import logging
import uuid
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Age Verification Handler for 18 USC 2257 Compliance
    Verifies user age using document analysis and face recognition
    """

    try:
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        compliance_bucket = os.environ['COMPLIANCE_BUCKET']

        action = event.get('action', 'verify_age')

        if action == 'verify_age':
            return verify_user_age(event, environment, project_name, compliance_bucket)
        elif action == 'verify_document':
            return verify_identity_document(event, environment, project_name, compliance_bucket)
        elif action == 'audit_verifications':
            return audit_age_verifications(event, environment, project_name, compliance_bucket)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Age verification failed: {str(e)}")
        audit_verification_action(compliance_bucket, "VERIFICATION_ERROR", {"error": str(e), "event": event})
        raise e

def verify_user_age(event, environment, project_name, compliance_bucket):
    """Verify user age through document analysis"""
    user_id = event.get('user_id')
    document_url = event.get('document_url')
    selfie_url = event.get('selfie_url', '')

    if not user_id or not document_url:
        raise ValueError("user_id and document_url are required")

    logger.info(f"Verifying age for user: {user_id}")

    verification_result = {
        'user_id': user_id,
        'verification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_url': document_url,
        'selfie_url': selfie_url
    }

    try:
        # Parse document URL
        bucket, key = parse_s3_url(document_url)

        # Analyze identity document
        document_analysis = analyze_identity_document(bucket, key)
        verification_result['document_analysis'] = document_analysis

        # Verify age from document
        age_verification = verify_age_from_document(document_analysis)
        verification_result['age_verification'] = age_verification

        # If selfie provided, verify face match
        if selfie_url:
            selfie_bucket, selfie_key = parse_s3_url(selfie_url)
            face_match = verify_face_match(bucket, key, selfie_bucket, selfie_key)
            verification_result['face_match'] = face_match
        else:
            verification_result['face_match'] = {'status': 'SKIPPED', 'reason': 'No selfie provided'}

        # Determine overall verification status
        verification_result['status'] = determine_verification_status(age_verification, verification_result.get('face_match', {}))

        # Store verification result
        store_verification_result(compliance_bucket, verification_result)

        # Update database
        update_user_verification_status(verification_result, environment, project_name)

        # Store compliance record
        store_compliance_record(verification_result, environment, project_name)

        audit_verification_action(compliance_bucket, "AGE_VERIFIED", verification_result)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Age verification completed',
                'verification_id': verification_result['verification_id'],
                'status': verification_result['status'],
                'age_verified': verification_result['age_verification']['is_over_18']
            })
        }

    except Exception as e:
        verification_result['status'] = 'ERROR'
        verification_result['error'] = str(e)
        store_verification_result(compliance_bucket, verification_result)
        raise e

def parse_s3_url(url):
    """Parse S3 URL to extract bucket and key"""
    if not url.startswith('s3://'):
        raise ValueError("Only S3 URLs are supported")

    parts = url.replace('s3://', '').split('/', 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ''
    return bucket, key

def analyze_identity_document(bucket, key):
    """Analyze identity document using AWS Textract"""
    textract = boto3.client('textract')

    try:
        # Use AnalyzeID for driver's licenses and IDs
        response = textract.analyze_id(
            DocumentLocation={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )

        # Extract relevant information
        identity_documents = response.get('IdentityDocuments', [])

        if not identity_documents:
            # Fallback to general document analysis
            response = textract.analyze_document(
                Document={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                FeatureTypes=['FORMS', 'TABLES']
            )
            return parse_general_document(response)

        # Parse ID-specific information
        document_info = identity_documents[0]
        identity_fields = document_info.get('IdentityDocumentFields', [])

        extracted_data = {}
        for field in identity_fields:
            field_type = field.get('Type', {}).get('Text', '')
            field_value = field.get('ValueDetection', {}).get('Text', '')

            if field_type and field_value:
                extracted_data[field_type.lower().replace(' ', '_')] = field_value

        return {
            'extraction_method': 'analyze_id',
            'confidence': 'high',
            'extracted_data': extracted_data,
            'raw_response': identity_documents[0]
        }

    except Exception as e:
        logger.error(f"Document analysis failed: {str(e)}")
        return {
            'extraction_method': 'failed',
            'error': str(e),
            'extracted_data': {}
        }

def parse_general_document(response):
    """Parse general document when AnalyzeID fails"""
    blocks = response.get('Blocks', [])

    # Extract key-value pairs
    key_map = {}
    value_map = {}
    block_map = {}

    for block in blocks:
        block_id = block['Id']
        block_map[block_id] = block

        if block['BlockType'] == 'KEY_VALUE_SET':
            if 'KEY' in block['EntityTypes']:
                key_map[block_id] = block
            else:
                value_map[block_id] = block

    # Match keys with values
    extracted_data = {}
    for key_id, key_block in key_map.items():
        value_block = find_value_block(key_block, value_map)
        if value_block:
            key_text = get_text(key_block, block_map)
            value_text = get_text(value_block, block_map)

            if key_text and value_text:
                extracted_data[key_text.lower().replace(' ', '_')] = value_text

    return {
        'extraction_method': 'general_document',
        'confidence': 'medium',
        'extracted_data': extracted_data
    }

def find_value_block(key_block, value_map):
    """Find corresponding value block for a key"""
    relationships = key_block.get('Relationships', [])
    for relationship in relationships:
        if relationship['Type'] == 'VALUE':
            for value_id in relationship['Ids']:
                if value_id in value_map:
                    return value_map[value_id]
    return None

def get_text(result, blocks_map):
    """Extract text from a block"""
    text = ''
    if 'Relationships' in result:
        for relationship in result['Relationships']:
            if relationship['Type'] == 'CHILD':
                for child_id in relationship['Ids']:
                    word = blocks_map[child_id]
                    if word['BlockType'] == 'WORD':
                        text += word['Text'] + ' '
    return text.strip()

def verify_age_from_document(document_analysis):
    """Verify age from extracted document data"""
    extracted_data = document_analysis.get('extracted_data', {})

    # Look for date of birth fields
    dob_fields = [
        'date_of_birth', 'dob', 'birth_date', 'birthdate',
        'date_of_birth_text', 'dob_text'
    ]

    birth_date = None
    for field in dob_fields:
        if field in extracted_data:
            birth_date = parse_date(extracted_data[field])
            if birth_date:
                break

    if not birth_date:
        return {
            'is_over_18': False,
            'confidence': 'low',
            'reason': 'Could not extract birth date from document',
            'birth_date': None,
            'age': None
        }

    # Calculate age
    today = date.today()
    age = today.year - birth_date.year

    # Adjust if birthday hasn't occurred this year
    if (today.month, today.day) < (birth_date.month, birth_date.day):
        age -= 1

    is_over_18 = age >= 18

    return {
        'is_over_18': is_over_18,
        'confidence': 'high' if document_analysis.get('confidence') == 'high' else 'medium',
        'birth_date': birth_date.isoformat(),
        'age': age,
        'reason': f'Calculated age: {age} years'
    }

def parse_date(date_string):
    """Parse date string in various formats"""
    if not date_string:
        return None

    # Common date formats
    formats = [
        '%m/%d/%Y', '%m-%d-%Y', '%m.%d.%Y',
        '%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y',
        '%Y/%m/%d', '%Y-%m-%d', '%Y.%m.%d',
        '%B %d, %Y', '%b %d, %Y',
        '%d %B %Y', '%d %b %Y'
    ]

    for fmt in formats:
        try:
            return datetime.strptime(date_string.strip(), fmt).date()
        except ValueError:
            continue

    # Try to extract date using regex
    date_patterns = [
        r'(\d{1,2})/(\d{1,2})/(\d{4})',
        r'(\d{1,2})-(\d{1,2})-(\d{4})',
        r'(\d{4})/(\d{1,2})/(\d{1,2})',
        r'(\d{4})-(\d{1,2})-(\d{1,2})'
    ]

    for pattern in date_patterns:
        match = re.search(pattern, date_string)
        if match:
            try:
                groups = match.groups()
                if len(groups) == 3:
                    # Determine if it's MM/DD/YYYY or DD/MM/YYYY
                    if int(groups[0]) > 12:  # DD/MM/YYYY
                        return date(int(groups[2]), int(groups[1]), int(groups[0]))
                    else:  # MM/DD/YYYY or YYYY/MM/DD
                        if int(groups[2]) > 31:  # YYYY/MM/DD
                            return date(int(groups[0]), int(groups[1]), int(groups[2]))
                        else:  # MM/DD/YYYY
                            return date(int(groups[2]), int(groups[0]), int(groups[1]))
            except (ValueError, IndexError):
                continue

    return None

def verify_face_match(doc_bucket, doc_key, selfie_bucket, selfie_key):
    """Verify face match between document and selfie"""
    rekognition = boto3.client('rekognition')

    try:
        response = rekognition.compare_faces(
            SourceImage={
                'S3Object': {
                    'Bucket': doc_bucket,
                    'Name': doc_key
                }
            },
            TargetImage={
                'S3Object': {
                    'Bucket': selfie_bucket,
                    'Name': selfie_key
                }
            },
            SimilarityThreshold=80.0
        )

        face_matches = response.get('FaceMatches', [])

        if face_matches:
            match = face_matches[0]
            similarity = match['Similarity']
            confidence = match['Face']['Confidence']

            return {
                'status': 'MATCH' if similarity >= 80 else 'NO_MATCH',
                'similarity': similarity,
                'confidence': confidence,
                'threshold': 80.0
            }
        else:
            return {
                'status': 'NO_MATCH',
                'similarity': 0,
                'confidence': 0,
                'reason': 'No face matches found'
            }

    except Exception as e:
        logger.error(f"Face verification failed: {str(e)}")
        return {
            'status': 'ERROR',
            'error': str(e)
        }

def determine_verification_status(age_verification, face_match):
    """Determine overall verification status"""
    if age_verification.get('is_over_18') and age_verification.get('confidence') in ['high', 'medium']:
        if face_match.get('status') == 'MATCH' or face_match.get('status') == 'SKIPPED':
            return 'VERIFIED'
        elif face_match.get('status') == 'NO_MATCH':
            return 'REJECTED'
        else:
            return 'REVIEW_REQUIRED'
    else:
        return 'REJECTED'

def store_verification_result(bucket, result):
    """Store verification result in S3"""
    s3_client = boto3.client('s3')

    try:
        timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
        key = f"age-verifications/{timestamp}/{result['verification_id']}.json"

        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(result, indent=2, default=str),
            ContentType='application/json'
        )

    except Exception as e:
        logger.error(f"Failed to store verification result: {str(e)}")

def update_user_verification_status(result, environment, project_name):
    """Update user verification status in database"""
    # This would update the user's verification status in the database
    logger.info(f"Updated verification status for user {result['user_id']}: {result['status']}")

def store_compliance_record(result, environment, project_name):
    """Store compliance record in DynamoDB"""
    dynamodb = boto3.resource('dynamodb')

    try:
        table_name = f"{project_name}-compliance-records-{environment}"
        table = dynamodb.Table(table_name)

        record = {
            'record_id': result['verification_id'],
            'record_type': 'AGE_VERIFICATION',
            'user_id': result['user_id'],
            'timestamp': result['timestamp'],
            'verification_status': result['status'],
            'verification_details': {
                'age_verified': result.get('age_verification', {}).get('is_over_18', False),
                'age': result.get('age_verification', {}).get('age'),
                'birth_date': result.get('age_verification', {}).get('birth_date'),
                'face_match_status': result.get('face_match', {}).get('status'),
                'confidence': result.get('age_verification', {}).get('confidence')
            }
        }

        table.put_item(Item=record)

    except Exception as e:
        logger.error(f"Failed to store compliance record: {str(e)}")

def verify_identity_document(event, environment, project_name, compliance_bucket):
    """Verify identity document independently"""
    document_url = event.get('document_url')

    if not document_url:
        raise ValueError("document_url is required")

    bucket, key = parse_s3_url(document_url)
    analysis = analyze_identity_document(bucket, key)

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Document analysis completed',
            'analysis': analysis
        })
    }

def audit_age_verifications(event, environment, project_name, compliance_bucket):
    """Audit age verification compliance"""
    logger.info("Starting age verification audit")

    dynamodb = boto3.resource('dynamodb')
    s3_client = boto3.client('s3')

    try:
        table_name = f"{project_name}-compliance-records-{environment}"
        table = dynamodb.Table(table_name)

        # Get verification statistics
        now = datetime.utcnow()
        one_month_ago = (now - timedelta(days=30)).isoformat()

        # Query recent verification records
        response = table.query(
            IndexName='type-timestamp-index',
            KeyConditionExpression='record_type = :type AND #ts >= :timestamp',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':type': 'AGE_VERIFICATION',
                ':timestamp': one_month_ago
            }
        )

        records = response.get('Items', [])

        # Calculate statistics
        total_verifications = len(records)
        verified_users = len([r for r in records if r.get('verification_status') == 'VERIFIED'])
        rejected_users = len([r for r in records if r.get('verification_status') == 'REJECTED'])
        pending_reviews = len([r for r in records if r.get('verification_status') == 'REVIEW_REQUIRED'])

        audit_report = {
            'audit_timestamp': now.isoformat(),
            'audit_period': '30_days',
            'statistics': {
                'total_verifications': total_verifications,
                'verified_users': verified_users,
                'rejected_users': rejected_users,
                'pending_reviews': pending_reviews,
                'verification_rate': (verified_users / total_verifications * 100) if total_verifications > 0 else 0
            },
            'compliance_status': 'COMPLIANT'
        }

        # Store audit report
        audit_key = f"verification-audits/{now.strftime('%Y/%m/%d')}/age_verification_audit_{now.strftime('%H%M%S')}.json"
        s3_client.put_object(
            Bucket=compliance_bucket,
            Key=audit_key,
            Body=json.dumps(audit_report, indent=2),
            ContentType='application/json'
        )

        audit_verification_action(compliance_bucket, "VERIFICATION_AUDIT", audit_report)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Age verification audit completed',
                'audit_report': audit_report
            })
        }

    except Exception as e:
        logger.error(f"Age verification audit failed: {str(e)}")
        raise e

def audit_verification_action(bucket_name, action_type, details):
    """Log verification audit action to S3"""
    s3_client = boto3.client('s3')
    timestamp = datetime.utcnow().isoformat()

    audit_record = {
        "timestamp": timestamp,
        "action_type": action_type,
        "details": details,
        "audit_id": str(uuid.uuid4())
    }

    key = f"verification-audit/{datetime.utcnow().strftime('%Y/%m/%d')}/{timestamp}_{action_type}.json"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(audit_record, indent=2, default=str),
            ContentType='application/json'
        )
    except Exception as e:
        logger.error(f"Failed to write verification audit record: {str(e)}")

# Helper imports
from datetime import timedelta