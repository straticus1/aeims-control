import json
import boto3
import logging
from datetime import datetime
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Florida Obscenity Filter Lambda Function
    Filters content according to Florida obscenity laws
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"

    # Initialize AWS clients
    dynamodb = boto3.resource('dynamodb')

    try:
        logger.info(f"Processing obscenity filter for {project_name} in {environment}")

        # Parse incoming content
        content_id = event.get('content_id', 'unknown')
        content_type = event.get('content_type', 'text')
        content_data = event.get('content', '')
        user_id = event.get('user_id', 'unknown')

        # Perform obscenity analysis
        filter_result = analyze_content(content_data, content_type)

        # Log the filtering action
        table_name = f"{project_name}-florida-obscenity-logs-{environment}"
        table = dynamodb.Table(table_name)

        log_item = {
            'log_id': f"{content_id}-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
            'timestamp': datetime.utcnow().isoformat(),
            'content_id': content_id,
            'content_type': content_type,
            'user_id': user_id,
            'filter_result': filter_result['status'],
            'violations_found': filter_result.get('violations', []),
            'confidence_score': filter_result.get('confidence', 0.0),
            'environment': environment,
            'project': project_name
        }

        table.put_item(Item=log_item)

        response_data = {
            'content_id': content_id,
            'approved': filter_result['status'] == 'approved',
            'status': filter_result['status'],
            'violations': filter_result.get('violations', []),
            'confidence': filter_result.get('confidence', 0.0),
            'timestamp': datetime.utcnow().isoformat()
        }

        logger.info(f"Obscenity filter completed for {content_id}: {filter_result['status']}")

        return {
            'statusCode': 200,
            'body': json.dumps(response_data)
        }

    except Exception as e:
        logger.error(f"Obscenity filter failed: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Obscenity filter failed',
                'error': str(e),
                'approved': False,  # Fail secure
                'environment': environment,
                'project': project_name
            })
        }

def analyze_content(content, content_type):
    """Analyze content for obscenity according to Florida standards"""

    violations = []
    confidence = 0.0

    # Florida Obscenity Standards (simplified implementation)
    # In production, this would use more sophisticated ML models

    if content_type == 'text':
        # Check for explicit text patterns
        explicit_patterns = [
            r'\b(explicit_term_1|explicit_term_2)\b',  # Replace with actual terms
            r'\b(inappropriate_phrase)\b'
        ]

        for pattern in explicit_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                violations.append({
                    'type': 'explicit_language',
                    'pattern': pattern,
                    'severity': 'high'
                })

        # Check for potential minor-related content (prohibited)
        minor_patterns = [
            r'\b(teen|young|minor)\b.*\b(explicit|sexual)\b',
            r'\b(underage|minor)\b'
        ]

        for pattern in minor_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                violations.append({
                    'type': 'minor_related',
                    'pattern': pattern,
                    'severity': 'critical'
                })

    elif content_type in ['image', 'video']:
        # For media content, this would integrate with AWS Rekognition
        # or other content moderation services
        violations.append({
            'type': 'media_review_required',
            'severity': 'medium',
            'note': 'Manual review required for media content'
        })

    # Calculate confidence score
    if violations:
        critical_violations = [v for v in violations if v.get('severity') == 'critical']
        high_violations = [v for v in violations if v.get('severity') == 'high']

        if critical_violations:
            confidence = 0.95
            status = 'rejected'
        elif high_violations:
            confidence = 0.75
            status = 'flagged'
        else:
            confidence = 0.50
            status = 'review_required'
    else:
        confidence = 0.90
        status = 'approved'

    return {
        'status': status,
        'violations': violations,
        'confidence': confidence
    }