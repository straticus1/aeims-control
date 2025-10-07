"""
Privacy Rights Lambda Function

This function handles user privacy rights requests including GDPR, CCPA,
and COPPA compliance for data access, portability, deletion, and correction.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
sns = boto3.client('sns')

# Configuration
PRIVACY_TABLE = os.environ.get('PRIVACY_REQUESTS_TABLE', 'aeims-privacy-requests')
DATA_EXPORT_BUCKET = os.environ.get('DATA_EXPORT_BUCKET')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')

class PrivacyRightsHandler:
    """Main class for handling privacy rights requests"""

    def __init__(self):
        self.table = dynamodb.Table(PRIVACY_TABLE)

        # Privacy rights frameworks
        self.privacy_frameworks = {
            'GDPR': {
                'applicable_regions': ['EU', 'EEA'],
                'rights': [
                    'right_to_access',
                    'right_to_rectification',
                    'right_to_erasure',
                    'right_to_portability',
                    'right_to_restrict_processing',
                    'right_to_object'
                ],
                'response_timeframe': 30  # days
            },
            'CCPA': {
                'applicable_regions': ['California'],
                'rights': [
                    'right_to_know',
                    'right_to_delete',
                    'right_to_opt_out',
                    'right_to_non_discrimination'
                ],
                'response_timeframe': 45  # days
            },
            'COPPA': {
                'applicable_users': ['under_13'],
                'rights': [
                    'parental_access',
                    'parental_deletion',
                    'consent_withdrawal'
                ],
                'response_timeframe': 30  # days
            },
            'Florida_HB_3': {
                'applicable_users': ['under_18_florida'],
                'rights': [
                    'parental_access_minor_data',
                    'parental_deletion_minor_data',
                    'data_portability'
                ],
                'response_timeframe': 30  # days
            }
        }

        # Request types and processing requirements
        self.request_types = {
            'data_access': {
                'description': 'Provide user with copy of their personal data',
                'complexity': 'medium',
                'automation_possible': True,
                'verification_required': True
            },
            'data_deletion': {
                'description': 'Delete user personal data (right to erasure)',
                'complexity': 'high',
                'automation_possible': False,
                'verification_required': True,
                'legal_review_required': True
            },
            'data_correction': {
                'description': 'Correct inaccurate personal data',
                'complexity': 'low',
                'automation_possible': True,
                'verification_required': True
            },
            'data_portability': {
                'description': 'Provide data in portable format',
                'complexity': 'medium',
                'automation_possible': True,
                'verification_required': True
            },
            'opt_out_sale': {
                'description': 'Opt out of personal data sale',
                'complexity': 'low',
                'automation_possible': True,
                'verification_required': False
            },
            'consent_withdrawal': {
                'description': 'Withdraw consent for data processing',
                'complexity': 'medium',
                'automation_possible': False,
                'verification_required': True
            }
        }

    def process_privacy_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process privacy rights request"""
        try:
            processing_result = {
                'request_id': str(uuid.uuid4()),
                'request_accepted': False,
                'applicable_frameworks': [],
                'verification_required': False,
                'automated_processing': False,
                'estimated_completion_date': None,
                'next_steps': [],
                'compliance_notes': []
            }

            user_id = request_data.get('user_id')
            request_type = request_data.get('request_type')
            user_location = request_data.get('user_location', {})
            user_age = request_data.get('user_age')
            requester_type = request_data.get('requester_type', 'user')  # user, parent, legal_guardian

            # Determine applicable privacy frameworks
            applicable_frameworks = self._determine_applicable_frameworks(user_location, user_age, requester_type)
            processing_result['applicable_frameworks'] = applicable_frameworks

            if not applicable_frameworks:
                processing_result['request_accepted'] = False
                processing_result['next_steps'].append('Request not applicable under current privacy frameworks')
                return processing_result

            # Validate request type
            if request_type not in self.request_types:
                raise ValueError(f"Invalid request type: {request_type}")

            request_config = self.request_types[request_type]
            processing_result['request_accepted'] = True

            # Determine verification requirements
            if request_config['verification_required']:
                processing_result['verification_required'] = True
                processing_result['next_steps'].append('Identity verification required before processing')

            # Check if automated processing is possible
            if request_config['automation_possible'] and not request_config.get('legal_review_required'):
                processing_result['automated_processing'] = True
                processing_result['next_steps'].append('Request will be processed automatically')
            else:
                processing_result['next_steps'].append('Request requires manual review')

            # Calculate estimated completion date
            max_timeframe = max([
                self.privacy_frameworks[fw]['response_timeframe']
                for fw in applicable_frameworks
            ])
            estimated_completion = datetime.now(timezone.utc) + timedelta(days=max_timeframe)
            processing_result['estimated_completion_date'] = estimated_completion.isoformat()

            # Special handling for minors
            if user_age and user_age < 18:
                processing_result = self._handle_minor_request(processing_result, request_data)

            # Generate compliance notes
            processing_result['compliance_notes'] = self._generate_compliance_notes(
                applicable_frameworks, request_type, user_age
            )

            return processing_result

        except Exception as e:
            logger.error(f"Privacy request processing error: {str(e)}")
            raise

    def _determine_applicable_frameworks(self, user_location: Dict[str, Any], user_age: Optional[int], requester_type: str) -> List[str]:
        """Determine which privacy frameworks apply to the request"""
        applicable = []

        # Check GDPR applicability
        country = user_location.get('country', '').upper()
        if country in ['EU', 'EEA'] or user_location.get('gdpr_applicable', False):
            applicable.append('GDPR')

        # Check CCPA applicability
        state = user_location.get('state', '').lower()
        if state in ['california', 'ca']:
            applicable.append('CCPA')

        # Check COPPA applicability
        if user_age and user_age < 13:
            applicable.append('COPPA')

        # Check Florida HB 3 applicability
        if (user_age and user_age < 18 and state in ['florida', 'fl']):
            applicable.append('Florida_HB_3')

        return applicable

    def _handle_minor_request(self, processing_result: Dict[str, Any], request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Handle special requirements for minor user requests"""
        user_age = request_data.get('user_age')
        requester_type = request_data.get('requester_type')

        if user_age < 13:
            # COPPA requirements
            if requester_type != 'parent':
                processing_result['request_accepted'] = False
                processing_result['next_steps'] = ['Request must be made by parent or legal guardian for users under 13']
                return processing_result

            processing_result['compliance_notes'].append('COPPA: Parental verification required for under-13 user')

        elif user_age < 18:
            # Additional protections for 13-17 year olds
            if request_data.get('request_type') == 'data_deletion':
                processing_result['next_steps'].append('Additional minor protection review required for deletion request')

            if 'Florida_HB_3' in processing_result['applicable_frameworks']:
                processing_result['compliance_notes'].append('Florida HB 3: Enhanced minor protection requirements apply')

        return processing_result

    def _generate_compliance_notes(self, frameworks: List[str], request_type: str, user_age: Optional[int]) -> List[str]:
        """Generate compliance notes for the request"""
        notes = []

        for framework in frameworks:
            if framework == 'GDPR':
                notes.append(f'GDPR Article compliance required for {request_type}')
            elif framework == 'CCPA':
                notes.append(f'CCPA Section 1798.110+ compliance required for {request_type}')
            elif framework == 'COPPA':
                notes.append(f'COPPA parental rights enforcement for {request_type}')
            elif framework == 'Florida_HB_3':
                notes.append(f'Florida HB 3 minor protection requirements for {request_type}')

        if user_age and user_age < 18:
            notes.append('Enhanced minor data protection measures applied')

        return notes

    def execute_data_access_request(self, request_id: str, user_id: str) -> Dict[str, Any]:
        """Execute data access request (Subject Access Request)"""
        try:
            execution_result = {
                'request_id': request_id,
                'execution_status': 'in_progress',
                'data_collected': False,
                'export_location': None,
                'data_categories': [],
                'processing_notes': []
            }

            # Collect user data from various sources
            collected_data = self._collect_user_data(user_id)
            execution_result['data_categories'] = list(collected_data.keys())

            # Create data export
            if DATA_EXPORT_BUCKET and collected_data:
                export_location = self._create_data_export(request_id, user_id, collected_data)
                execution_result['export_location'] = export_location
                execution_result['data_collected'] = True
                execution_result['execution_status'] = 'completed'
            else:
                execution_result['processing_notes'].append('Data export location not configured or no data found')
                execution_result['execution_status'] = 'failed'

            return execution_result

        except Exception as e:
            logger.error(f"Data access request execution error: {str(e)}")
            return {
                'request_id': request_id,
                'execution_status': 'failed',
                'error': str(e)
            }

    def _collect_user_data(self, user_id: str) -> Dict[str, Any]:
        """Collect all user data for access request"""
        try:
            collected_data = {
                'profile_data': {},
                'communication_data': [],
                'content_data': [],
                'verification_data': {},
                'compliance_records': [],
                'metadata': {}
            }

            # This would typically query multiple data sources
            # For demonstration, we'll show the structure

            collected_data['metadata'] = {
                'collection_timestamp': datetime.now(timezone.utc).isoformat(),
                'data_retention_period': '7_years',
                'collection_method': 'automated_privacy_request',
                'data_categories_included': list(collected_data.keys())
            }

            return collected_data

        except Exception as e:
            logger.error(f"User data collection error: {str(e)}")
            return {}

    def _create_data_export(self, request_id: str, user_id: str, data: Dict[str, Any]) -> str:
        """Create secure data export for user"""
        try:
            timestamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
            export_key = f"privacy-exports/{request_id}/{timestamp}/user_data_export.json"

            # Anonymize sensitive internal data
            export_data = self._anonymize_export_data(data)

            # Add export metadata
            export_data['export_metadata'] = {
                'export_id': request_id,
                'export_timestamp': datetime.now(timezone.utc).isoformat(),
                'data_subject_id': user_id,
                'export_format': 'JSON',
                'privacy_framework_compliance': 'GDPR_CCPA_COPPA',
                'data_integrity_hash': 'calculated_hash_would_go_here'
            }

            # Upload to S3 with encryption
            s3.put_object(
                Bucket=DATA_EXPORT_BUCKET,
                Key=export_key,
                Body=json.dumps(export_data, indent=2),
                ContentType='application/json',
                ServerSideEncryption='AES256',
                Metadata={
                    'privacy_export': 'true',
                    'request_id': request_id,
                    'export_timestamp': timestamp
                }
            )

            return f"s3://{DATA_EXPORT_BUCKET}/{export_key}"

        except Exception as e:
            logger.error(f"Data export creation error: {str(e)}")
            raise

    def _anonymize_export_data(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Anonymize internal data for user export"""
        # Remove internal system identifiers, replace with user-friendly descriptions
        anonymized = data.copy()

        # Remove sensitive internal metadata
        for category in anonymized:
            if isinstance(anonymized[category], dict):
                # Remove internal system fields
                anonymized[category].pop('internal_id', None)
                anonymized[category].pop('system_metadata', None)

        return anonymized

    def store_privacy_request(self, request_data: Dict[str, Any], processing_result: Dict[str, Any]) -> bool:
        """Store privacy request record"""
        try:
            item = {
                'request_id': processing_result['request_id'],
                'user_id': request_data.get('user_id'),
                'request_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'request_type': request_data.get('request_type'),
                'requester_type': request_data.get('requester_type'),
                'applicable_frameworks': processing_result['applicable_frameworks'],
                'status': 'received',
                'verification_required': processing_result['verification_required'],
                'automated_processing': processing_result['automated_processing'],
                'estimated_completion_date': processing_result['estimated_completion_date'],
                'compliance_notes': processing_result['compliance_notes'],
                'request_data': json.dumps(request_data),
                'processing_result': json.dumps(processing_result),
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=2555)).timestamp())  # 7 year retention
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Privacy request storage error: {str(e)}")
            return False

    def send_privacy_alert(self, request_data: Dict[str, Any], processing_result: Dict[str, Any]) -> bool:
        """Send alert for privacy request"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            # Send alert for high-priority requests
            request_type = request_data.get('request_type')
            user_age = request_data.get('user_age')

            if (request_type == 'data_deletion' or
                (user_age and user_age < 18) or
                'COPPA' in processing_result['applicable_frameworks']):

                alert = {
                    'alert_type': 'PRIVACY_RIGHTS_REQUEST',
                    'request_id': processing_result['request_id'],
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'request_type': request_type,
                    'user_age': user_age,
                    'applicable_frameworks': processing_result['applicable_frameworks'],
                    'verification_required': processing_result['verification_required'],
                    'minor_involved': user_age < 18 if user_age else False,
                    'priority': 'HIGH' if request_type == 'data_deletion' or (user_age and user_age < 13) else 'MEDIUM'
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject=f"Privacy Rights Request - {request_type}",
                    Message=json.dumps(alert, indent=2)
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Privacy alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for privacy rights requests"""
    try:
        logger.info("Processing privacy rights request")

        action = event.get('action', 'process_request')

        handler = PrivacyRightsHandler()

        if action == 'process_request':
            required_fields = ['request_data']
            for field in required_fields:
                if field not in event:
                    raise ValueError(f"Missing required field: {field}")

            request_data = event['request_data']
            processing_result = handler.process_privacy_request(request_data)

            # Store request
            stored = handler.store_privacy_request(request_data, processing_result)

            # Send alert if needed
            alert_sent = handler.send_privacy_alert(request_data, processing_result)

            response = {
                'statusCode': 200,
                'body': {
                    'request_processed': True,
                    'request_id': processing_result['request_id'],
                    'request_accepted': processing_result['request_accepted'],
                    'applicable_frameworks': processing_result['applicable_frameworks'],
                    'verification_required': processing_result['verification_required'],
                    'automated_processing': processing_result['automated_processing'],
                    'estimated_completion_date': processing_result['estimated_completion_date'],
                    'next_steps': processing_result['next_steps'],
                    'alert_sent': alert_sent,
                    'request_stored': stored,
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }
            }

        elif action == 'execute_data_access':
            required_fields = ['request_id', 'user_id']
            for field in required_fields:
                if field not in event:
                    raise ValueError(f"Missing required field: {field}")

            execution_result = handler.execute_data_access_request(
                event['request_id'],
                event['user_id']
            )

            response = {
                'statusCode': 200,
                'body': execution_result
            }

        else:
            raise ValueError(f"Unsupported action: {action}")

        return response

    except ValueError as e:
        logger.error(f"Input validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': {'error': 'Invalid input', 'message': str(e)}
        }

    except Exception as e:
        logger.error(f"Privacy rights handler error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Privacy request processing failed'}
        }