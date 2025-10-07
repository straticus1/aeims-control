"""
Anti-Trafficking Monitor Lambda Function

This function implements comprehensive monitoring for human trafficking indicators
across the platform, using advanced pattern recognition and behavioral analysis
to detect potential trafficking activities.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
import re
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional, Tuple
import os
import hashlib
import numpy as np

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
comprehend = boto3.client('comprehend')
rekognition = boto3.client('rekognition')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

# Configuration
TRAFFICKING_TABLE = os.environ.get('TRAFFICKING_TABLE', 'aeims-trafficking-monitoring')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
RISK_THRESHOLD = float(os.environ.get('RISK_THRESHOLD', '0.75'))
ANALYSIS_WINDOW_HOURS = int(os.environ.get('ANALYSIS_WINDOW_HOURS', '72'))

class AntiTraffickingMonitor:
    """Main class for anti-trafficking monitoring operations"""

    def __init__(self):
        self.table = dynamodb.Table(TRAFFICKING_TABLE)

        # Trafficking indicator patterns
        self.trafficking_patterns = {
            # Recruitment patterns
            'recruitment': [
                r'\b(?:modeling|entertainment|travel)\s+(?:opportunity|job|work)\b',
                r'\b(?:easy\s+money|quick\s+cash|big\s+money)\b',
                r'\b(?:no\s+experience\s+required|immediate\s+start)\b',
                r'\b(?:help\s+with\s+(?:visa|papers|documents))\b',
                r'\b(?:room\s+and\s+board\s+provided|housing\s+included)\b'
            ],

            # Transportation patterns
            'transportation': [
                r'\b(?:bus\s+ticket|plane\s+ticket|travel\s+arrangements)\b',
                r'\b(?:pick\s+you\s+up|driver\s+will\s+get\s+you)\b',
                r'\b(?:meet\s+at\s+(?:airport|station|bus\s+stop))\b',
                r'\b(?:out\s+of\s+state|different\s+city|cross\s+country)\b'
            ],

            # Control patterns
            'control': [
                r'\b(?:keep\s+your\s+(?:phone|id|documents))\b',
                r'\b(?:dont?\s+(?:talk\s+to|trust)\s+(?:police|anyone))\b',
                r'\b(?:owe\s+(?:me|us)\s+money|pay\s+back\s+debt)\b',
                r'\b(?:work\s+until\s+you\s+pay|quota\s+to\s+meet)\b',
                r'\b(?:cant?\s+leave\s+until|not\s+allowed\s+to\s+go)\b'
            ],

            # Exploitation patterns
            'exploitation': [
                r'\b(?:clients?\s+(?:pay|want|expect))\b',
                r'\b(?:service\s+(?:men|customers|clients?))\b',
                r'\b(?:work\s+(?:long\s+hours|all\s+day|24/?7))\b',
                r'\b(?:no\s+(?:breaks|days\s+off|rest))\b',
                r'\b(?:keep\s+(?:working|going)\s+until)\b'
            ],

            # Vulnerability patterns
            'vulnerability': [
                r'\b(?:nowhere\s+(?:to\s+go|else\s+to\s+turn))\b',
                r'\b(?:family\s+(?:problems|kicked\s+me\s+out))\b',
                r'\b(?:need\s+(?:money|help)\s+(?:badly|desperately))\b',
                r'\b(?:homeless|no\s+place\s+to\s+stay)\b',
                r'\b(?:aged?\s+out\s+of\s+(?:foster|care))\b'
            ]
        }

        # High-risk keywords for immediate escalation
        self.immediate_risk_keywords = [
            'trapped', 'cant leave', 'forced', 'scared', 'help me',
            'being held', 'not allowed', 'take my phone', 'keep my id',
            'owe money', 'debt', 'quota', 'work all day', 'no choice'
        ]

        # Geographic risk factors
        self.high_risk_locations = [
            'truck stops', 'massage parlors', 'strip clubs', 'hotels near airports',
            'border areas', 'agricultural areas', 'construction sites'
        ]

        # Behavioral indicators
        self.behavioral_indicators = {
            'communication_patterns': [
                'irregular_timing',
                'location_inconsistencies',
                'controlled_responses',
                'fear_indicators',
                'multiple_handler_contacts'
            ],
            'movement_patterns': [
                'frequent_location_changes',
                'transportation_dependency',
                'restricted_movement',
                'isolation_indicators'
            ],
            'financial_patterns': [
                'no_direct_payment',
                'debt_bondage_indicators',
                'quota_pressure',
                'financial_control'
            ]
        }

    def analyze_content_for_trafficking(self, content: str, content_type: str = 'text') -> Dict[str, Any]:
        """Analyze content for trafficking indicators"""
        try:
            analysis = {
                'trafficking_risk_score': 0.0,
                'detected_patterns': {},
                'risk_categories': [],
                'immediate_intervention_required': False,
                'confidence_level': 'low',
                'flagged_content': []
            }

            content_lower = content.lower()

            # Check immediate risk keywords first
            immediate_risks = []
            for keyword in self.immediate_risk_keywords:
                if keyword in content_lower:
                    immediate_risks.append(keyword)

            if immediate_risks:
                analysis['immediate_intervention_required'] = True
                analysis['trafficking_risk_score'] = 0.9
                analysis['flagged_content'] = immediate_risks
                analysis['confidence_level'] = 'high'
                analysis['risk_categories'].append('immediate_danger')

            # Analyze trafficking patterns by category
            total_pattern_score = 0.0
            for category, patterns in self.trafficking_patterns.items():
                category_matches = []
                category_score = 0.0

                for pattern in patterns:
                    matches = re.finditer(pattern, content, re.IGNORECASE)
                    for match in matches:
                        category_matches.append({
                            'pattern': pattern,
                            'match': match.group(),
                            'position': match.span()
                        })
                        category_score += 0.15  # Each pattern match adds 15% risk

                if category_matches:
                    analysis['detected_patterns'][category] = {
                        'matches': category_matches,
                        'score': min(category_score, 1.0),
                        'count': len(category_matches)
                    }
                    total_pattern_score += category_score
                    analysis['risk_categories'].append(category)

            # Update risk score if not already at high risk
            if not analysis['immediate_intervention_required']:
                analysis['trafficking_risk_score'] = min(total_pattern_score, 1.0)

            # Determine confidence level
            if analysis['trafficking_risk_score'] > 0.8:
                analysis['confidence_level'] = 'high'
            elif analysis['trafficking_risk_score'] > 0.5:
                analysis['confidence_level'] = 'medium'
            else:
                analysis['confidence_level'] = 'low'

            # Use AWS Comprehend for additional analysis
            if len(content) > 20 and not analysis['immediate_intervention_required']:
                try:
                    sentiment_response = comprehend.detect_sentiment(
                        Text=content[:1000],
                        LanguageCode='en'
                    )

                    # Check for distress patterns in sentiment
                    if sentiment_response['Sentiment'] == 'NEGATIVE':
                        negative_score = sentiment_response['SentimentScore']['Negative']
                        if negative_score > 0.8:
                            analysis['trafficking_risk_score'] += 0.2
                            analysis['risk_categories'].append('emotional_distress')

                    # Detect entities that might indicate trafficking
                    entities_response = comprehend.detect_entities(
                        Text=content[:1000],
                        LanguageCode='en'
                    )

                    for entity in entities_response['Entities']:
                        if entity['Type'] == 'LOCATION':
                            location = entity['Text'].lower()
                            if any(risk_loc in location for risk_loc in self.high_risk_locations):
                                analysis['trafficking_risk_score'] += 0.15
                                analysis['risk_categories'].append('high_risk_location')

                except Exception as e:
                    logger.warning(f"Comprehend analysis failed: {str(e)}")

            return analysis

        except Exception as e:
            logger.error(f"Trafficking content analysis error: {str(e)}")
            raise

    def analyze_behavioral_patterns(self, user_id: str, timeframe_hours: int = 72) -> Dict[str, Any]:
        """Analyze user behavioral patterns for trafficking indicators"""
        try:
            behavioral_analysis = {
                'risk_score': 0.0,
                'indicators': [],
                'pattern_anomalies': [],
                'movement_analysis': {},
                'communication_analysis': {},
                'financial_analysis': {}
            }

            # Get user activity history
            cutoff_time = datetime.now(timezone.utc) - timedelta(hours=timeframe_hours)
            cutoff_timestamp = int(cutoff_time.timestamp())

            try:
                response = self.table.scan(
                    FilterExpression='user_id = :uid AND activity_timestamp > :cutoff',
                    ExpressionAttributeValues={
                        ':uid': user_id,
                        ':cutoff': cutoff_timestamp
                    }
                )
                activities = response.get('Items', [])
            except Exception as e:
                logger.warning(f"Could not retrieve user activities: {str(e)}")
                activities = []

            if not activities:
                return behavioral_analysis

            # Analyze communication patterns
            comm_analysis = self._analyze_communication_patterns(activities)
            behavioral_analysis['communication_analysis'] = comm_analysis
            behavioral_analysis['risk_score'] += comm_analysis.get('risk_contribution', 0.0)

            # Analyze movement/location patterns
            movement_analysis = self._analyze_movement_patterns(activities)
            behavioral_analysis['movement_analysis'] = movement_analysis
            behavioral_analysis['risk_score'] += movement_analysis.get('risk_contribution', 0.0)

            # Analyze financial transaction patterns
            financial_analysis = self._analyze_financial_patterns(activities)
            behavioral_analysis['financial_analysis'] = financial_analysis
            behavioral_analysis['risk_score'] += financial_analysis.get('risk_contribution', 0.0)

            # Compile indicators
            all_indicators = (
                comm_analysis.get('indicators', []) +
                movement_analysis.get('indicators', []) +
                financial_analysis.get('indicators', [])
            )
            behavioral_analysis['indicators'] = all_indicators

            # Cap risk score
            behavioral_analysis['risk_score'] = min(behavioral_analysis['risk_score'], 1.0)

            return behavioral_analysis

        except Exception as e:
            logger.error(f"Behavioral pattern analysis error: {str(e)}")
            return {
                'risk_score': 0.0,
                'indicators': ['analysis_error'],
                'error': str(e)
            }

    def _analyze_communication_patterns(self, activities: List[Dict]) -> Dict[str, Any]:
        """Analyze communication patterns for trafficking indicators"""
        comm_analysis = {
            'risk_contribution': 0.0,
            'indicators': [],
            'unusual_patterns': []
        }

        communication_activities = [a for a in activities if a.get('activity_type') == 'communication']

        if not communication_activities:
            return comm_analysis

        # Check for irregular timing patterns
        timestamps = [int(a.get('activity_timestamp', 0)) for a in communication_activities]
        if timestamps:
            time_intervals = np.diff(sorted(timestamps))
            if len(time_intervals) > 3:
                # Check for very irregular patterns (high variance)
                variance = np.var(time_intervals)
                if variance > 3600 * 3600:  # High variance in timing
                    comm_analysis['indicators'].append('irregular_communication_timing')
                    comm_analysis['risk_contribution'] += 0.1

        # Check for controlled response patterns
        response_times = []
        for activity in communication_activities:
            if 'response_time' in activity:
                response_times.append(activity['response_time'])

        if response_times and len(response_times) > 5:
            avg_response_time = np.mean(response_times)
            if avg_response_time < 30:  # Very quick responses might indicate control
                comm_analysis['indicators'].append('unusually_quick_responses')
                comm_analysis['risk_contribution'] += 0.15

        # Check for multiple handler contacts
        unique_contacts = set()
        for activity in communication_activities:
            contact = activity.get('contact_id')
            if contact:
                unique_contacts.add(contact)

        if len(unique_contacts) > 10:  # Many different contacts
            comm_analysis['indicators'].append('excessive_contact_diversity')
            comm_analysis['risk_contribution'] += 0.2

        return comm_analysis

    def _analyze_movement_patterns(self, activities: List[Dict]) -> Dict[str, Any]:
        """Analyze movement/location patterns for trafficking indicators"""
        movement_analysis = {
            'risk_contribution': 0.0,
            'indicators': [],
            'location_changes': 0
        }

        location_activities = [a for a in activities if a.get('location_data')]

        if not location_activities:
            return movement_analysis

        # Track location changes
        locations = []
        for activity in location_activities:
            location = activity.get('location_data', {})
            if location.get('city') or location.get('state'):
                locations.append(f"{location.get('city', '')},{location.get('state', '')}")

        unique_locations = set(locations)
        movement_analysis['location_changes'] = len(unique_locations)

        # Frequent location changes
        if len(unique_locations) > 5:  # More than 5 different locations
            movement_analysis['indicators'].append('frequent_location_changes')
            movement_analysis['risk_contribution'] += 0.25

        # Check for high-risk location types
        for activity in location_activities:
            location_type = activity.get('location_data', {}).get('venue_type', '')
            if any(risk_type in location_type.lower() for risk_type in self.high_risk_locations):
                movement_analysis['indicators'].append('high_risk_location_activity')
                movement_analysis['risk_contribution'] += 0.2
                break

        return movement_analysis

    def _analyze_financial_patterns(self, activities: List[Dict]) -> Dict[str, Any]:
        """Analyze financial patterns for trafficking indicators"""
        financial_analysis = {
            'risk_contribution': 0.0,
            'indicators': [],
            'transaction_patterns': {}
        }

        financial_activities = [a for a in activities if a.get('activity_type') == 'financial']

        if not financial_activities:
            return financial_analysis

        # Check for lack of direct payments
        direct_payments = [a for a in financial_activities if a.get('payment_method') == 'direct']
        if len(direct_payments) == 0 and len(financial_activities) > 3:
            financial_analysis['indicators'].append('no_direct_payments')
            financial_analysis['risk_contribution'] += 0.3

        # Check for debt indicators
        debt_activities = [a for a in financial_activities if 'debt' in str(a.get('description', '')).lower()]
        if debt_activities:
            financial_analysis['indicators'].append('debt_bondage_indicators')
            financial_analysis['risk_contribution'] += 0.4

        return financial_analysis

    def store_trafficking_assessment(self, user_id: str, assessment_data: Dict[str, Any]) -> bool:
        """Store trafficking risk assessment"""
        try:
            item = {
                'assessment_id': f"{user_id}_{int(datetime.now(timezone.utc).timestamp())}",
                'user_id': user_id,
                'assessment_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'content_risk_score': assessment_data.get('content_analysis', {}).get('trafficking_risk_score', 0.0),
                'behavioral_risk_score': assessment_data.get('behavioral_analysis', {}).get('risk_score', 0.0),
                'total_risk_score': assessment_data.get('total_risk_score', 0.0),
                'immediate_intervention': assessment_data.get('immediate_intervention_required', False),
                'detected_patterns': json.dumps(assessment_data.get('detected_patterns', {})),
                'behavioral_indicators': assessment_data.get('behavioral_indicators', []),
                'risk_categories': assessment_data.get('risk_categories', []),
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=180)).timestamp())  # 6-month retention
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Assessment storage error: {str(e)}")
            return False

    def send_trafficking_alert(self, user_id: str, assessment_data: Dict[str, Any]) -> bool:
        """Send alert for high-risk trafficking indicators"""
        try:
            if not ALERT_SNS_TOPIC:
                logger.warning("No alert SNS topic configured")
                return False

            total_risk = assessment_data.get('total_risk_score', 0.0)
            immediate_intervention = assessment_data.get('immediate_intervention_required', False)

            alert = {
                'alert_type': 'HUMAN_TRAFFICKING_RISK',
                'user_id': hashlib.sha256(user_id.encode()).hexdigest(),  # Hash for privacy
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'total_risk_score': total_risk,
                'immediate_intervention_required': immediate_intervention,
                'risk_categories': assessment_data.get('risk_categories', []),
                'behavioral_indicators': assessment_data.get('behavioral_indicators', []),
                'detected_patterns': list(assessment_data.get('detected_patterns', {}).keys()),
                'severity': 'CRITICAL' if immediate_intervention else 'HIGH' if total_risk > 0.8 else 'MEDIUM',
                'recommended_actions': self._generate_recommended_actions(assessment_data),
                'legal_requirements': 'Consider mandatory reporting under applicable laws'
            }

            sns.publish(
                TopicArn=ALERT_SNS_TOPIC,
                Subject=f"Anti-Trafficking Alert - Risk Score: {total_risk:.2f}",
                Message=json.dumps(alert, indent=2)
            )

            # Send CloudWatch metric
            cloudwatch.put_metric_data(
                Namespace='AEIMS/AntiTrafficking',
                MetricData=[
                    {
                        'MetricName': 'TraffickingRiskDetections',
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

            logger.info(f"Anti-trafficking alert sent for user: {user_id}")
            return True

        except Exception as e:
            logger.error(f"Alert sending error: {str(e)}")
            return False

    def _generate_recommended_actions(self, assessment_data: Dict[str, Any]) -> List[str]:
        """Generate recommended actions based on assessment"""
        actions = []

        if assessment_data.get('immediate_intervention_required'):
            actions.extend([
                'Immediate law enforcement notification',
                'Preserve all evidence',
                'Coordinate with specialized anti-trafficking units',
                'Prepare victim support resources'
            ])
        else:
            total_risk = assessment_data.get('total_risk_score', 0.0)
            if total_risk > 0.8:
                actions.extend([
                    'Enhanced monitoring of user activity',
                    'Review for law enforcement reporting requirements',
                    'Coordinate with anti-trafficking specialists'
                ])
            elif total_risk > 0.5:
                actions.extend([
                    'Continued monitoring',
                    'Document pattern development',
                    'Prepare for potential escalation'
                ])

        return actions


def lambda_handler(event, context):
    """
    Lambda handler for anti-trafficking monitoring

    Expected event structure:
    {
        "user_id": "user_identifier",
        "content": "content_to_analyze",
        "content_type": "text|image|communication",
        "analysis_type": "content|behavioral|comprehensive",
        "context": {
            "source": "chat|profile|listing|communication",
            "timestamp": "iso_timestamp",
            "additional_metadata": {}
        }
    }
    """
    try:
        logger.info(f"Processing anti-trafficking monitoring request: {event.get('user_id', 'unknown')}")

        # Validate input
        required_fields = ['user_id']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        user_id = event['user_id']
        content = event.get('content', '')
        content_type = event.get('content_type', 'text')
        analysis_type = event.get('analysis_type', 'comprehensive')
        context = event.get('context', {})

        # Initialize monitor
        monitor = AntiTraffickingMonitor()

        assessment_data = {
            'user_id': user_id,
            'analysis_timestamp': datetime.now(timezone.utc).isoformat(),
            'analysis_type': analysis_type,
            'context': context
        }

        # Perform content analysis if content provided
        if content and analysis_type in ['content', 'comprehensive']:
            content_analysis = monitor.analyze_content_for_trafficking(content, content_type)
            assessment_data['content_analysis'] = content_analysis

        # Perform behavioral analysis if requested
        if analysis_type in ['behavioral', 'comprehensive']:
            behavioral_analysis = monitor.analyze_behavioral_patterns(user_id, ANALYSIS_WINDOW_HOURS)
            assessment_data['behavioral_analysis'] = behavioral_analysis

        # Calculate total risk score
        content_risk = assessment_data.get('content_analysis', {}).get('trafficking_risk_score', 0.0)
        behavioral_risk = assessment_data.get('behavioral_analysis', {}).get('risk_score', 0.0)

        # Weight the risks (content analysis weighted higher for immediate threats)
        total_risk_score = (content_risk * 0.7) + (behavioral_risk * 0.3)
        assessment_data['total_risk_score'] = total_risk_score

        # Check for immediate intervention requirements
        immediate_intervention = assessment_data.get('content_analysis', {}).get('immediate_intervention_required', False)
        assessment_data['immediate_intervention_required'] = immediate_intervention

        # Collect all risk categories and indicators
        risk_categories = []
        behavioral_indicators = []

        if 'content_analysis' in assessment_data:
            risk_categories.extend(assessment_data['content_analysis'].get('risk_categories', []))

        if 'behavioral_analysis' in assessment_data:
            behavioral_indicators.extend(assessment_data['behavioral_analysis'].get('indicators', []))

        assessment_data['risk_categories'] = list(set(risk_categories))
        assessment_data['behavioral_indicators'] = behavioral_indicators

        # Collect detected patterns
        detected_patterns = assessment_data.get('content_analysis', {}).get('detected_patterns', {})
        assessment_data['detected_patterns'] = detected_patterns

        # Store assessment
        stored = monitor.store_trafficking_assessment(user_id, assessment_data)

        # Send alert if necessary
        alert_sent = False
        if total_risk_score >= RISK_THRESHOLD or immediate_intervention:
            alert_sent = monitor.send_trafficking_alert(user_id, assessment_data)

        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'user_id': user_id,
                'analysis_completed': True,
                'analysis_type': analysis_type,
                'total_risk_score': total_risk_score,
                'immediate_intervention_required': immediate_intervention,
                'alert_sent': alert_sent,
                'assessment_stored': stored,
                'risk_categories': assessment_data['risk_categories'],
                'behavioral_indicators': assessment_data['behavioral_indicators'],
                'pattern_count': len(detected_patterns),
                'risk_level': 'CRITICAL' if immediate_intervention else 'HIGH' if total_risk_score > 0.8 else 'MEDIUM' if total_risk_score > 0.5 else 'LOW',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_framework': 'Anti-Human_Trafficking'
            }
        }

        logger.info(f"Anti-trafficking monitoring completed: {user_id}")
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
        logger.error(f"Anti-trafficking monitor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal server error',
                'message': 'Anti-trafficking monitoring failed',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }