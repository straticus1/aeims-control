"""
Sex trafficking content detection Lambda function
Analyzes content for indicators of sex trafficking and exploitation
"""
import json
import re
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class SexTraffickingDetector:
    def __init__(self):
        # Keywords and patterns associated with sex trafficking
        self.trafficking_keywords = [
            'escort', 'massage', 'companionship', 'full service',
            'outcall', 'incall', 'sensual', 'discreet', 'young',
            'fresh', 'new in town', 'barely legal', 'tight'
        ]

        # Suspicious patterns
        self.suspicious_patterns = [
            r'\b(?:new\s+in\s+town|just\s+arrived)\b',
            r'\b(?:barely\s+legal|just\s+turned\s+18)\b',
            r'\b(?:no\s+limits|anything\s+goes)\b',
            r'\$\d+.*(?:hour|hr|30\s*min)',
            r'\b(?:greek|gfe|pse|bbfs|cim|cof)\b'
        ]

    def analyze_content(self, content: str) -> Dict[str, Any]:
        """Analyze content for sex trafficking indicators"""
        content_lower = content.lower()

        keyword_matches = []
        pattern_matches = []
        risk_score = 0

        # Check for trafficking keywords
        for keyword in self.trafficking_keywords:
            if keyword in content_lower:
                keyword_matches.append(keyword)
                risk_score += 1

        # Check for suspicious patterns
        for pattern in self.suspicious_patterns:
            matches = re.findall(pattern, content_lower, re.IGNORECASE)
            if matches:
                pattern_matches.extend(matches)
                risk_score += 2

        # Additional risk factors
        if re.search(r'\b(?:call|text|dm)\s+(?:me|us)\b', content_lower):
            risk_score += 1

        if re.search(r'\b(?:cash|venmo|paypal|zelle)\s+only\b', content_lower):
            risk_score += 1

        # Determine risk level
        if risk_score >= 5:
            risk_level = 'HIGH'
        elif risk_score >= 3:
            risk_level = 'MEDIUM'
        elif risk_score >= 1:
            risk_level = 'LOW'
        else:
            risk_level = 'NONE'

        return {
            'risk_level': risk_level,
            'risk_score': risk_score,
            'keyword_matches': keyword_matches,
            'pattern_matches': pattern_matches,
            'content_length': len(content),
            'analysis_timestamp': str(datetime.utcnow())
        }

def lambda_handler(event, context):
    """Main Lambda handler"""
    try:
        # Extract content from event
        content = event.get('content', '')
        source = event.get('source', 'unknown')
        user_id = event.get('user_id', 'anonymous')

        if not content:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No content provided for analysis'
                })
            }

        # Initialize detector and analyze
        detector = SexTraffickingDetector()
        analysis_result = detector.analyze_content(content)

        # Add metadata
        analysis_result.update({
            'source': source,
            'user_id': user_id,
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        })

        # Log high-risk detections
        if analysis_result['risk_level'] in ['HIGH', 'MEDIUM']:
            logger.warning(f"Potential trafficking content detected: "
                         f"Risk={analysis_result['risk_level']}, "
                         f"Score={analysis_result['risk_score']}, "
                         f"User={user_id}, Source={source}")

        return {
            'statusCode': 200,
            'body': json.dumps(analysis_result)
        }

    except Exception as e:
        logger.error(f"Error in sex trafficking detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }