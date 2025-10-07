"""
Interstate Commerce Monitor Lambda Function

This function monitors activities that cross state lines to ensure compliance
with federal interstate commerce regulations and identify potential violations.

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
cloudwatch = boto3.client('cloudwatch')

# Configuration
COMMERCE_TABLE = os.environ.get('COMMERCE_TABLE', 'aeims-interstate-commerce')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
RISK_THRESHOLD = float(os.environ.get('RISK_THRESHOLD', '0.7'))

class InterstateCommerceMonitor:
    """Main class for interstate commerce monitoring"""

    def __init__(self):
        self.table = dynamodb.Table(COMMERCE_TABLE)

        self.interstate_indicators = [
            r'\b(?:cross\s+state|different\s+state|out\s+of\s+state)\b',
            r'\b(?:travel\s+to|meet\s+in|going\s+to)\s+\w+\s+(?:state|city)\b',
            r'\b(?:ship|send|mail)\s+(?:to|from)\s+\w+\s+state\b',
            r'\b(?:jurisdiction|federal|interstate)\b'
        ]

        self.commercial_indicators = [
            r'\b(?:payment|money|cash|fee|charge)\b',
            r'\b(?:business|commercial|service|transaction)\b',
            r'\b(?:buy|sell|purchase|trade)\b'
        ]

    def analyze_interstate_activity(self, activity_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze activity for interstate commerce indicators"""
        try:
            analysis = {
                'interstate_risk_score': 0.0,
                'commerce_detected': False,
                'interstate_detected': False,
                'risk_indicators': [],
                'regulatory_concerns': [],
                'jurisdictional_issues': []
            }

            content = activity_data.get('content', '')
            location_data = activity_data.get('location_data', {})
            transaction_data = activity_data.get('transaction_data', {})

            # Check for interstate indicators in content
            interstate_matches = 0
            for pattern in self.interstate_indicators:
                if re.search(pattern, content, re.IGNORECASE):
                    interstate_matches += 1

            if interstate_matches > 0:
                analysis['interstate_detected'] = True
                analysis['interstate_risk_score'] += interstate_matches * 0.2

            # Check for commercial indicators
            commercial_matches = 0
            for pattern in self.commercial_indicators:
                if re.search(pattern, content, re.IGNORECASE):
                    commercial_matches += 1

            if commercial_matches > 0:
                analysis['commerce_detected'] = True
                analysis['interstate_risk_score'] += commercial_matches * 0.15

            # Analyze location data for interstate activity
            if location_data:
                origin_state = location_data.get('origin_state')
                destination_state = location_data.get('destination_state')

                if origin_state and destination_state and origin_state != destination_state:
                    analysis['interstate_detected'] = True
                    analysis['jurisdictional_issues'].append('multi_state_activity')
                    analysis['interstate_risk_score'] += 0.3

            # Analyze transaction data
            if transaction_data:
                if transaction_data.get('cross_state', False):
                    analysis['interstate_detected'] = True
                    analysis['interstate_risk_score'] += 0.4

            # Final risk assessment
            if analysis['interstate_detected'] and analysis['commerce_detected']:
                analysis['interstate_risk_score'] += 0.2
                analysis['regulatory_concerns'].append('interstate_commerce_regulation')

            analysis['interstate_risk_score'] = min(1.0, analysis['interstate_risk_score'])

            return analysis

        except Exception as e:
            logger.error(f"Interstate commerce analysis error: {str(e)}")
            raise

    def store_commerce_record(self, activity_data: Dict[str, Any], analysis_result: Dict[str, Any]) -> bool:
        """Store interstate commerce monitoring record"""
        try:
            item = {
                'record_id': f"{activity_data.get('user_id', 'unknown')}_{int(datetime.now(timezone.utc).timestamp())}",
                'user_id': activity_data.get('user_id'),
                'activity_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'interstate_detected': analysis_result['interstate_detected'],
                'commerce_detected': analysis_result['commerce_detected'],
                'risk_score': analysis_result['interstate_risk_score'],
                'regulatory_concerns': analysis_result['regulatory_concerns'],
                'jurisdictional_issues': analysis_result['jurisdictional_issues'],
                'activity_type': activity_data.get('activity_type', 'unknown'),
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=365)).timestamp())
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Commerce record storage error: {str(e)}")
            return False

    def send_commerce_alert(self, activity_data: Dict[str, Any], analysis_result: Dict[str, Any]) -> bool:
        """Send alert for interstate commerce violations"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            alert = {
                'alert_type': 'INTERSTATE_COMMERCE_DETECTED',
                'user_id': activity_data.get('user_id'),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'risk_score': analysis_result['interstate_risk_score'],
                'interstate_detected': analysis_result['interstate_detected'],
                'commerce_detected': analysis_result['commerce_detected'],
                'regulatory_concerns': analysis_result['regulatory_concerns'],
                'severity': 'HIGH' if analysis_result['interstate_risk_score'] > 0.8 else 'MEDIUM'
            }

            sns.publish(
                TopicArn=ALERT_SNS_TOPIC,
                Subject="Interstate Commerce Activity Detected",
                Message=json.dumps(alert, indent=2)
            )

            return True

        except Exception as e:
            logger.error(f"Commerce alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for interstate commerce monitoring"""
    try:
        logger.info("Processing interstate commerce monitoring request")

        required_fields = ['user_id', 'activity_data']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        activity_data = event['activity_data']
        activity_data['user_id'] = event['user_id']

        monitor = InterstateCommerceMonitor()
        analysis_result = monitor.analyze_interstate_activity(activity_data)

        stored = monitor.store_commerce_record(activity_data, analysis_result)

        alert_sent = False
        if analysis_result['interstate_risk_score'] >= RISK_THRESHOLD:
            alert_sent = monitor.send_commerce_alert(activity_data, analysis_result)

        response = {
            'statusCode': 200,
            'body': {
                'monitored': True,
                'interstate_detected': analysis_result['interstate_detected'],
                'commerce_detected': analysis_result['commerce_detected'],
                'risk_score': analysis_result['interstate_risk_score'],
                'alert_sent': alert_sent,
                'stored': stored,
                'timestamp': datetime.now(timezone.utc).isoformat()
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
        logger.error(f"Interstate commerce monitor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Monitoring failed'}
        }