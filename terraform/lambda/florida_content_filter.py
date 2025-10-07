"""
Florida Content Filter Lambda Function

This function implements content filtering specifically for Florida state
requirements including HB 3 social media protections and other state-specific
content regulations.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional
import os
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
comprehend = boto3.client('comprehend')

# Configuration
FILTER_TABLE = os.environ.get('FL_CONTENT_FILTER_TABLE', 'aeims-florida-content-filter')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')

class FloridaContentFilter:
    """Main class for Florida-specific content filtering"""

    def __init__(self):
        self.table = dynamodb.Table(FILTER_TABLE)

        # Florida HB 3 content restrictions for minors
        self.florida_minor_restrictions = [
            # Harmful content patterns
            r'\b(?:self.?harm|suicide|cutting)\b',
            r'\b(?:eating.?disorder|anorexia|bulimia)\b',
            r'\b(?:drug.?use|substance.?abuse|addiction)\b',
            r'\b(?:sexual.?content|explicit|adult.?material)\b',
            r'\b(?:violence|graphic|disturbing)\b',

            # Social media specific risks
            r'\b(?:meet.?up|secret|private.?meeting)\b',
            r'\b(?:dont?.tell|keep.?secret|between.?us)\b',
            r'\b(?:location|address|where.?you.?live)\b',
            r'\b(?:personal.?info|phone.?number|social.?security)\b',

            # Cyberbullying patterns
            r'\b(?:kill.?yourself|worthless|loser|ugly)\b',
            r'\b(?:nobody.?likes|hate.?you|die)\b',
            r'\b(?:embarrassing|humiliate|shame)\b'
        ]

        # Age-appropriate content guidelines
        self.age_content_matrix = {
            'under_14': {
                'prohibited_topics': [
                    'sexual_content', 'violence', 'substance_abuse',
                    'self_harm', 'cyberbullying', 'predatory_behavior'
                ],
                'restricted_interactions': [
                    'private_messaging_adults', 'location_sharing',
                    'personal_info_sharing', 'commercial_transactions'
                ]
            },
            '14_to_15': {
                'prohibited_topics': [
                    'explicit_sexual_content', 'graphic_violence',
                    'substance_abuse_promotion', 'self_harm_content'
                ],
                'restricted_interactions': [
                    'private_messaging_unknown_adults', 'location_sharing',
                    'financial_transactions'
                ],
                'requires_parental_notification': [
                    'content_violations', 'cyberbullying_incidents',
                    'predatory_contact_attempts'
                ]
            },
            '16_to_17': {
                'prohibited_topics': [
                    'explicit_sexual_content', 'extreme_violence',
                    'illegal_substance_promotion'
                ],
                'restricted_interactions': [
                    'commercial_adult_content', 'gambling'
                ],
                'parental_notification_recommended': [
                    'serious_content_violations', 'safety_concerns'
                ]
            }
        }

    def filter_content_florida_requirements(self, content_data: Dict[str, Any]) -> Dict[str, Any]:
        """Filter content according to Florida HB 3 requirements"""
        try:
            filter_result = {
                'content_allowed': True,
                'florida_compliant': True,
                'violations': [],
                'age_appropriate': True,
                'parental_notification_required': False,
                'recommended_actions': [],
                'risk_level': 'LOW'
            }

            content = content_data.get('content', '')
            user_age_category = content_data.get('user_age_category')
            user_location = content_data.get('user_location', {})
            content_type = content_data.get('content_type', 'text')

            # Check if Florida jurisdiction applies
            if not self._is_florida_jurisdiction(user_location):
                filter_result['florida_compliant'] = True
                return filter_result

            # Check age-specific restrictions
            if user_age_category in self.age_content_matrix:
                age_restrictions = self.age_content_matrix[user_age_category]
                age_filter_result = self._apply_age_restrictions(content, age_restrictions, content_type)
                filter_result.update(age_filter_result)

            # Apply general Florida minor protection patterns
            minor_violation_result = self._check_minor_protection_violations(content, user_age_category)
            if minor_violation_result['violations']:
                filter_result['violations'].extend(minor_violation_result['violations'])
                filter_result['content_allowed'] = False
                filter_result['florida_compliant'] = False

            # Check for cyberbullying (special Florida emphasis)
            cyberbullying_result = self._detect_cyberbullying(content, user_age_category)
            if cyberbullying_result['detected']:
                filter_result['violations'].append('cyberbullying_detected')
                filter_result['content_allowed'] = False
                filter_result['parental_notification_required'] = True
                filter_result['risk_level'] = 'HIGH'

            # Apply content sentiment analysis for minors
            if user_age_category != '18_plus':
                sentiment_result = self._analyze_content_sentiment(content)
                if sentiment_result['harmful_to_minors']:
                    filter_result['violations'].append('harmful_sentiment_detected')
                    filter_result['age_appropriate'] = False

            # Determine final risk level
            filter_result['risk_level'] = self._calculate_risk_level(filter_result)

            # Generate recommended actions
            filter_result['recommended_actions'] = self._generate_recommended_actions(filter_result, user_age_category)

            return filter_result

        except Exception as e:
            logger.error(f"Florida content filtering error: {str(e)}")
            raise

    def _is_florida_jurisdiction(self, location: Dict[str, Any]) -> bool:
        """Check if Florida law applies"""
        state = location.get('state', '').lower()
        return state in ['florida', 'fl']

    def _apply_age_restrictions(self, content: str, restrictions: Dict[str, List], content_type: str) -> Dict[str, Any]:
        """Apply age-specific content restrictions"""
        result = {
            'age_violations': [],
            'interaction_restrictions': [],
            'notification_triggers': []
        }

        # Check prohibited topics
        for topic in restrictions.get('prohibited_topics', []):
            if self._content_contains_topic(content, topic):
                result['age_violations'].append(topic)

        # Check restricted interactions (if applicable)
        for interaction in restrictions.get('restricted_interactions', []):
            if self._content_indicates_interaction(content, interaction):
                result['interaction_restrictions'].append(interaction)

        # Check notification triggers
        for trigger in restrictions.get('requires_parental_notification', []):
            if self._content_triggers_notification(content, trigger):
                result['notification_triggers'].append(trigger)

        return result

    def _content_contains_topic(self, content: str, topic: str) -> bool:
        """Check if content contains prohibited topic"""
        topic_patterns = {
            'sexual_content': [r'\bsex\b', r'\bsexual\b', r'\bnude\b', r'\bnaked\b'],
            'violence': [r'\bviolence\b', r'\bfight\b', r'\bhurt\b', r'\bkill\b'],
            'substance_abuse': [r'\bdrugs?\b', r'\balcohol\b', r'\bsmoke\b', r'\bhigh\b'],
            'self_harm': [r'\bcut\b', r'\bharming?\b', r'\bsuicide\b', r'\bkill.?myself\b'],
            'cyberbullying': [r'\bloser\b', r'\bugly\b', r'\bstupid\b', r'\bhate.?you\b']
        }

        patterns = topic_patterns.get(topic, [])
        for pattern in patterns:
            if re.search(pattern, content, re.IGNORECASE):
                return True
        return False

    def _content_indicates_interaction(self, content: str, interaction: str) -> bool:
        """Check if content indicates restricted interaction"""
        interaction_patterns = {
            'private_messaging_adults': [r'\bmessage.?me\b', r'\bprivate.?chat\b'],
            'location_sharing': [r'\bwhere.?are.?you\b', r'\baddress\b', r'\blocation\b'],
            'personal_info_sharing': [r'\bphone.?number\b', r'\bemail\b', r'\breal.?name\b'],
            'commercial_transactions': [r'\bbuy\b', r'\bsell\b', r'\bmoney\b', r'\bpay\b']
        }

        patterns = interaction_patterns.get(interaction, [])
        for pattern in patterns:
            if re.search(pattern, content, re.IGNORECASE):
                return True
        return False

    def _content_triggers_notification(self, content: str, trigger: str) -> bool:
        """Check if content triggers parental notification"""
        trigger_patterns = {
            'content_violations': [r'\bviolation\b', r'\bprohibited\b'],
            'cyberbullying_incidents': [r'\bbully\b', r'\bharass\b', r'\bmean\b'],
            'predatory_contact_attempts': [r'\bmeet\b', r'\bsecret\b', r'\balone\b']
        }

        patterns = trigger_patterns.get(trigger, [])
        for pattern in patterns:
            if re.search(pattern, content, re.IGNORECASE):
                return True
        return False

    def _check_minor_protection_violations(self, content: str, age_category: str) -> Dict[str, Any]:
        """Check for violations of minor protection patterns"""
        result = {'violations': []}

        if age_category == '18_plus':
            return result

        for pattern in self.florida_minor_restrictions:
            if re.search(pattern, content, re.IGNORECASE):
                result['violations'].append(f'minor_protection_violation: {pattern}')

        return result

    def _detect_cyberbullying(self, content: str, age_category: str) -> Dict[str, Any]:
        """Detect cyberbullying patterns (Florida emphasis)"""
        cyberbullying_patterns = [
            r'\b(?:kill.?yourself|kys)\b',
            r'\b(?:nobody.?likes.?you|everyone.?hates.?you)\b',
            r'\b(?:ugly|fat|stupid|worthless|loser)\b',
            r'\b(?:embarrassing|humiliating|pathetic)\b'
        ]

        detected = False
        severity = 'LOW'

        for pattern in cyberbullying_patterns:
            if re.search(pattern, content, re.IGNORECASE):
                detected = True
                if 'kill' in pattern or 'suicide' in pattern:
                    severity = 'CRITICAL'
                elif 'hate' in pattern or 'nobody' in pattern:
                    severity = 'HIGH'
                else:
                    severity = 'MEDIUM'
                break

        return {'detected': detected, 'severity': severity}

    def _analyze_content_sentiment(self, content: str) -> Dict[str, Any]:
        """Analyze content sentiment for harm to minors"""
        try:
            if len(content) < 10:
                return {'harmful_to_minors': False}

            # Use AWS Comprehend for sentiment analysis
            response = comprehend.detect_sentiment(
                Text=content[:1000],  # Limit for Comprehend
                LanguageCode='en'
            )

            sentiment = response['Sentiment']
            scores = response['SentimentScore']

            # Determine if harmful to minors based on sentiment
            harmful_to_minors = False

            if sentiment == 'NEGATIVE' and scores['Negative'] > 0.8:
                harmful_to_minors = True
            elif sentiment == 'MIXED' and scores['Negative'] > 0.6:
                harmful_to_minors = True

            return {
                'harmful_to_minors': harmful_to_minors,
                'sentiment': sentiment,
                'scores': scores
            }

        except Exception as e:
            logger.warning(f"Sentiment analysis failed: {str(e)}")
            return {'harmful_to_minors': False, 'error': str(e)}

    def _calculate_risk_level(self, filter_result: Dict[str, Any]) -> str:
        """Calculate overall risk level"""
        if not filter_result['content_allowed']:
            return 'HIGH'
        elif filter_result['parental_notification_required']:
            return 'MEDIUM'
        elif not filter_result['age_appropriate']:
            return 'MEDIUM'
        else:
            return 'LOW'

    def _generate_recommended_actions(self, filter_result: Dict[str, Any], age_category: str) -> List[str]:
        """Generate recommended actions based on filter results"""
        actions = []

        if not filter_result['content_allowed']:
            actions.append('Block content publication')
            actions.append('Notify content moderation team')

        if filter_result['parental_notification_required']:
            actions.append('Send parental notification')
            actions.append('Document incident for compliance records')

        if not filter_result['age_appropriate']:
            actions.append('Apply age-appropriate content warning')
            actions.append('Restrict content visibility to age-appropriate users')

        if filter_result['violations']:
            actions.append('Log violations in compliance database')
            actions.append('Apply user education measures')

        return actions

    def store_filter_record(self, content_data: Dict[str, Any], filter_result: Dict[str, Any]) -> bool:
        """Store content filter record"""
        try:
            item = {
                'record_id': f"{content_data.get('user_id', 'unknown')}_{int(datetime.now(timezone.utc).timestamp())}",
                'user_id': content_data.get('user_id'),
                'content_id': content_data.get('content_id'),
                'timestamp': int(datetime.now(timezone.utc).timestamp()),
                'content_allowed': filter_result['content_allowed'],
                'florida_compliant': filter_result['florida_compliant'],
                'violations': filter_result['violations'],
                'age_appropriate': filter_result['age_appropriate'],
                'risk_level': filter_result['risk_level'],
                'user_age_category': content_data.get('user_age_category'),
                'compliance_framework': 'Florida_HB_3',
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=90)).timestamp())
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Filter record storage error: {str(e)}")
            return False

    def send_filter_alert(self, content_data: Dict[str, Any], filter_result: Dict[str, Any]) -> bool:
        """Send alert for content filtering issues"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            # Send alert for high-risk content or violations
            if filter_result['risk_level'] in ['HIGH', 'CRITICAL'] or not filter_result['content_allowed']:
                alert = {
                    'alert_type': 'FLORIDA_CONTENT_FILTER_VIOLATION',
                    'user_id': content_data.get('user_id'),
                    'content_id': content_data.get('content_id'),
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'violations': filter_result['violations'],
                    'content_allowed': filter_result['content_allowed'],
                    'florida_compliant': filter_result['florida_compliant'],
                    'parental_notification_required': filter_result['parental_notification_required'],
                    'risk_level': filter_result['risk_level'],
                    'severity': filter_result['risk_level']
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject="Florida Content Filter Alert",
                    Message=json.dumps(alert, indent=2)
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Filter alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for Florida content filtering"""
    try:
        logger.info("Processing Florida content filter request")

        required_fields = ['content_data']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        content_data = event['content_data']

        filter_instance = FloridaContentFilter()
        filter_result = filter_instance.filter_content_florida_requirements(content_data)

        stored = filter_instance.store_filter_record(content_data, filter_result)
        alert_sent = filter_instance.send_filter_alert(content_data, filter_result)

        response = {
            'statusCode': 200,
            'body': {
                'content_id': content_data.get('content_id'),
                'filtered': True,
                'content_allowed': filter_result['content_allowed'],
                'florida_compliant': filter_result['florida_compliant'],
                'age_appropriate': filter_result['age_appropriate'],
                'violations': filter_result['violations'],
                'risk_level': filter_result['risk_level'],
                'parental_notification_required': filter_result['parental_notification_required'],
                'recommended_actions': filter_result['recommended_actions'],
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
        logger.error(f"Florida content filter error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Content filtering failed'}
        }