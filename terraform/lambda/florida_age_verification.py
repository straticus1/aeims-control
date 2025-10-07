"""
Florida Age Verification Lambda Function

This function implements age verification specifically for Florida state
requirements and HB 3 compliance for social media platforms.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
rekognition = boto3.client('rekognition')

# Configuration
VERIFICATION_TABLE = os.environ.get('FL_VERIFICATION_TABLE', 'aeims-florida-age-verification')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
PARENTAL_CONSENT_BUCKET = os.environ.get('PARENTAL_CONSENT_BUCKET')

class FloridaAgeVerifier:
    """Main class for Florida-specific age verification"""

    def __init__(self):
        self.table = dynamodb.Table(VERIFICATION_TABLE)

        # Florida HB 3 requirements
        self.florida_requirements = {
            'under_14': {
                'platform_access': 'PROHIBITED',
                'parental_consent': 'N/A',
                'verification_method': 'STRICT'
            },
            '14_to_15': {
                'platform_access': 'WITH_PARENTAL_CONSENT',
                'parental_consent': 'REQUIRED',
                'verification_method': 'ENHANCED',
                'parental_controls': 'MANDATORY'
            },
            '16_to_17': {
                'platform_access': 'WITH_CONSENT_OR_NOTIFICATION',
                'parental_consent': 'REQUIRED_OR_NOTIFICATION',
                'verification_method': 'STANDARD',
                'parental_controls': 'OPTIONAL'
            },
            '18_plus': {
                'platform_access': 'UNRESTRICTED',
                'parental_consent': 'NOT_REQUIRED',
                'verification_method': 'STANDARD'
            }
        }

    def verify_age_florida_requirements(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Verify age according to Florida HB 3 requirements"""
        try:
            verification_result = {
                'verification_status': 'PENDING',
                'age_category': None,
                'florida_compliance': False,
                'access_permitted': False,
                'parental_consent_required': False,
                'parental_controls_required': False,
                'verification_method_used': None,
                'compliance_issues': [],
                'next_steps': []
            }

            # Extract user information
            user_id = user_data.get('user_id')
            claimed_age = user_data.get('claimed_age')
            location = user_data.get('location', {})
            verification_documents = user_data.get('verification_documents', [])

            # Check if user is in Florida or subject to Florida law
            is_florida_resident = self._is_florida_jurisdiction(location)

            if not is_florida_resident:
                verification_result['verification_status'] = 'NOT_APPLICABLE'
                verification_result['florida_compliance'] = True
                verification_result['access_permitted'] = True
                return verification_result

            # Determine age category
            if claimed_age is None:
                verification_result['compliance_issues'].append('Age not provided')
                verification_result['next_steps'].append('Collect age information')
                return verification_result

            age_category = self._categorize_age(claimed_age)
            verification_result['age_category'] = age_category

            # Apply Florida requirements based on age
            florida_rules = self.florida_requirements[age_category]

            # Check if platform access is allowed
            if florida_rules['platform_access'] == 'PROHIBITED':
                verification_result['access_permitted'] = False
                verification_result['verification_status'] = 'DENIED'
                verification_result['compliance_issues'].append('User under 14 - platform access prohibited under Florida HB 3')

            elif florida_rules['platform_access'] == 'WITH_PARENTAL_CONSENT':
                verification_result['parental_consent_required'] = True
                verification_result['parental_controls_required'] = florida_rules.get('parental_controls') == 'MANDATORY'

                # Check if parental consent has been obtained
                consent_status = self._check_parental_consent(user_id)
                if consent_status['has_consent']:
                    verification_result['access_permitted'] = True
                    verification_result['verification_status'] = 'APPROVED'
                else:
                    verification_result['access_permitted'] = False
                    verification_result['next_steps'].append('Obtain parental consent')

            elif florida_rules['platform_access'] == 'WITH_CONSENT_OR_NOTIFICATION':
                # For 16-17 year olds, either consent or notification is required
                consent_status = self._check_parental_consent(user_id)
                notification_status = self._check_parental_notification(user_id)

                if consent_status['has_consent'] or notification_status['has_notification']:
                    verification_result['access_permitted'] = True
                    verification_result['verification_status'] = 'APPROVED'
                else:
                    verification_result['access_permitted'] = False
                    verification_result['next_steps'].append('Obtain parental consent or send notification')

            else:  # 18+ unrestricted
                verification_result['access_permitted'] = True
                verification_result['verification_status'] = 'APPROVED'

            # Verify age using appropriate method
            verification_method = florida_rules['verification_method']
            age_verification_result = self._verify_age_documents(
                verification_documents,
                verification_method,
                claimed_age
            )

            verification_result['verification_method_used'] = verification_method
            verification_result.update(age_verification_result)

            # Final compliance check
            if (verification_result['access_permitted'] and
                age_verification_result.get('age_verified', False)):
                verification_result['florida_compliance'] = True
            else:
                verification_result['florida_compliance'] = False

            return verification_result

        except Exception as e:
            logger.error(f"Florida age verification error: {str(e)}")
            raise

    def _is_florida_jurisdiction(self, location: Dict[str, Any]) -> bool:
        """Determine if user is subject to Florida jurisdiction"""
        state = location.get('state', '').lower()
        country = location.get('country', '').lower()

        # Florida residents
        if state in ['florida', 'fl'] and country in ['usa', 'united states', 'us']:
            return True

        # Additional checks for IP-based location, billing address, etc.
        billing_state = location.get('billing_state', '').lower()
        if billing_state in ['florida', 'fl']:
            return True

        return False

    def _categorize_age(self, age: int) -> str:
        """Categorize age according to Florida HB 3 brackets"""
        if age < 14:
            return 'under_14'
        elif 14 <= age <= 15:
            return '14_to_15'
        elif 16 <= age <= 17:
            return '16_to_17'
        else:
            return '18_plus'

    def _check_parental_consent(self, user_id: str) -> Dict[str, Any]:
        """Check if parental consent has been obtained"""
        try:
            # Query consent records
            response = self.table.scan(
                FilterExpression='user_id = :uid AND record_type = :type',
                ExpressionAttributeValues={
                    ':uid': user_id,
                    ':type': 'parental_consent'
                }
            )

            consent_records = response.get('Items', [])

            if consent_records:
                latest_consent = max(consent_records, key=lambda x: x.get('timestamp', 0))
                return {
                    'has_consent': latest_consent.get('consent_granted', False),
                    'consent_date': latest_consent.get('consent_date'),
                    'consent_method': latest_consent.get('consent_method'),
                    'parent_info': latest_consent.get('parent_info', {})
                }

            return {'has_consent': False}

        except Exception as e:
            logger.error(f"Parental consent check error: {str(e)}")
            return {'has_consent': False, 'error': str(e)}

    def _check_parental_notification(self, user_id: str) -> Dict[str, Any]:
        """Check if parental notification has been sent"""
        try:
            response = self.table.scan(
                FilterExpression='user_id = :uid AND record_type = :type',
                ExpressionAttributeValues={
                    ':uid': user_id,
                    ':type': 'parental_notification'
                }
            )

            notification_records = response.get('Items', [])

            if notification_records:
                latest_notification = max(notification_records, key=lambda x: x.get('timestamp', 0))
                return {
                    'has_notification': True,
                    'notification_date': latest_notification.get('notification_date'),
                    'notification_method': latest_notification.get('notification_method'),
                    'parent_contact': latest_notification.get('parent_contact')
                }

            return {'has_notification': False}

        except Exception as e:
            logger.error(f"Parental notification check error: {str(e)}")
            return {'has_notification': False, 'error': str(e)}

    def _verify_age_documents(self, documents: List[Dict], method: str, claimed_age: int) -> Dict[str, Any]:
        """Verify age using provided documents based on verification method"""
        try:
            verification_result = {
                'age_verified': False,
                'confidence_score': 0.0,
                'verification_details': {},
                'issues': []
            }

            if not documents:
                verification_result['issues'].append('No verification documents provided')
                return verification_result

            if method == 'STRICT':
                # Strict verification for under 14 (should be denied anyway)
                verification_result['issues'].append('Strict verification not applicable - access denied')
                return verification_result

            elif method == 'ENHANCED':
                # Enhanced verification for 14-15 year olds
                verification_result = self._enhanced_age_verification(documents, claimed_age)

            elif method == 'STANDARD':
                # Standard verification for 16+ year olds
                verification_result = self._standard_age_verification(documents, claimed_age)

            return verification_result

        except Exception as e:
            logger.error(f"Age document verification error: {str(e)}")
            return {
                'age_verified': False,
                'confidence_score': 0.0,
                'issues': [f'Verification error: {str(e)}']
            }

    def _enhanced_age_verification(self, documents: List[Dict], claimed_age: int) -> Dict[str, Any]:
        """Enhanced age verification for 14-15 year olds"""
        verification_result = {
            'age_verified': False,
            'confidence_score': 0.0,
            'verification_details': {'method': 'enhanced'},
            'issues': []
        }

        # Require multiple forms of verification
        required_document_types = ['government_id', 'birth_certificate']
        provided_types = [doc.get('type') for doc in documents]

        missing_types = [req_type for req_type in required_document_types if req_type not in provided_types]

        if missing_types:
            verification_result['issues'].append(f'Missing required documents: {missing_types}')
            return verification_result

        # Verify each document
        total_confidence = 0.0
        verified_documents = 0

        for document in documents:
            doc_verification = self._verify_single_document(document, claimed_age)
            if doc_verification['verified']:
                total_confidence += doc_verification['confidence']
                verified_documents += 1

        if verified_documents >= 2 and total_confidence >= 1.6:  # High confidence requirement
            verification_result['age_verified'] = True
            verification_result['confidence_score'] = total_confidence / verified_documents
        else:
            verification_result['issues'].append('Insufficient document verification for enhanced method')

        return verification_result

    def _standard_age_verification(self, documents: List[Dict], claimed_age: int) -> Dict[str, Any]:
        """Standard age verification for 16+ year olds"""
        verification_result = {
            'age_verified': False,
            'confidence_score': 0.0,
            'verification_details': {'method': 'standard'},
            'issues': []
        }

        # Single valid document sufficient
        for document in documents:
            doc_verification = self._verify_single_document(document, claimed_age)
            if doc_verification['verified'] and doc_verification['confidence'] >= 0.8:
                verification_result['age_verified'] = True
                verification_result['confidence_score'] = doc_verification['confidence']
                break

        if not verification_result['age_verified']:
            verification_result['issues'].append('No valid documents for standard verification')

        return verification_result

    def _verify_single_document(self, document: Dict[str, Any], claimed_age: int) -> Dict[str, Any]:
        """Verify a single document"""
        try:
            doc_type = document.get('type')
            doc_data = document.get('data')

            if doc_type == 'government_id':
                return self._verify_government_id(doc_data, claimed_age)
            elif doc_type == 'birth_certificate':
                return self._verify_birth_certificate(doc_data, claimed_age)
            else:
                return {'verified': False, 'confidence': 0.0, 'reason': 'Unsupported document type'}

        except Exception as e:
            return {'verified': False, 'confidence': 0.0, 'reason': f'Verification error: {str(e)}'}

    def _verify_government_id(self, doc_data: str, claimed_age: int) -> Dict[str, Any]:
        """Verify government ID using AWS Rekognition"""
        try:
            # This would use Rekognition to extract text from ID documents
            # For demonstration, we'll simulate the verification

            # In a real implementation, this would:
            # 1. Use Rekognition to extract text from the ID image
            # 2. Parse birth date from the extracted text
            # 3. Calculate age and compare to claimed age
            # 4. Verify document authenticity

            verification_result = {
                'verified': True,  # Simulated successful verification
                'confidence': 0.9,
                'extracted_age': claimed_age,  # Would be extracted from document
                'document_type': 'drivers_license'  # Would be detected
            }

            return verification_result

        except Exception as e:
            logger.error(f"Government ID verification error: {str(e)}")
            return {'verified': False, 'confidence': 0.0, 'reason': str(e)}

    def _verify_birth_certificate(self, doc_data: str, claimed_age: int) -> Dict[str, Any]:
        """Verify birth certificate"""
        try:
            # Similar to government ID verification
            # Would extract birth date from birth certificate

            verification_result = {
                'verified': True,  # Simulated
                'confidence': 0.95,
                'extracted_age': claimed_age,
                'document_type': 'birth_certificate'
            }

            return verification_result

        except Exception as e:
            logger.error(f"Birth certificate verification error: {str(e)}")
            return {'verified': False, 'confidence': 0.0, 'reason': str(e)}

    def store_verification_record(self, user_id: str, verification_result: Dict[str, Any]) -> bool:
        """Store age verification record"""
        try:
            item = {
                'record_id': f"{user_id}_{int(datetime.now(timezone.utc).timestamp())}",
                'user_id': user_id,
                'record_type': 'age_verification',
                'timestamp': int(datetime.now(timezone.utc).timestamp()),
                'verification_status': verification_result['verification_status'],
                'age_category': verification_result['age_category'],
                'florida_compliance': verification_result['florida_compliance'],
                'access_permitted': verification_result['access_permitted'],
                'parental_consent_required': verification_result['parental_consent_required'],
                'verification_method': verification_result.get('verification_method_used'),
                'compliance_framework': 'Florida_HB_3',
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=365)).timestamp())
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Verification record storage error: {str(e)}")
            return False

    def send_verification_alert(self, user_id: str, verification_result: Dict[str, Any]) -> bool:
        """Send alert for verification issues"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            # Send alert for compliance issues or denied access
            if not verification_result['florida_compliance'] or verification_result['compliance_issues']:
                alert = {
                    'alert_type': 'FLORIDA_AGE_VERIFICATION_ISSUE',
                    'user_id': user_id,
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'verification_status': verification_result['verification_status'],
                    'age_category': verification_result['age_category'],
                    'compliance_issues': verification_result['compliance_issues'],
                    'access_permitted': verification_result['access_permitted'],
                    'severity': 'HIGH' if not verification_result['access_permitted'] else 'MEDIUM'
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject="Florida Age Verification Alert",
                    Message=json.dumps(alert, indent=2)
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Verification alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for Florida age verification"""
    try:
        logger.info("Processing Florida age verification request")

        required_fields = ['user_id', 'user_data']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        user_id = event['user_id']
        user_data = event['user_data']
        user_data['user_id'] = user_id

        verifier = FloridaAgeVerifier()
        verification_result = verifier.verify_age_florida_requirements(user_data)

        stored = verifier.store_verification_record(user_id, verification_result)
        alert_sent = verifier.send_verification_alert(user_id, verification_result)

        response = {
            'statusCode': 200,
            'body': {
                'user_id': user_id,
                'verification_completed': True,
                'verification_status': verification_result['verification_status'],
                'age_category': verification_result['age_category'],
                'florida_compliance': verification_result['florida_compliance'],
                'access_permitted': verification_result['access_permitted'],
                'parental_consent_required': verification_result['parental_consent_required'],
                'parental_controls_required': verification_result.get('parental_controls_required', False),
                'next_steps': verification_result['next_steps'],
                'alert_sent': alert_sent,
                'record_stored': stored,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_framework': 'Florida_HB_3'
            }
        }

        return response

    except ValueError as e:
        logger.error(f"Input validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': {'error': 'Invalid input', 'message': str(e)}
        }

    except Exception as e:
        logger.error(f"Florida age verification error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Age verification failed'}
        }