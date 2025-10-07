"""
Content takedown handler Lambda function
Processes and manages content removal requests across platforms
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class TakedownHandler:
    def __init__(self):
        """Initialize takedown handler"""
        self.valid_request_types = [
            'ncii',           # Non-consensual intimate images
            'sex_trafficking', # Sex trafficking content
            'copyright',      # Copyright violation
            'harassment',     # Harassment/bullying
            'doxxing',       # Personal information disclosure
            'impersonation', # Identity theft/impersonation
            'minor_safety'   # Content involving minors
        ]

        self.priority_levels = {
            'ncii': 'CRITICAL',
            'sex_trafficking': 'CRITICAL',
            'minor_safety': 'CRITICAL',
            'doxxing': 'HIGH',
            'harassment': 'MEDIUM',
            'copyright': 'MEDIUM',
            'impersonation': 'MEDIUM'
        }

    def validate_takedown_request(self, request: Dict) -> Dict[str, Any]:
        """Validate incoming takedown request"""
        errors = []
        warnings = []

        # Required fields
        required_fields = ['request_type', 'content_url', 'reporter_info']
        for field in required_fields:
            if not request.get(field):
                errors.append(f"Missing required field: {field}")

        # Validate request type
        request_type = request.get('request_type', '').lower()
        if request_type not in self.valid_request_types:
            errors.append(f"Invalid request type: {request_type}")

        # Validate content URL
        content_url = request.get('content_url', '')
        if content_url and not (content_url.startswith('http://') or content_url.startswith('https://')):
            warnings.append("Content URL should include protocol (http/https)")

        # Validate reporter information
        reporter_info = request.get('reporter_info', {})
        if not reporter_info.get('contact_method'):
            warnings.append("No contact method provided for reporter")

        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings
        }

    def create_takedown_record(self, request: Dict) -> Dict[str, Any]:
        """Create a takedown record with tracking information"""
        request_id = str(uuid.uuid4())
        request_type = request['request_type'].lower()

        record = {
            'takedown_id': request_id,
            'request_type': request_type,
            'priority': self.priority_levels.get(request_type, 'MEDIUM'),
            'status': 'PENDING_REVIEW',
            'content_url': request['content_url'],
            'description': request.get('description', ''),
            'reporter_info': request['reporter_info'],
            'created_timestamp': datetime.utcnow().isoformat(),
            'last_updated': datetime.utcnow().isoformat(),
            'evidence_urls': request.get('evidence_urls', []),
            'legal_basis': request.get('legal_basis', ''),
            'platform': self.extract_platform(request['content_url']),
            'escalation_level': 0
        }

        # Set expected resolution timeframe based on priority
        if record['priority'] == 'CRITICAL':
            expected_resolution = datetime.utcnow() + timedelta(hours=2)
        elif record['priority'] == 'HIGH':
            expected_resolution = datetime.utcnow() + timedelta(hours=24)
        else:
            expected_resolution = datetime.utcnow() + timedelta(days=3)

        record['expected_resolution'] = expected_resolution.isoformat()

        return record

    def extract_platform(self, url: str) -> str:
        """Extract platform name from content URL"""
        url_lower = url.lower()

        platform_mapping = {
            'twitter.com': 'Twitter',
            'x.com': 'Twitter',
            'facebook.com': 'Facebook',
            'instagram.com': 'Instagram',
            'tiktok.com': 'TikTok',
            'youtube.com': 'YouTube',
            'reddit.com': 'Reddit',
            'discord.com': 'Discord',
            'telegram.org': 'Telegram',
            'onlyfans.com': 'OnlyFans'
        }

        for domain, platform in platform_mapping.items():
            if domain in url_lower:
                return platform

        return 'Unknown'

    def process_takedown_request(self, request: Dict) -> Dict[str, Any]:
        """Process a complete takedown request"""
        # Validate request
        validation_result = self.validate_takedown_request(request)

        if not validation_result['valid']:
            return {
                'success': False,
                'errors': validation_result['errors'],
                'warnings': validation_result.get('warnings', [])
            }

        # Create takedown record
        takedown_record = self.create_takedown_record(request)

        # Log the takedown request
        logger.info(f"Takedown request created: {takedown_record['takedown_id']} "
                   f"Type: {takedown_record['request_type']} "
                   f"Priority: {takedown_record['priority']} "
                   f"Platform: {takedown_record['platform']}")

        # For critical requests, send immediate alerts
        if takedown_record['priority'] == 'CRITICAL':
            logger.critical(f"CRITICAL TAKEDOWN REQUEST: {takedown_record['takedown_id']} "
                          f"Type: {takedown_record['request_type']} "
                          f"URL: {takedown_record['content_url']}")

        return {
            'success': True,
            'takedown_record': takedown_record,
            'warnings': validation_result.get('warnings', [])
        }

def lambda_handler(event, context):
    """Main Lambda handler for takedown requests"""
    try:
        # Extract takedown request from event
        takedown_request = event.get('takedown_request', {})
        action = event.get('action', 'create')

        if not takedown_request and action == 'create':
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No takedown request provided'
                })
            }

        # Initialize handler
        handler = TakedownHandler()

        if action == 'create':
            # Process new takedown request
            result = handler.process_takedown_request(takedown_request)

            if result['success']:
                return {
                    'statusCode': 201,
                    'body': json.dumps({
                        'message': 'Takedown request created successfully',
                        'takedown_id': result['takedown_record']['takedown_id'],
                        'priority': result['takedown_record']['priority'],
                        'expected_resolution': result['takedown_record']['expected_resolution'],
                        'warnings': result.get('warnings', [])
                    })
                }
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'Invalid takedown request',
                        'details': result['errors'],
                        'warnings': result.get('warnings', [])
                    })
                }

        elif action == 'status':
            # Handle status check requests
            takedown_id = event.get('takedown_id')
            if not takedown_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'Takedown ID required for status check'
                    })
                }

            # In production, would query database for actual status
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'takedown_id': takedown_id,
                    'status': 'PENDING_REVIEW',
                    'message': 'Takedown request is being reviewed'
                })
            }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown action: {action}'
                })
            }

    except Exception as e:
        logger.error(f"Error in takedown handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }