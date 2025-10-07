"""
Breach Detector Lambda Function

This function monitors for data breaches and security incidents that could
compromise user data, particularly focusing on protecting minor user information
and ensuring compliance with breach notification requirements.

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

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')
cloudtrail = boto3.client('cloudtrail')

# Configuration
BREACH_TABLE = os.environ.get('BREACH_TABLE', 'aeims-breach-incidents')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
LEGAL_NOTIFICATION_ARN = os.environ.get('LEGAL_NOTIFICATION_ARN')

class BreachDetector:
    """Main class for data breach detection and response"""

    def __init__(self):
        self.table = dynamodb.Table(BREACH_TABLE)

        # Breach detection patterns
        self.breach_indicators = {
            'unauthorized_access': [
                'multiple_failed_logins',
                'unusual_access_patterns',
                'privilege_escalation',
                'administrative_bypass'
            ],
            'data_exfiltration': [
                'bulk_data_download',
                'unusual_api_usage',
                'large_data_transfers',
                'database_dumps'
            ],
            'system_compromise': [
                'malware_detection',
                'unauthorized_code_execution',
                'system_file_modifications',
                'network_intrusion'
            ],
            'insider_threats': [
                'unauthorized_data_access',
                'policy_violations',
                'suspicious_employee_activity',
                'data_misuse'
            ]
        }

        # Severity criteria
        self.severity_criteria = {
            'CRITICAL': {
                'minor_data_involved': True,
                'pii_exposed': True,
                'large_scale': True,
                'public_exposure': True
            },
            'HIGH': {
                'pii_exposed': True,
                'authentication_compromised': True,
                'system_access_gained': True
            },
            'MEDIUM': {
                'limited_data_exposure': True,
                'potential_vulnerability': True,
                'suspicious_activity': True
            },
            'LOW': {
                'minor_anomaly': True,
                'preventive_detection': True
            }
        }

    def detect_breach_indicators(self, security_event: Dict[str, Any]) -> Dict[str, Any]:
        """Detect potential breach indicators from security event"""
        try:
            detection_result = {
                'breach_detected': False,
                'confidence_score': 0.0,
                'indicator_types': [],
                'affected_systems': [],
                'potential_impact': {},
                'immediate_response_required': False,
                'investigation_priority': 'LOW'
            }

            event_type = security_event.get('event_type', '')
            event_data = security_event.get('event_data', {})
            timestamp = security_event.get('timestamp')

            # Analyze event against breach indicators
            for category, indicators in self.breach_indicators.items():
                category_score = 0.0
                detected_indicators = []

                for indicator in indicators:
                    if self._check_indicator(event_data, indicator):
                        detected_indicators.append(indicator)
                        category_score += 0.25

                if detected_indicators:
                    detection_result['indicator_types'].append({
                        'category': category,
                        'indicators': detected_indicators,
                        'score': min(category_score, 1.0)
                    })
                    detection_result['confidence_score'] += category_score

            # Determine if breach detected
            detection_result['confidence_score'] = min(detection_result['confidence_score'], 1.0)
            if detection_result['confidence_score'] > 0.6:
                detection_result['breach_detected'] = True

            # Assess potential impact
            impact_assessment = self._assess_potential_impact(security_event, detection_result)
            detection_result['potential_impact'] = impact_assessment

            # Determine response priority
            priority = self._determine_investigation_priority(detection_result, impact_assessment)
            detection_result['investigation_priority'] = priority

            # Check if immediate response required
            if (impact_assessment.get('minor_data_at_risk', False) or
                impact_assessment.get('severity') in ['CRITICAL', 'HIGH']):
                detection_result['immediate_response_required'] = True

            return detection_result

        except Exception as e:
            logger.error(f"Breach detection error: {str(e)}")
            raise

    def _check_indicator(self, event_data: Dict[str, Any], indicator: str) -> bool:
        """Check if specific breach indicator is present"""
        indicator_checks = {
            'multiple_failed_logins': lambda data: data.get('failed_login_count', 0) > 5,
            'unusual_access_patterns': lambda data: data.get('access_anomaly_score', 0) > 0.8,
            'privilege_escalation': lambda data: 'privilege_change' in data.get('actions', []),
            'bulk_data_download': lambda data: data.get('data_volume_mb', 0) > 1000,
            'unusual_api_usage': lambda data: data.get('api_call_rate', 0) > 1000,
            'malware_detection': lambda data: data.get('malware_detected', False),
            'unauthorized_code_execution': lambda data: 'code_execution' in data.get('security_events', []),
            'unauthorized_data_access': lambda data: data.get('unauthorized_access', False)
        }

        check_function = indicator_checks.get(indicator)
        if check_function:
            return check_function(event_data)
        return False

    def _assess_potential_impact(self, security_event: Dict[str, Any], detection_result: Dict[str, Any]) -> Dict[str, Any]:
        """Assess potential impact of detected breach"""
        try:
            impact = {
                'severity': 'LOW',
                'estimated_affected_users': 0,
                'minor_data_at_risk': False,
                'pii_exposed': False,
                'financial_data_at_risk': False,
                'system_integrity_compromised': False,
                'public_exposure_risk': False,
                'compliance_implications': []
            }

            event_data = security_event.get('event_data', {})

            # Check data types at risk
            data_types = event_data.get('data_types_involved', [])
            if 'minor_user_data' in data_types:
                impact['minor_data_at_risk'] = True
                impact['compliance_implications'].extend(['COPPA', 'Florida_HB_3'])

            if any(dt in data_types for dt in ['pii', 'personal_information', 'user_profiles']):
                impact['pii_exposed'] = True
                impact['compliance_implications'].append('GDPR_CCPA')

            if 'financial_data' in data_types:
                impact['financial_data_at_risk'] = True
                impact['compliance_implications'].append('PCI_DSS')

            # Estimate affected users
            impact['estimated_affected_users'] = event_data.get('affected_user_count', 0)

            # Assess system integrity
            if detection_result['confidence_score'] > 0.8:
                impact['system_integrity_compromised'] = True

            # Determine severity
            severity_score = 0
            if impact['minor_data_at_risk']:
                severity_score += 3
            if impact['pii_exposed']:
                severity_score += 2
            if impact['estimated_affected_users'] > 1000:
                severity_score += 2
            if impact['system_integrity_compromised']:
                severity_score += 1

            if severity_score >= 5:
                impact['severity'] = 'CRITICAL'
            elif severity_score >= 3:
                impact['severity'] = 'HIGH'
            elif severity_score >= 1:
                impact['severity'] = 'MEDIUM'
            else:
                impact['severity'] = 'LOW'

            return impact

        except Exception as e:
            logger.error(f"Impact assessment error: {str(e)}")
            return {'severity': 'UNKNOWN', 'error': str(e)}

    def _determine_investigation_priority(self, detection_result: Dict[str, Any], impact: Dict[str, Any]) -> str:
        """Determine investigation priority"""
        if impact['severity'] == 'CRITICAL' or impact['minor_data_at_risk']:
            return 'CRITICAL'
        elif impact['severity'] == 'HIGH' or detection_result['confidence_score'] > 0.8:
            return 'HIGH'
        elif impact['severity'] == 'MEDIUM' or detection_result['confidence_score'] > 0.6:
            return 'MEDIUM'
        else:
            return 'LOW'

    def initiate_breach_response(self, detection_result: Dict[str, Any], security_event: Dict[str, Any]) -> Dict[str, Any]:
        """Initiate automated breach response procedures"""
        try:
            response_actions = {
                'incident_id': f"BREACH_{int(datetime.now(timezone.utc).timestamp())}",
                'response_initiated': datetime.now(timezone.utc).isoformat(),
                'containment_actions': [],
                'investigation_actions': [],
                'notification_actions': [],
                'recovery_actions': [],
                'lessons_learned': []
            }

            impact = detection_result['potential_impact']
            priority = detection_result['investigation_priority']

            # Immediate containment actions
            if priority in ['CRITICAL', 'HIGH']:
                response_actions['containment_actions'].extend([
                    'isolate_affected_systems',
                    'disable_compromised_accounts',
                    'increase_monitoring_affected_areas',
                    'preserve_forensic_evidence'
                ])

            if impact.get('minor_data_at_risk'):
                response_actions['containment_actions'].extend([
                    'emergency_minor_data_protection',
                    'notify_parental_contacts',
                    'escalate_to_child_safety_team'
                ])

            # Investigation actions
            response_actions['investigation_actions'].extend([
                'collect_system_logs',
                'analyze_attack_vectors',
                'identify_affected_data',
                'assess_timeline_of_compromise'
            ])

            # Notification requirements
            notification_requirements = self._determine_notification_requirements(impact)
            response_actions['notification_actions'] = notification_requirements

            # Recovery actions
            if impact.get('system_integrity_compromised'):
                response_actions['recovery_actions'].extend([
                    'system_integrity_verification',
                    'malware_removal_if_applicable',
                    'security_patch_deployment',
                    'configuration_hardening'
                ])

            return response_actions

        except Exception as e:
            logger.error(f"Breach response initiation error: {str(e)}")
            raise

    def _determine_notification_requirements(self, impact: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Determine required notifications based on impact"""
        notifications = []

        # Legal/compliance notifications
        if impact.get('minor_data_at_risk'):
            notifications.extend([
                {
                    'type': 'legal_immediate',
                    'recipient': 'legal_department',
                    'timeline': 'immediate',
                    'reason': 'minor_data_breach'
                },
                {
                    'type': 'regulatory',
                    'recipient': 'florida_attorney_general',
                    'timeline': '24_hours',
                    'reason': 'florida_minor_data_protection'
                }
            ])

        if impact.get('pii_exposed') and impact.get('estimated_affected_users', 0) > 500:
            notifications.append({
                'type': 'regulatory',
                'recipient': 'state_attorney_general',
                'timeline': '72_hours',
                'reason': 'large_scale_pii_breach'
            })

        # User notifications
        if impact['severity'] in ['CRITICAL', 'HIGH']:
            notifications.append({
                'type': 'user_notification',
                'recipient': 'affected_users',
                'timeline': '72_hours',
                'reason': 'breach_notification_requirement'
            })

        return notifications

    def store_breach_incident(self, detection_result: Dict[str, Any], security_event: Dict[str, Any], response_actions: Dict[str, Any]) -> bool:
        """Store breach incident record"""
        try:
            incident_id = response_actions['incident_id']

            item = {
                'incident_id': incident_id,
                'detection_timestamp': int(datetime.now(timezone.utc).timestamp()),
                'breach_detected': detection_result['breach_detected'],
                'confidence_score': detection_result['confidence_score'],
                'investigation_priority': detection_result['investigation_priority'],
                'severity': detection_result['potential_impact']['severity'],
                'minor_data_involved': detection_result['potential_impact'].get('minor_data_at_risk', False),
                'estimated_affected_users': detection_result['potential_impact'].get('estimated_affected_users', 0),
                'compliance_implications': detection_result['potential_impact'].get('compliance_implications', []),
                'security_event_data': json.dumps(security_event),
                'detection_details': json.dumps(detection_result),
                'response_actions': json.dumps(response_actions),
                'status': 'investigating',
                'ttl': int((datetime.now(timezone.utc) + timedelta(days=2555)).timestamp())  # 7 year retention
            }

            self.table.put_item(Item=item)
            return True

        except Exception as e:
            logger.error(f"Breach incident storage error: {str(e)}")
            return False

    def send_breach_alerts(self, detection_result: Dict[str, Any], response_actions: Dict[str, Any]) -> bool:
        """Send breach detection alerts"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            priority = detection_result['investigation_priority']
            impact = detection_result['potential_impact']

            # Send high priority alerts immediately
            if priority in ['CRITICAL', 'HIGH']:
                alert = {
                    'alert_type': 'DATA_BREACH_DETECTED',
                    'incident_id': response_actions['incident_id'],
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'severity': impact['severity'],
                    'priority': priority,
                    'minor_data_involved': impact.get('minor_data_at_risk', False),
                    'estimated_affected_users': impact.get('estimated_affected_users', 0),
                    'immediate_response_required': detection_result['immediate_response_required'],
                    'compliance_implications': impact.get('compliance_implications', []),
                    'containment_actions_initiated': response_actions['containment_actions']
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject=f"BREACH ALERT - {priority} Priority - Incident {response_actions['incident_id']}",
                    Message=json.dumps(alert, indent=2)
                )

                # Send CloudWatch metric
                cloudwatch.put_metric_data(
                    Namespace='AEIMS/Security/Breaches',
                    MetricData=[
                        {
                            'MetricName': 'BreachDetections',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': impact['severity']
                                },
                                {
                                    'Name': 'Priority',
                                    'Value': priority
                                }
                            ]
                        }
                    ]
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Breach alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for breach detection"""
    try:
        logger.info("Processing breach detection request")

        required_fields = ['security_event']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        security_event = event['security_event']

        detector = BreachDetector()

        # Detect breach indicators
        detection_result = detector.detect_breach_indicators(security_event)

        # Initiate response if breach detected
        response_actions = None
        if detection_result['breach_detected'] or detection_result['immediate_response_required']:
            response_actions = detector.initiate_breach_response(detection_result, security_event)

        # Store incident record
        stored = False
        if response_actions:
            stored = detector.store_breach_incident(detection_result, security_event, response_actions)

        # Send alerts
        alert_sent = False
        if detection_result['investigation_priority'] in ['CRITICAL', 'HIGH']:
            alert_sent = detector.send_breach_alerts(detection_result, response_actions or {})

        response = {
            'statusCode': 200,
            'body': {
                'breach_detected': detection_result['breach_detected'],
                'confidence_score': detection_result['confidence_score'],
                'investigation_priority': detection_result['investigation_priority'],
                'severity': detection_result['potential_impact']['severity'],
                'immediate_response_required': detection_result['immediate_response_required'],
                'minor_data_at_risk': detection_result['potential_impact'].get('minor_data_at_risk', False),
                'incident_id': response_actions['incident_id'] if response_actions else None,
                'response_initiated': response_actions is not None,
                'alert_sent': alert_sent,
                'incident_stored': stored,
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
        logger.error(f"Breach detector error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Breach detection failed'}
        }