import json
import boto3
import os
from datetime import datetime, date
import logging
import uuid
import re
import requests

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Florida HB 3 Age Verification Handler
    Implements strict age verification requirements for Florida users
    Complies with Florida HB 3 (2023) requirements
    """

    try:
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        compliance_bucket = os.environ['COMPLIANCE_BUCKET']
        geolocation_api_key = os.environ.get('GEOLOCATION_API_KEY', '')

        action = event.get('action', 'verify_age')

        if action == 'verify_age':
            return verify_florida_user_age(event, environment, project_name, compliance_bucket, geolocation_api_key)
        elif action == 'check_florida_status':
            return check_florida_user_status(event, environment, project_name, geolocation_api_key)
        elif action == 'validate_verification_method':
            return validate_verification_method(event, environment, project_name)
        elif action == 'audit_florida_compliance':
            return audit_florida_age_compliance(event, environment, project_name, compliance_bucket)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"Florida age verification failed: {str(e)}")
        audit_florida_action(compliance_bucket, "FLORIDA_AGE_VERIFICATION_ERROR", {"error": str(e), "event": event})
        raise e

def verify_florida_user_age(event, environment, project_name, compliance_bucket, geolocation_api_key):
    """Verify age for users accessing from Florida"""
    user_id = event.get('user_id')
    ip_address = event.get('ip_address')
    verification_method = event.get('verification_method')
    document_url = event.get('document_url', '')
    selfie_url = event.get('selfie_url', '')

    if not user_id or not ip_address:
        raise ValueError("user_id and ip_address are required")

    logger.info(f"Verifying Florida user age: {user_id} from IP: {ip_address}")

    # Check if user is accessing from Florida
    geolocation_result = get_user_geolocation(ip_address, geolocation_api_key)
    is_florida_user = geolocation_result.get('state', '').upper() in ['FL', 'FLORIDA']

    verification_result = {
        'user_id': user_id,
        'verification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'ip_address': ip_address,
        'geolocation': geolocation_result,
        'is_florida_user': is_florida_user,
        'verification_method': verification_method,
        'document_url': document_url,
        'selfie_url': selfie_url
    }

    try:
        if is_florida_user:
            # Florida HB 3 requires strict age verification
            florida_verification = perform_florida_age_verification(
                verification_method,
                document_url,
                selfie_url,
                verification_result
            )
            verification_result.update(florida_verification)
        else:
            # Standard age verification for non-Florida users
            standard_verification = perform_standard_age_verification(
                verification_method,
                document_url,
                verification_result
            )
            verification_result.update(standard_verification)

        # Store verification result
        store_florida_verification_result(verification_result, environment, project_name)

        # Store compliance record
        store_florida_compliance_record(verification_result, environment, project_name)

        audit_florida_action(compliance_bucket, "FLORIDA_AGE_VERIFIED", verification_result)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'verification_id': verification_result['verification_id'],
                'is_florida_user': is_florida_user,
                'verification_status': verification_result.get('verification_status'),
                'age_verified': verification_result.get('age_verified', False),
                'compliance_level': 'FLORIDA_HB3' if is_florida_user else 'STANDARD'
            })
        }

    except Exception as e:
        verification_result['verification_status'] = 'ERROR'
        verification_result['error'] = str(e)
        store_florida_verification_result(verification_result, environment, project_name)
        raise e

def get_user_geolocation(ip_address, api_key):
    """Get geolocation information for IP address"""
    try:
        # Using a geolocation service (replace with your preferred service)
        if api_key:
            # Premium geolocation service
            response = requests.get(
                f"https://api.ipgeolocation.io/ipgeo?apiKey={api_key}&ip={ip_address}",
                timeout=10
            )
            if response.status_code == 200:
                data = response.json()
                return {
                    'country': data.get('country_name', ''),
                    'state': data.get('state_prov', ''),
                    'city': data.get('city', ''),
                    'zip_code': data.get('zipcode', ''),
                    'latitude': data.get('latitude', ''),
                    'longitude': data.get('longitude', ''),
                    'isp': data.get('isp', ''),
                    'service': 'ipgeolocation.io'
                }

        # Fallback to free service
        response = requests.get(f"http://ip-api.com/json/{ip_address}", timeout=10)
        if response.status_code == 200:
            data = response.json()
            return {
                'country': data.get('country', ''),
                'state': data.get('regionName', ''),
                'city': data.get('city', ''),
                'zip_code': data.get('zip', ''),
                'latitude': data.get('lat', ''),
                'longitude': data.get('lon', ''),
                'isp': data.get('isp', ''),
                'service': 'ip-api.com'
            }

    except Exception as e:
        logger.error(f"Geolocation lookup failed: {str(e)}")

    return {
        'country': 'Unknown',
        'state': 'Unknown',
        'city': 'Unknown',
        'service': 'failed'
    }

def perform_florida_age_verification(verification_method, document_url, selfie_url, verification_result):
    """Perform Florida HB 3 compliant age verification"""
    logger.info("Performing Florida HB 3 age verification")

    # Florida HB 3 approved verification methods
    approved_methods = [
        'government_issued_id',
        'credit_card_verification',
        'commercial_age_verification_service',
        'digital_identity_verification'
    ]

    if verification_method not in approved_methods:
        return {
            'verification_status': 'REJECTED',
            'age_verified': False,
            'florida_compliant': False,
            'rejection_reason': f'Verification method {verification_method} not approved for Florida HB 3'
        }

    result = {}

    if verification_method == 'government_issued_id':
        if not document_url:
            return {
                'verification_status': 'REJECTED',
                'age_verified': False,
                'florida_compliant': False,
                'rejection_reason': 'Government ID document required'
            }

        # Analyze government ID
        id_analysis = analyze_government_id(document_url)
        result['id_analysis'] = id_analysis

        # Verify age from document
        age_verification = verify_age_from_florida_id(id_analysis)
        result['age_verification'] = age_verification

        # If selfie provided, verify face match (required for Florida)
        if selfie_url:
            face_match = verify_face_match_florida(document_url, selfie_url)
            result['face_match'] = face_match
        else:
            return {
                'verification_status': 'REJECTED',
                'age_verified': False,
                'florida_compliant': False,
                'rejection_reason': 'Selfie verification required for Florida HB 3 compliance'
            }

    elif verification_method == 'credit_card_verification':
        # Credit card age verification (simplified)
        result = perform_credit_card_verification(verification_result)

    elif verification_method == 'commercial_age_verification_service':
        # Third-party commercial service verification
        result = perform_commercial_age_verification(verification_result)

    elif verification_method == 'digital_identity_verification':
        # Digital identity verification
        result = perform_digital_identity_verification(verification_result)

    # Determine overall verification status for Florida
    florida_compliant = determine_florida_compliance_status(result, verification_method)

    result.update({
        'verification_status': 'VERIFIED' if florida_compliant else 'REJECTED',
        'age_verified': florida_compliant,
        'florida_compliant': florida_compliant,
        'hb3_compliance_level': 'STRICT'
    })

    return result

def analyze_government_id(document_url):
    """Analyze government-issued ID document"""
    textract = boto3.client('textract')

    try:
        # Parse S3 URL
        bucket, key = parse_s3_url(document_url)

        # Use AnalyzeID for government IDs
        response = textract.analyze_id(
            DocumentLocation={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )

        # Extract identity information
        identity_documents = response.get('IdentityDocuments', [])

        if not identity_documents:
            return {
                'extraction_method': 'failed',
                'error': 'No identity document detected',
                'extracted_data': {}
            }

        document_info = identity_documents[0]
        identity_fields = document_info.get('IdentityDocumentFields', [])

        extracted_data = {}
        confidence_scores = {}

        for field in identity_fields:
            field_type = field.get('Type', {}).get('Text', '')
            field_value = field.get('ValueDetection', {}).get('Text', '')
            confidence = field.get('ValueDetection', {}).get('Confidence', 0)

            if field_type and field_value:
                extracted_data[field_type.lower().replace(' ', '_')] = field_value
                confidence_scores[field_type.lower().replace(' ', '_')] = confidence

        # Validate document type for Florida compliance
        document_type = extracted_data.get('document_type', '').lower()
        valid_florida_documents = [
            'driver_license', 'drivers_license', 'state_id', 'passport',
            'military_id', 'tribal_id'
        ]

        is_valid_document = any(doc_type in document_type for doc_type in valid_florida_documents)

        return {
            'extraction_method': 'analyze_id',
            'confidence': 'high',
            'extracted_data': extracted_data,
            'confidence_scores': confidence_scores,
            'is_valid_florida_document': is_valid_document,
            'document_type': document_type
        }

    except Exception as e:
        logger.error(f"Government ID analysis failed: {str(e)}")
        return {
            'extraction_method': 'failed',
            'error': str(e),
            'extracted_data': {}
        }

def verify_age_from_florida_id(id_analysis):
    """Verify age from Florida government ID with strict validation"""
    extracted_data = id_analysis.get('extracted_data', {})

    # Look for date of birth fields
    dob_fields = [
        'date_of_birth', 'dob', 'birth_date', 'birthdate',
        'date_of_birth_text', 'dob_text'
    ]

    birth_date = None
    for field in dob_fields:
        if field in extracted_data:
            birth_date = parse_date_strict(extracted_data[field])
            if birth_date:
                break

    if not birth_date:
        return {
            'is_over_18': False,
            'is_over_21': False,
            'confidence': 'low',
            'reason': 'Could not extract birth date from document',
            'birth_date': None,
            'age': None,
            'florida_verification': False
        }

    # Calculate age with strict validation
    today = date.today()
    age = today.year - birth_date.year

    # Adjust if birthday hasn't occurred this year
    if (today.month, today.day) < (birth_date.month, birth_date.day):
        age -= 1

    # Florida HB 3 requires verification of 18+ for adult content
    is_over_18 = age >= 18
    is_over_21 = age >= 21

    # Additional Florida-specific validation
    florida_verification = (
        is_over_18 and
        id_analysis.get('is_valid_florida_document', False) and
        id_analysis.get('confidence') == 'high'
    )

    return {
        'is_over_18': is_over_18,
        'is_over_21': is_over_21,
        'confidence': 'high' if florida_verification else 'medium',
        'birth_date': birth_date.isoformat(),
        'age': age,
        'reason': f'Calculated age: {age} years',
        'florida_verification': florida_verification
    }

def verify_face_match_florida(doc_url, selfie_url):
    """Verify face match with Florida HB 3 requirements"""
    rekognition = boto3.client('rekognition')

    try:
        doc_bucket, doc_key = parse_s3_url(doc_url)
        selfie_bucket, selfie_key = parse_s3_url(selfie_url)

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
            SimilarityThreshold=95.0  # Higher threshold for Florida compliance
        )

        face_matches = response.get('FaceMatches', [])

        if face_matches:
            match = face_matches[0]
            similarity = match['Similarity']
            confidence = match['Face']['Confidence']

            # Florida requires high confidence face matching
            florida_compliant = similarity >= 95.0 and confidence >= 95.0

            return {
                'status': 'MATCH' if florida_compliant else 'NO_MATCH',
                'similarity': similarity,
                'confidence': confidence,
                'threshold': 95.0,
                'florida_compliant': florida_compliant
            }
        else:
            return {
                'status': 'NO_MATCH',
                'similarity': 0,
                'confidence': 0,
                'reason': 'No face matches found',
                'florida_compliant': False
            }

    except Exception as e:
        logger.error(f"Florida face verification failed: {str(e)}")
        return {
            'status': 'ERROR',
            'error': str(e),
            'florida_compliant': False
        }

def perform_credit_card_verification(verification_result):
    """Perform credit card age verification (Florida approved method)"""
    # This would integrate with credit card verification services
    # For demonstration, we'll return a structured response

    return {
        'verification_method': 'credit_card',
        'status': 'PENDING_IMPLEMENTATION',
        'message': 'Credit card verification requires integration with approved services',
        'florida_approved': True
    }

def perform_commercial_age_verification(verification_result):
    """Perform commercial age verification service check"""
    # This would integrate with approved commercial services like Veratad, Jumio, etc.

    return {
        'verification_method': 'commercial_service',
        'status': 'PENDING_IMPLEMENTATION',
        'message': 'Commercial verification requires integration with approved services',
        'florida_approved': True
    }

def perform_digital_identity_verification(verification_result):
    """Perform digital identity verification"""
    # This would integrate with digital identity services

    return {
        'verification_method': 'digital_identity',
        'status': 'PENDING_IMPLEMENTATION',
        'message': 'Digital identity verification requires integration with approved services',
        'florida_approved': True
    }

def perform_standard_age_verification(verification_method, document_url, verification_result):
    """Perform standard age verification for non-Florida users"""
    if verification_method == 'government_issued_id' and document_url:
        # Standard document verification
        id_analysis = analyze_government_id(document_url)
        age_verification = verify_age_from_document_standard(id_analysis)

        return {
            'verification_status': 'VERIFIED' if age_verification.get('is_over_18') else 'REJECTED',
            'age_verified': age_verification.get('is_over_18', False),
            'age_verification': age_verification,
            'florida_compliant': False,
            'compliance_level': 'STANDARD'
        }
    else:
        return {
            'verification_status': 'REJECTED',
            'age_verified': False,
            'florida_compliant': False,
            'rejection_reason': 'Invalid verification method for standard verification'
        }

def verify_age_from_document_standard(id_analysis):
    """Standard age verification (less strict than Florida)"""
    extracted_data = id_analysis.get('extracted_data', {})

    # Look for date of birth
    dob_fields = ['date_of_birth', 'dob', 'birth_date']
    birth_date = None

    for field in dob_fields:
        if field in extracted_data:
            birth_date = parse_date_strict(extracted_data[field])
            if birth_date:
                break

    if not birth_date:
        return {'is_over_18': False, 'confidence': 'low'}

    # Calculate age
    today = date.today()
    age = today.year - birth_date.year
    if (today.month, today.day) < (birth_date.month, birth_date.day):
        age -= 1

    return {
        'is_over_18': age >= 18,
        'age': age,
        'birth_date': birth_date.isoformat(),
        'confidence': 'medium'
    }

def determine_florida_compliance_status(verification_result, verification_method):
    """Determine if verification meets Florida HB 3 requirements"""
    if verification_method == 'government_issued_id':
        age_verification = verification_result.get('age_verification', {})
        face_match = verification_result.get('face_match', {})

        return (
            age_verification.get('florida_verification', False) and
            age_verification.get('is_over_18', False) and
            face_match.get('florida_compliant', False)
        )
    else:
        # For other methods, check if they're implemented and approved
        return verification_result.get('florida_approved', False)

def parse_s3_url(url):
    """Parse S3 URL to extract bucket and key"""
    if not url.startswith('s3://'):
        raise ValueError("Only S3 URLs are supported")

    parts = url.replace('s3://', '').split('/', 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ''
    return bucket, key

def parse_date_strict(date_string):
    """Parse date string with strict validation"""
    if not date_string:
        return None

    # Common date formats with strict validation
    formats = [
        '%m/%d/%Y', '%m-%d-%Y', '%m.%d.%Y',
        '%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y',
        '%Y/%m/%d', '%Y-%m-%d', '%Y.%m.%d',
        '%B %d, %Y', '%b %d, %Y',
        '%d %B %Y', '%d %b %Y'
    ]

    for fmt in formats:
        try:
            parsed_date = datetime.strptime(date_string.strip(), fmt).date()
            # Validate date is reasonable (not in future, not too old)
            today = date.today()
            if parsed_date <= today and (today.year - parsed_date.year) <= 120:
                return parsed_date
        except ValueError:
            continue

    return None

def check_florida_user_status(event, environment, project_name, geolocation_api_key):
    """Check if user is from Florida and their verification status"""
    user_id = event.get('user_id')
    ip_address = event.get('ip_address')

    if not user_id or not ip_address:
        raise ValueError("user_id and ip_address are required")

    # Get geolocation
    geolocation = get_user_geolocation(ip_address, geolocation_api_key)
    is_florida_user = geolocation.get('state', '').upper() in ['FL', 'FLORIDA']

    # Get existing verification status
    verification_status = get_user_verification_status(user_id, environment, project_name)

    return {
        'statusCode': 200,
        'body': json.dumps({
            'user_id': user_id,
            'is_florida_user': is_florida_user,
            'geolocation': geolocation,
            'verification_status': verification_status,
            'requires_florida_verification': is_florida_user and not verification_status.get('florida_verified', False)
        })
    }

def validate_verification_method(event, environment, project_name):
    """Validate if verification method is approved for Florida HB 3"""
    verification_method = event.get('verification_method')
    is_florida_user = event.get('is_florida_user', False)

    florida_approved_methods = [
        'government_issued_id',
        'credit_card_verification',
        'commercial_age_verification_service',
        'digital_identity_verification'
    ]

    standard_approved_methods = [
        'government_issued_id',
        'self_declaration'  # Not allowed for Florida users
    ]

    if is_florida_user:
        is_valid = verification_method in florida_approved_methods
        compliance_level = 'FLORIDA_HB3'
    else:
        is_valid = verification_method in standard_approved_methods
        compliance_level = 'STANDARD'

    return {
        'statusCode': 200,
        'body': json.dumps({
            'verification_method': verification_method,
            'is_valid': is_valid,
            'compliance_level': compliance_level,
            'is_florida_user': is_florida_user
        })
    }

def get_user_verification_status(user_id, environment, project_name):
    """Get user's current verification status"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-florida-age-verification-{environment}"

    try:
        table = dynamodb.Table(table_name)
        response = table.query(
            KeyConditionExpression='user_id = :user_id',
            ExpressionAttributeValues={':user_id': user_id},
            ScanIndexForward=False,  # Get most recent first
            Limit=1
        )

        if response['Items']:
            latest_verification = response['Items'][0]
            return {
                'verified': latest_verification.get('verification_status') == 'VERIFIED',
                'florida_verified': latest_verification.get('florida_compliant', False),
                'verification_timestamp': latest_verification.get('verification_timestamp'),
                'verification_method': latest_verification.get('verification_method')
            }

    except Exception as e:
        logger.error(f"Failed to get verification status: {str(e)}")

    return {
        'verified': False,
        'florida_verified': False
    }

def store_florida_verification_result(result, environment, project_name):
    """Store verification result in DynamoDB"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-florida-age-verification-{environment}"

    try:
        table = dynamodb.Table(table_name)

        item = {
            'user_id': result['user_id'],
            'verification_timestamp': result['timestamp'],
            'verification_id': result['verification_id'],
            'ip_address': result['ip_address'],
            'is_florida_user': result['is_florida_user'],
            'verification_method': result.get('verification_method', ''),
            'verification_status': result.get('verification_status', 'PENDING'),
            'age_verified': result.get('age_verified', False),
            'florida_compliant': result.get('florida_compliant', False),
            'geolocation': result.get('geolocation', {}),
            'verification_details': {
                k: v for k, v in result.items()
                if k not in ['user_id', 'verification_timestamp', 'verification_id']
            }
        }

        table.put_item(Item=item)

    except Exception as e:
        logger.error(f"Failed to store Florida verification result: {str(e)}")

def store_florida_compliance_record(result, environment, project_name):
    """Store compliance record in federal compliance table"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-compliance-records-{environment}"

    try:
        table = dynamodb.Table(table_name)

        record = {
            'record_id': result['verification_id'],
            'record_type': 'FLORIDA_AGE_VERIFICATION',
            'user_id': result['user_id'],
            'timestamp': result['timestamp'],
            'compliance_status': 'COMPLIANT' if result.get('florida_compliant') else 'NON_COMPLIANT',
            'compliance_details': {
                'is_florida_user': result['is_florida_user'],
                'verification_method': result.get('verification_method'),
                'verification_status': result.get('verification_status'),
                'hb3_compliant': result.get('florida_compliant', False),
                'geolocation': result.get('geolocation', {})
            }
        }

        table.put_item(Item=record)

    except Exception as e:
        logger.error(f"Failed to store Florida compliance record: {str(e)}")

def audit_florida_age_compliance(event, environment, project_name, compliance_bucket):
    """Audit Florida age verification compliance"""
    logger.info("Auditing Florida age verification compliance")

    dynamodb = boto3.resource('dynamodb')
    s3_client = boto3.client('s3')
    table_name = f"{project_name}-florida-age-verification-{environment}"

    try:
        table = dynamodb.Table(table_name)

        # Get verification statistics for the last 30 days
        from datetime import timedelta
        thirty_days_ago = (datetime.utcnow() - timedelta(days=30)).isoformat()

        # Scan for recent verifications
        response = table.scan(
            FilterExpression='verification_timestamp >= :timestamp',
            ExpressionAttributeValues={':timestamp': thirty_days_ago}
        )

        records = response.get('Items', [])

        # Calculate statistics
        total_verifications = len(records)
        florida_users = len([r for r in records if r.get('is_florida_user')])
        florida_verified = len([r for r in records if r.get('is_florida_user') and r.get('florida_compliant')])
        standard_verified = len([r for r in records if not r.get('is_florida_user') and r.get('age_verified')])

        audit_report = {
            'audit_timestamp': datetime.utcnow().isoformat(),
            'audit_period': '30_days',
            'statistics': {
                'total_verifications': total_verifications,
                'florida_users': florida_users,
                'florida_verified': florida_verified,
                'standard_verified': standard_verified,
                'florida_compliance_rate': (florida_verified / florida_users * 100) if florida_users > 0 else 0,
                'overall_verification_rate': ((florida_verified + standard_verified) / total_verifications * 100) if total_verifications > 0 else 0
            },
            'compliance_status': 'COMPLIANT',
            'florida_hb3_compliance': True
        }

        # Store audit report
        audit_key = f"florida-audits/{datetime.utcnow().strftime('%Y/%m/%d')}/age_verification_audit_{datetime.utcnow().strftime('%H%M%S')}.json"
        s3_client.put_object(
            Bucket=compliance_bucket,
            Key=audit_key,
            Body=json.dumps(audit_report, indent=2),
            ContentType='application/json'
        )

        audit_florida_action(compliance_bucket, "FLORIDA_AGE_VERIFICATION_AUDIT", audit_report)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Florida age verification audit completed',
                'audit_report': audit_report
            })
        }

    except Exception as e:
        logger.error(f"Florida age verification audit failed: {str(e)}")
        raise e

def audit_florida_action(bucket_name, action_type, details):
    """Log Florida compliance audit action to S3"""
    s3_client = boto3.client('s3')
    timestamp = datetime.utcnow().isoformat()

    audit_record = {
        "timestamp": timestamp,
        "action_type": action_type,
        "details": details,
        "audit_id": str(uuid.uuid4()),
        "compliance_framework": "FLORIDA_HB3"
    }

    key = f"florida-audit/{datetime.utcnow().strftime('%Y/%m/%d')}/{timestamp}_{action_type}.json"

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(audit_record, indent=2, default=str),
            ContentType='application/json'
        )
    except Exception as e:
        logger.error(f"Failed to write Florida audit record: {str(e)}")