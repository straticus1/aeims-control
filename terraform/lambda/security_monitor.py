"""
Security Monitor Lambda Function

This function provides comprehensive security monitoring for the AEIMS platform,
detecting threats, anomalies, and security incidents while ensuring compliance
with defensive security requirements.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os
import hashlib
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
guardduty = boto3.client('guardduty')

# Configuration
SECURITY_TABLE = os.environ.get('SECURITY_EVENTS_TABLE', 'aeims-security-events')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
THREAT_THRESHOLD = float(os.environ.get('THREAT_THRESHOLD', '0.7'))

class SecurityMonitor:
    """Main class for comprehensive security monitoring"""

    def __init__(self):
        self.table = dynamodb.Table(SECURITY_TABLE)

        # Security threat categories
        self.threat_categories = {
            'authentication_attacks': {
                'patterns': [
                    'brute_force_login',
                    'credential_stuffing',
                    'session_hijacking',
                    'multi_factor_bypass'
                ],
                'severity_multiplier': 1.5
            },
            'data_access_threats': {
                'patterns': [
                    'unauthorized_data_access',
                    'privilege_escalation',
                    'data_exfiltration',
                    'bulk_data_download'
                ],
                'severity_multiplier': 2.0
            },
            'application_attacks': {
                'patterns': [
                    'sql_injection',
                    'xss_attack',
                    'csrf_attack',
                    'code_injection'
                ],
                'severity_multiplier': 1.8
            },
            'network_threats': {
                'patterns': [
                    'ddos_attack',
                    'port_scanning',
                    'malicious_ip_access',
                    'network_intrusion'
                ],
                'severity_multiplier': 1.3
            },
            'malware_threats': {
                'patterns': [
                    'malware_upload',
                    'virus_detection',
                    'trojan_activity',
                    'suspicious_file_behavior'
                ],
                'severity_multiplier': 2.5
            },
            'insider_threats': {
                'patterns': [
                    'unusual_admin_activity',
                    'off_hours_access',
                    'bulk_data_access',
                    'policy_violations'
                ],
                'severity_multiplier': 1.7
            }
        }

        # Anomaly detection patterns
        self.anomaly_patterns = {
            'user_behavior': [
                'unusual_login_times',
                'multiple_location_access',
                'excessive_failed_attempts',
                'unusual_data_access_patterns'
            ],
            'system_behavior': [
                'resource_consumption_spikes',
                'unusual_network_traffic',
                'unexpected_service_calls',
                'configuration_changes'
            ],
            'content_anomalies': [
                'mass_content_uploads',
                'suspicious_file_types',
                'large_file_transfers',
                'unusual_api_usage'
            ]
        }

        # Compliance-specific security monitoring
        self.compliance_security_checks = {
            'minor_data_protection': [
                'unauthorized_minor_data_access',
                'minor_data_exposure',
                'parental_control_bypass',
                'age_verification_manipulation'
            ],
            'fosta_security': [
                'content_filter_bypass',
                'trafficking_content_injection',
                'law_enforcement_data_tampering',
                'compliance_system_attacks'
            ],
            'privacy_security': [
                'privacy_setting_manipulation',
                'consent_bypass_attempts',
                'data_subject_rights_interference',
                'personal_data_unauthorized_access'
            ]
        }

    def analyze_security_event(self, security_event: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze individual security event for threats"""
        try:
            analysis_result = {
                'threat_detected': False,
                'threat_score': 0.0,
                'threat_categories': [],
                'anomaly_indicators': [],
                'compliance_implications': [],
                'immediate_action_required': False,
                'recommended_actions': [],
                'confidence_level': 'low'
            }

            event_type = security_event.get('event_type', '')
            event_data = security_event.get('event_data', {})
            source_ip = event_data.get('source_ip', '')
            user_id = event_data.get('user_id', '')
            timestamp = security_event.get('timestamp')

            # Analyze against threat patterns
            threat_analysis = self._analyze_threat_patterns(event_type, event_data)
            analysis_result.update(threat_analysis)

            # Check for anomalies
            anomaly_analysis = self._detect_anomalies(security_event)
            analysis_result['anomaly_indicators'].extend(anomaly_analysis['indicators'])
            analysis_result['threat_score'] += anomaly_analysis['anomaly_score']

            # Compliance-specific security checks
            compliance_analysis = self._check_compliance_security(security_event)
            analysis_result['compliance_implications'].extend(compliance_analysis['implications'])
            analysis_result['threat_score'] += compliance_analysis['compliance_risk_score']

            # IP reputation check
            ip_analysis = self._analyze_ip_reputation(source_ip)
            if ip_analysis['malicious']:
                analysis_result['threat_score'] += 0.4
                analysis_result['threat_categories'].append('malicious_ip_access')

            # User behavior analysis
            if user_id:
                user_analysis = self._analyze_user_behavior(user_id, security_event)
                analysis_result['threat_score'] += user_analysis['risk_contribution']
                analysis_result['anomaly_indicators'].extend(user_analysis['behavioral_anomalies'])

            # Final threat determination
            analysis_result['threat_score'] = min(analysis_result['threat_score'], 1.0)
            if analysis_result['threat_score'] >= THREAT_THRESHOLD:
                analysis_result['threat_detected'] = True

            # Determine confidence level
            if analysis_result['threat_score'] > 0.8:
                analysis_result['confidence_level'] = 'high'
            elif analysis_result['threat_score'] > 0.5:
                analysis_result['confidence_level'] = 'medium'
            else:
                analysis_result['confidence_level'] = 'low'

            # Determine if immediate action required
            if (analysis_result['threat_score'] > 0.8 or
                'minor_data_protection' in analysis_result['compliance_implications'] or
                'CRITICAL' in str(analysis_result)):
                analysis_result['immediate_action_required'] = True

            # Generate recommended actions
            analysis_result['recommended_actions'] = self._generate_security_actions(analysis_result)

            return analysis_result

        except Exception as e:
            logger.error(f"Security event analysis error: {str(e)}")
            raise

    def _analyze_threat_patterns(self, event_type: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze event against known threat patterns"""
        threat_analysis = {
            'threat_categories': [],
            'pattern_matches': [],
            'threat_score': 0.0
        }

        for category, config in self.threat_categories.items():
            category_score = 0.0
            matched_patterns = []

            for pattern in config['patterns']:
                if self._matches_threat_pattern(event_type, event_data, pattern):
                    matched_patterns.append(pattern)
                    category_score += 0.2

            if matched_patterns:
                threat_analysis['threat_categories'].append(category)
                threat_analysis['pattern_matches'].extend(matched_patterns)
                # Apply severity multiplier
                category_score *= config['severity_multiplier']
                threat_analysis['threat_score'] += min(category_score, 1.0)

        return threat_analysis

    def _matches_threat_pattern(self, event_type: str, event_data: Dict[str, Any], pattern: str) -> bool:
        """Check if event matches specific threat pattern"""
        pattern_checks = {
            'brute_force_login': lambda: event_data.get('failed_login_count', 0) > 10,
            'credential_stuffing': lambda: event_data.get('credential_list_detected', False),
            'unauthorized_data_access': lambda: event_data.get('unauthorized_access', False),
            'sql_injection': lambda: any(
                sql_keyword in str(event_data.get('request_data', '')).lower()
                for sql_keyword in ['union', 'select', 'drop', 'insert', 'update', 'delete', '--', ';']
            ),
            'xss_attack': lambda: any(
                xss_pattern in str(event_data.get('request_data', '')).lower()
                for xss_pattern in ['<script', 'javascript:', 'onerror=', 'onload=']
            ),
            'ddos_attack': lambda: event_data.get('request_rate', 0) > 1000,
            'malware_upload': lambda: event_data.get('malware_detected', False),
            'bulk_data_download': lambda: event_data.get('data_volume_mb', 0) > 1000
        }

        check_function = pattern_checks.get(pattern)
        return check_function() if check_function else False

    def _detect_anomalies(self, security_event: Dict[str, Any]) -> Dict[str, Any]:
        """Detect behavioral and system anomalies"""
        anomaly_result = {
            'indicators': [],
            'anomaly_score': 0.0
        }

        event_data = security_event.get('event_data', {})

        # Check for unusual timing
        event_time = datetime.fromisoformat(security_event.get('timestamp', datetime.now().isoformat()))
        if event_time.hour < 6 or event_time.hour > 22:  # Outside business hours
            anomaly_result['indicators'].append('off_hours_activity')
            anomaly_result['anomaly_score'] += 0.1

        # Check for unusual geographic access
        source_ip = event_data.get('source_ip', '')
        if self._is_unusual_geographic_access(source_ip):
            anomaly_result['indicators'].append('unusual_geographic_access')
            anomaly_result['anomaly_score'] += 0.2

        # Check for resource consumption anomalies
        if event_data.get('cpu_usage', 0) > 80 or event_data.get('memory_usage', 0) > 80:
            anomaly_result['indicators'].append('high_resource_consumption')
            anomaly_result['anomaly_score'] += 0.15

        # Check for unusual API usage
        if event_data.get('api_calls_per_minute', 0) > 100:
            anomaly_result['indicators'].append('unusual_api_usage')
            anomaly_result['anomaly_score'] += 0.2

        return anomaly_result

    def _check_compliance_security(self, security_event: Dict[str, Any]) -> Dict[str, Any]:
        """Check for compliance-specific security threats"""
        compliance_result = {
            'implications': [],
            'compliance_risk_score': 0.0
        }

        event_data = security_event.get('event_data', {})

        # Check minor data protection threats
        if event_data.get('involves_minor_data', False):
            compliance_result['implications'].append('minor_data_protection')
            compliance_result['compliance_risk_score'] += 0.5

        # Check FOSTA compliance security
        if any(keyword in str(event_data).lower() for keyword in ['trafficking', 'escort', 'commercial']):
            compliance_result['implications'].append('fosta_security')
            compliance_result['compliance_risk_score'] += 0.4

        # Check privacy security
        if event_data.get('personal_data_involved', False):
            compliance_result['implications'].append('privacy_security')
            compliance_result['compliance_risk_score'] += 0.3

        return compliance_result

    def _analyze_ip_reputation(self, ip_address: str) -> Dict[str, Any]:
        """Analyze IP address reputation"""
        # This would typically integrate with threat intelligence services
        # For demonstration, we'll use basic checks
        ip_analysis = {
            'malicious': False,
            'reputation_score': 0.0,
            'threat_types': []
        }

        # Basic malicious IP patterns (in real implementation, use threat intelligence)
        known_malicious_patterns = [
            r'^10\.0\.0\.',  # Example internal IP (not actually malicious)
            r'^192\.168\.',  # Example private IP (not actually malicious)
        ]

        # This would be replaced with real threat intelligence API calls
        return ip_analysis

    def _analyze_user_behavior(self, user_id: str, current_event: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze user behavior for anomalies"""
        behavior_analysis = {
            'risk_contribution': 0.0,
            'behavioral_anomalies': []
        }

        try:
            # Get recent user activity (simplified for demo)
            recent_activity = self._get_recent_user_activity(user_id)

            # Check for unusual patterns
            if len(recent_activity) > 100:  # High activity volume
                behavior_analysis['behavioral_anomalies'].append('high_activity_volume')
                behavior_analysis['risk_contribution'] += 0.1

            # Check for rapid location changes
            locations = [activity.get('source_ip') for activity in recent_activity[-10:]]
            unique_locations = len(set(locations))
            if unique_locations > 5:
                behavior_analysis['behavioral_anomalies'].append('rapid_location_changes')
                behavior_analysis['risk_contribution'] += 0.2

        except Exception as e:
            logger.warning(f"User behavior analysis error: {str(e)}")

        return behavior_analysis

    def _get_recent_user_activity(self, user_id: str) -> List[Dict[str, Any]]:
        """Get recent user activity for analysis"""
        try:
            cutoff_time = datetime.now(timezone.utc) - timedelta(hours=24)
            cutoff_timestamp = int(cutoff_time.timestamp())

            response = self.table.scan(
                FilterExpression='user_id = :uid AND event_timestamp > :cutoff',
                ExpressionAttributeValues={
                    ':uid': user_id,
                    ':cutoff': cutoff_timestamp
                }
            )

            return response.get('Items', [])

        except Exception as e:
            logger.warning(f"Recent activity retrieval error: {str(e)}")
            return []

    def _is_unusual_geographic_access(self, ip_address: str) -> bool:
        """Check if IP represents unusual geographic access"""
        # This would integrate with geolocation services
        # For demonstration, return False
        return False

    def _generate_security_actions(self, analysis_result: Dict[str, Any]) -> List[str]:
        """Generate recommended security actions"""
        actions = []

        if analysis_result['threat_detected']:
            actions.append('Investigate security threat immediately')
            actions.append('Review user activity logs')

        if analysis_result['immediate_action_required']:
            actions.append('Isolate affected systems')
            actions.append('Notify security team')

        if 'minor_data_protection' in analysis_result['compliance_implications']:
            actions.append('Escalate to child safety team')
            actions.append('Review minor data access controls')

        if analysis_result['threat_score'] > 0.8:
            actions.append('Consider blocking source IP')
            actions.append('Implement additional monitoring')

        return actions

    def store_security_event(self, security_event: Dict[str, Any], analysis_result: Dict[str, Any]) -> bool:
        """Store security event and analysis"""
        try:
            item = {
                'event_id': f"{security_event.get('event_type', 'unknown')}_{int(datetime.now(timezone.utc).timestamp())}",
                'event_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'event_type': security_event.get('event_type'),
                'user_id': security_event.get('event_data', {}).get('user_id'),
                'source_ip': security_event.get('event_data', {}).get('source_ip'),
                'threat_detected': analysis_result['threat_detected'],
                'threat_score': analysis_result['threat_score'],
                'threat_categories': analysis_result['threat_categories'],
                'compliance_implications': analysis_result['compliance_implications'],
                'immediate_action_required': analysis_result['immediate_action_required'],
                'confidence_level': analysis_result['confidence_level'],
                'event_data': json.dumps(security_event),
                'analysis_result': json.dumps(analysis_result),
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=365)).timestamp())
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Security event storage error: {str(e)}")
            return False

    def send_security_alert(self, security_event: Dict[str, Any], analysis_result: Dict[str, Any]) -> bool:
        """Send security alert"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            # Send alert for high-threat events
            if (analysis_result['threat_detected'] or
                analysis_result['immediate_action_required'] or
                analysis_result['threat_score'] > 0.7):

                alert = {
                    'alert_type': 'SECURITY_THREAT_DETECTED',
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'threat_score': analysis_result['threat_score'],
                    'threat_categories': analysis_result['threat_categories'],
                    'confidence_level': analysis_result['confidence_level'],
                    'immediate_action_required': analysis_result['immediate_action_required'],
                    'compliance_implications': analysis_result['compliance_implications'],
                    'recommended_actions': analysis_result['recommended_actions'],
                    'event_summary': {
                        'event_type': security_event.get('event_type'),
                        'source_ip': security_event.get('event_data', {}).get('source_ip'),
                        'user_id': security_event.get('event_data', {}).get('user_id')
                    },
                    'severity': 'CRITICAL' if analysis_result['threat_score'] > 0.8 else 'HIGH' if analysis_result['threat_score'] > 0.6 else 'MEDIUM'
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject=f"Security Alert - {alert['severity']} Threat Detected",
                    Message=json.dumps(alert, indent=2)
                )

                # Send CloudWatch metric
                cloudwatch.put_metric_data(
                    Namespace='AEIMS/Security',
                    MetricData=[
                        {
                            'MetricName': 'SecurityThreats',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': alert['severity']
                                },
                                {
                                    'Name': 'ThreatCategory',
                                    'Value': analysis_result['threat_categories'][0] if analysis_result['threat_categories'] else 'unknown'
                                }
                            ]
                        }
                    ]
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Security alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for security monitoring"""
    try:
        logger.info("Processing security monitoring request")

        required_fields = ['security_event']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        security_event = event['security_event']

        monitor = SecurityMonitor()

        # Analyze security event
        analysis_result = monitor.analyze_security_event(security_event)

        # Store event and analysis
        stored = monitor.store_security_event(security_event, analysis_result)

        # Send alert if necessary
        alert_sent = monitor.send_security_alert(security_event, analysis_result)

        response = {
            'statusCode': 200,
            'body': {
                'monitoring_completed': True,
                'threat_detected': analysis_result['threat_detected'],
                'threat_score': analysis_result['threat_score'],
                'threat_categories': analysis_result['threat_categories'],
                'confidence_level': analysis_result['confidence_level'],
                'immediate_action_required': analysis_result['immediate_action_required'],
                'compliance_implications': analysis_result['compliance_implications'],
                'recommended_actions': analysis_result['recommended_actions'],
                'alert_sent': alert_sent,
                'event_stored': stored,
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
        logger.error(f"Security monitor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Security monitoring failed'}
        }