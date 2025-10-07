"""
FOSTA Communication Monitor Lambda Function

This function monitors real-time communications for patterns that may indicate
sex trafficking or other violations of FOSTA-SESTA regulations.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
import re
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os
import hashlib

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
comprehend = boto3.client('comprehend')
cloudwatch = boto3.client('cloudwatch')

# Configuration
COMMUNICATION_TABLE = os.environ.get('COMMUNICATION_TABLE', 'aeims-communications')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
RISK_THRESHOLD = float(os.environ.get('RISK_THRESHOLD', '0.7'))
PATTERN_LOOKBACK_HOURS = int(os.environ.get('PATTERN_LOOKBACK_HOURS', '24'))

class FOSTACommunicationMonitor:
    """Main class for FOSTA communication monitoring"""

    def __init__(self):
        self.table = dynamodb.Table(COMMUNICATION_TABLE)

        # Suspicious communication patterns
        self.trafficking_indicators = [
            # Location/movement patterns
            r'\b(?:new\s+in\s+town|just\s+arrived|traveling)\b',
            r'\b(?:hotel|motel|room\s+\d+)\b',
            r'\b(?:airport|station|downtown)\b',

            # Financial indicators
            r'\b(?:cash\s+only|no\s+credit|upfront|deposit)\b',
            r'\b(?:donation|gift|roses|\$\d+)\b',
            r'\b(?:generous|wealthy|upscale)\b',

            # Service indicators
            r'\b(?:full\s+service|anything\s+goes|no\s+limits)\b',
            r'\b(?:private|discrete|confidential)\b',
            r'\b(?:young|teen|barely|fresh)\b',

            # Control/coercion indicators
            r'\b(?:manager|boss|handler|driver)\b',
            r'\b(?:must\s+work|quota|debt)\b',
            r'\b(?:cant\s+leave|stuck|trapped)\b'
        ]

        self.urgency_keywords = [
            'emergency', 'urgent', 'help', 'trapped', 'cant leave',
            'forced', 'scared', 'danger', 'police', 'rescue'
        ]

        self.suspicious_phrases = [
            'no questions asked',
            'discretion guaranteed',
            'what happens here stays here',
            'special services available',
            'private entertainment',
            'companionship services'
        ]

    def analyze_message_content(self, message: str, sender_id: str, recipient_id: str) -> Dict[str, Any]:
        """Analyze individual message for FOSTA violations"""
        try:
            analysis = {
                'risk_score': 0.0,
                'risk_indicators': [],
                'trafficking_patterns': [],
                'urgency_level': 'LOW',
                'requires_intervention': False,
                'flagged_content': []
            }

            message_lower = message.lower()

            # Check trafficking indicator patterns
            pattern_matches = 0
            for pattern in self.trafficking_indicators:
                matches = re.finditer(pattern, message_lower, re.IGNORECASE)
                for match in matches:
                    pattern_matches += 1
                    analysis['trafficking_patterns'].append({
                        'pattern': pattern,
                        'match': match.group(),
                        'category': self._categorize_pattern(pattern)
                    })

            # Calculate base risk score from patterns
            if pattern_matches > 0:
                analysis['risk_score'] = min(0.9, pattern_matches * 0.2)

            # Check for urgency keywords
            urgency_count = 0
            for keyword in self.urgency_keywords:
                if keyword in message_lower:
                    urgency_count += 1
                    analysis['risk_indicators'].append(f'urgency_keyword: {keyword}')

            if urgency_count > 0:
                analysis['urgency_level'] = 'HIGH' if urgency_count > 2 else 'MEDIUM'
                analysis['risk_score'] += urgency_count * 0.3
                analysis['requires_intervention'] = urgency_count > 1

            # Check suspicious phrases
            phrase_matches = 0
            for phrase in self.suspicious_phrases:
                if phrase in message_lower:
                    phrase_matches += 1
                    analysis['flagged_content'].append(phrase)

            if phrase_matches > 0:
                analysis['risk_score'] += phrase_matches * 0.25

            # Use AWS Comprehend for sentiment analysis
            try:
                if len(message) > 10:  # Only analyze substantial messages
                    sentiment_response = comprehend.detect_sentiment(
                        Text=message[:1000],  # Limit for Comprehend
                        LanguageCode='en'
                    )

                    # Check for concerning sentiment patterns
                    if sentiment_response['Sentiment'] == 'NEGATIVE':
                        negative_score = sentiment_response['SentimentScore']['Negative']
                        if negative_score > 0.8:
                            analysis['risk_score'] += 0.2
                            analysis['risk_indicators'].append('high_negative_sentiment')

            except Exception as e:
                logger.warning(f"Sentiment analysis failed: {str(e)}")

            # Cap risk score
            analysis['risk_score'] = min(1.0, analysis['risk_score'])

            return analysis

        except Exception as e:
            logger.error(f"Message analysis error: {str(e)}")
            raise

    def _categorize_pattern(self, pattern: str) -> str:
        """Categorize the type of trafficking pattern"""
        if any(word in pattern for word in ['cash', 'donation', 'gift', '$']):
            return 'financial'
        elif any(word in pattern for word in ['hotel', 'room', 'airport', 'travel']):
            return 'location'
        elif any(word in pattern for word in ['service', 'private', 'discrete']):
            return 'commercial'
        elif any(word in pattern for word in ['manager', 'boss', 'must', 'debt']):
            return 'control'
        else:
            return 'general'

    def get_communication_history(self, user_id: str, hours: int = 24) -> List[Dict]:
        """Get recent communication history for pattern analysis"""
        try:
            cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
            cutoff_timestamp = int(cutoff_time.timestamp())

            # Query recent communications
            response = self.table.scan(
                FilterExpression='(sender_id = :uid OR recipient_id = :uid) AND message_timestamp > :cutoff',
                ExpressionAttributeValues={
                    ':uid': user_id,
                    ':cutoff': cutoff_timestamp
                }
            )

            return response.get('Items', [])

        except Exception as e:
            logger.error(f"History retrieval error: {str(e)}")
            return []

    def analyze_communication_patterns(self, user_id: str, current_message: Dict) -> Dict[str, Any]:
        """Analyze broader communication patterns for trafficking indicators"""
        try:
            history = self.get_communication_history(user_id, PATTERN_LOOKBACK_HOURS)

            pattern_analysis = {
                'pattern_risk_score': 0.0,
                'behavioral_indicators': [],
                'escalation_detected': False,
                'frequency_anomaly': False
            }

            if not history:
                return pattern_analysis

            # Analyze message frequency
            message_count = len(history)
            avg_daily_messages = message_count / (PATTERN_LOOKBACK_HOURS / 24)

            if avg_daily_messages > 50:  # High frequency threshold
                pattern_analysis['frequency_anomaly'] = True
                pattern_analysis['behavioral_indicators'].append('high_message_frequency')
                pattern_analysis['pattern_risk_score'] += 0.3

            # Analyze unique contacts
            contacts = set()
            for msg in history:
                if msg.get('sender_id') == user_id:
                    contacts.add(msg.get('recipient_id', ''))
                else:
                    contacts.add(msg.get('sender_id', ''))

            if len(contacts) > 10:  # Many different contacts
                pattern_analysis['behavioral_indicators'].append('multiple_contacts')
                pattern_analysis['pattern_risk_score'] += 0.2

            # Check for escalating risk scores over time
            recent_risks = []
            for msg in sorted(history, key=lambda x: x.get('message_timestamp', 0)):
                if 'risk_score' in msg:
                    recent_risks.append(float(msg['risk_score']))

            if len(recent_risks) >= 3:
                recent_avg = sum(recent_risks[-3:]) / 3
                earlier_avg = sum(recent_risks[:-3]) / max(len(recent_risks) - 3, 1)

                if recent_avg > earlier_avg * 1.5:  # 50% increase
                    pattern_analysis['escalation_detected'] = True
                    pattern_analysis['pattern_risk_score'] += 0.4

            return pattern_analysis

        except Exception as e:
            logger.error(f"Pattern analysis error: {str(e)}")
            return {
                'pattern_risk_score': 0.0,
                'behavioral_indicators': ['analysis_error'],
                'escalation_detected': False,
                'frequency_anomaly': False
            }

    def store_communication_record(self, message_data: Dict, analysis_result: Dict) -> bool:
        """Store communication record with analysis results"""
        try:
            item = {
                'message_id': message_data['message_id'],
                'sender_id': message_data['sender_id'],
                'recipient_id': message_data['recipient_id'],
                'message_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'message_hash': hashlib.sha256(message_data['content'].encode()).hexdigest(),
                'risk_score': analysis_result['risk_score'],
                'risk_indicators': analysis_result['risk_indicators'],
                'trafficking_patterns': analysis_result['trafficking_patterns'],
                'urgency_level': analysis_result['urgency_level'],
                'requires_intervention': analysis_result['requires_intervention'],
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=90)).timestamp())  # 90-day retention
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Storage error: {str(e)}")
            return False

    def send_alert(self, message_data: Dict, analysis_result: Dict, pattern_analysis: Dict) -> bool:
        """Send alert for high-risk communications"""
        try:
            if not ALERT_SNS_TOPIC:
                logger.warning("No alert SNS topic configured")
                return False

            total_risk = analysis_result['risk_score'] + pattern_analysis['pattern_risk_score']

            alert = {
                'alert_type': 'FOSTA_COMMUNICATION_VIOLATION',
                'message_id': message_data['message_id'],
                'sender_id': message_data['sender_id'],
                'recipient_id': message_data['recipient_id'],
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'risk_score': analysis_result['risk_score'],
                'pattern_risk_score': pattern_analysis['pattern_risk_score'],
                'total_risk_score': total_risk,
                'urgency_level': analysis_result['urgency_level'],
                'requires_intervention': analysis_result['requires_intervention'],
                'trafficking_patterns': analysis_result['trafficking_patterns'],
                'behavioral_indicators': pattern_analysis['behavioral_indicators'],
                'escalation_detected': pattern_analysis['escalation_detected'],
                'severity': 'CRITICAL' if total_risk > 0.8 else 'HIGH' if total_risk > 0.6 else 'MEDIUM'
            }

            sns.publish(
                TopicArn=ALERT_SNS_TOPIC,
                Subject=f"FOSTA Communication Alert - Risk Score: {total_risk:.2f}",
                Message=json.dumps(alert, indent=2)
            )

            # Send CloudWatch metric
            cloudwatch.put_metric_data(
                Namespace='AEIMS/FOSTA/Communications',
                MetricData=[
                    {
                        'MetricName': 'HighRiskCommunications',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'Severity',
                                'Value': alert['severity']
                            }
                        ]
                    }
                ]
            )

            logger.info(f"FOSTA communication alert sent: {message_data['message_id']}")
            return True

        except Exception as e:
            logger.error(f"Alert sending error: {str(e)}")
            return False


def lambda_handler(event, context):
    """
    Lambda handler for FOSTA communication monitoring

    Expected event structure:
    {
        "message_id": "unique_message_id",
        "sender_id": "sender_user_id",
        "recipient_id": "recipient_user_id",
        "content": "message_content",
        "timestamp": "iso_timestamp",
        "platform": "chat|messaging|forum"
    }
    """
    try:
        logger.info(f"Processing FOSTA communication monitor request: {event.get('message_id', 'unknown')}")

        # Validate input
        required_fields = ['message_id', 'sender_id', 'recipient_id', 'content']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        message_data = {
            'message_id': event['message_id'],
            'sender_id': event['sender_id'],
            'recipient_id': event['recipient_id'],
            'content': event['content'],
            'timestamp': event.get('timestamp', datetime.now(timezone.utc).isoformat()),
            'platform': event.get('platform', 'unknown')
        }

        # Initialize monitor
        monitor = FOSTACommunicationMonitor()

        # Analyze message content
        content_analysis = monitor.analyze_message_content(
            message_data['content'],
            message_data['sender_id'],
            message_data['recipient_id']
        )

        # Analyze communication patterns
        pattern_analysis = monitor.analyze_communication_patterns(
            message_data['sender_id'],
            message_data
        )

        # Calculate total risk
        total_risk = content_analysis['risk_score'] + pattern_analysis['pattern_risk_score']

        # Store communication record
        stored = monitor.store_communication_record(message_data, content_analysis)

        # Send alert if necessary
        alert_sent = False
        if total_risk >= RISK_THRESHOLD or content_analysis['requires_intervention']:
            alert_sent = monitor.send_alert(message_data, content_analysis, pattern_analysis)

        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'message_id': message_data['message_id'],
                'monitored': True,
                'risk_score': content_analysis['risk_score'],
                'pattern_risk_score': pattern_analysis['pattern_risk_score'],
                'total_risk_score': total_risk,
                'urgency_level': content_analysis['urgency_level'],
                'requires_intervention': content_analysis['requires_intervention'],
                'alert_sent': alert_sent,
                'stored': stored,
                'trafficking_patterns_detected': len(content_analysis['trafficking_patterns']) > 0,
                'behavioral_anomalies': pattern_analysis['behavioral_indicators'],
                'escalation_detected': pattern_analysis['escalation_detected'],
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_framework': 'FOSTA-SESTA'
            }
        }

        logger.info(f"FOSTA communication monitoring completed: {message_data['message_id']}")
        return response

    except ValueError as e:
        logger.error(f"Input validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': {
                'error': 'Invalid input',
                'message': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }

    except Exception as e:
        logger.error(f"FOSTA communication monitor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal server error',
                'message': 'Communication monitoring failed',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }