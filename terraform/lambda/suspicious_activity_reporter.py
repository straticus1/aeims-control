"""
Suspicious Activity Reporter Lambda function
Reports suspicious activities to appropriate authorities
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import boto3
import hashlib

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class SuspiciousActivityReporter:
    def __init__(self):
        """Initialize suspicious activity reporter"""
        self.sns = boto3.client('sns')
        self.s3 = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')

        # Suspicious activity categories
        self.activity_categories = {
            'trafficking': {
                'keywords': ['escort', 'young', 'fresh', 'new in town'],
                'severity': 'CRITICAL',
                'authorities': ['FBI', 'NCMEC', 'LOCAL_PD']
            },
            'exploitation': {
                'keywords': ['barely legal', 'just turned', 'innocent'],
                'severity': 'HIGH',
                'authorities': ['NCMEC', 'LOCAL_PD']
            },
            'drug_related': {
                'keywords': ['party favors', 'special treats', 'candy'],
                'severity': 'HIGH',
                'authorities': ['DEA', 'LOCAL_PD']
            },
            'money_laundering': {
                'keywords': ['cash only', 'no questions', 'anonymous'],
                'severity': 'MEDIUM',
                'authorities': ['FBI', 'FINRA']
            }
        }

    def analyze_suspicious_activity(self, content: str, metadata: Dict) -> Dict[str, Any]:
        """Analyze content for suspicious activity patterns"""
        detected_activities = []
        highest_severity = 'LOW'
        content_lower = content.lower()

        for category, config in self.activity_categories.items():
            keyword_matches = []
            for keyword in config['keywords']:
                if keyword in content_lower:
                    keyword_matches.append(keyword)

            if keyword_matches:
                activity = {
                    'category': category,
                    'severity': config['severity'],
                    'matched_keywords': keyword_matches,
                    'authorities': config['authorities']
                }
                detected_activities.append(activity)

                # Update highest severity
                severity_order = {'CRITICAL': 4, 'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}
                if severity_order[config['severity']] > severity_order[highest_severity]:
                    highest_severity = config['severity']

        # Additional pattern analysis
        suspicious_patterns = self.check_behavioral_patterns(content, metadata)

        return {
            'detected_activities': detected_activities,
            'highest_severity': highest_severity,
            'requires_reporting': len(detected_activities) > 0,
            'behavioral_patterns': suspicious_patterns,
            'analysis_timestamp': datetime.utcnow().isoformat()
        }

    def check_behavioral_patterns(self, content: str, metadata: Dict) -> List[Dict]:
        """Check for suspicious behavioral patterns"""
        patterns = []

        # Check for urgency indicators
        urgency_words = ['urgent', 'immediate', 'asap', 'now', 'tonight']
        if any(word in content.lower() for word in urgency_words):
            patterns.append({
                'type': 'urgency_indicators',
                'description': 'Content contains urgency language',
                'risk_level': 'MEDIUM'
            })

        # Check for secrecy indicators
        secrecy_words = ['secret', 'discreet', 'private', 'confidential', 'between us']
        if any(word in content.lower() for word in secrecy_words):
            patterns.append({
                'type': 'secrecy_indicators',
                'description': 'Content suggests secrecy or discretion',
                'risk_level': 'MEDIUM'
            })

        # Check for financial indicators
        if '$' in content or any(word in content.lower() for word in ['money', 'cash', 'payment']):
            patterns.append({
                'type': 'financial_transaction',
                'description': 'Content mentions financial transactions',
                'risk_level': 'LOW'
            })

        # Check for geographic dispersion
        location_data = metadata.get('location', {})
        if location_data.get('state') and location_data.get('city'):
            patterns.append({
                'type': 'location_tracking',
                'description': 'Activity has geographic location data',
                'risk_level': 'LOW'
            })

        return patterns

    def create_report(self, analysis: Dict, content: str, metadata: Dict) -> Dict[str, Any]:
        """Create detailed suspicious activity report"""
        report_id = hashlib.sha256(
            f"{content[:100]}{datetime.utcnow().isoformat()}".encode()
        ).hexdigest()[:16]

        report = {
            'report_id': report_id,
            'timestamp': datetime.utcnow().isoformat(),
            'analysis': analysis,
            'content_hash': hashlib.sha256(content.encode()).hexdigest(),
            'metadata': {
                'platform': metadata.get('platform', 'unknown'),
                'user_agent': metadata.get('user_agent', 'unknown'),
                'ip_location': metadata.get('location', {}),
                'reported_by': 'AEIMS_AUTOMATED_SYSTEM'
            },
            'evidence': {
                'content_length': len(content),
                'contains_media': metadata.get('has_media', False),
                'external_links': metadata.get('external_links', [])
            },
            'status': 'PENDING_REVIEW'
        }

        return report

    def store_evidence(self, report: Dict, content: str) -> Dict[str, Any]:
        """Store evidence securely for investigation"""
        try:
            bucket_name = 'aeims-suspicious-activity-evidence'
            object_key = f"reports/{report['report_id']}/evidence.json"

            evidence_package = {
                'report': report,
                'content': content,
                'stored_timestamp': datetime.utcnow().isoformat()
            }

            # Upload to S3 with encryption
            self.s3.put_object(
                Bucket=bucket_name,
                Key=object_key,
                Body=json.dumps(evidence_package),
                ServerSideEncryption='aws:kms'
            )

            return {
                'evidence_stored': True,
                'storage_location': f"s3://{bucket_name}/{object_key}",
                'report_id': report['report_id']
            }

        except Exception as e:
            logger.error(f"Error storing evidence: {str(e)}")
            return {
                'evidence_stored': False,
                'error': str(e)
            }

    def notify_authorities(self, report: Dict) -> Dict[str, Any]:
        """Notify appropriate authorities of suspicious activity"""
        notifications_sent = []

        try:
            # Determine which authorities to notify
            all_authorities = set()
            for activity in report['analysis']['detected_activities']:
                all_authorities.update(activity['authorities'])

            # Create notification message
            message = {
                'report_id': report['report_id'],
                'timestamp': report['timestamp'],
                'severity': report['analysis']['highest_severity'],
                'activities': [a['category'] for a in report['analysis']['detected_activities']],
                'platform': report['metadata']['platform'],
                'requires_immediate_attention': report['analysis']['highest_severity'] == 'CRITICAL'
            }

            # Send notifications to each authority
            for authority in all_authorities:
                topic_arn = f"arn:aws:sns:us-east-1:123456789012:suspicious-activity-{authority.lower()}"

                try:
                    response = self.sns.publish(
                        TopicArn=topic_arn,
                        Subject=f"Suspicious Activity Report - {report['analysis']['highest_severity']}",
                        Message=json.dumps(message, indent=2)
                    )

                    notifications_sent.append({
                        'authority': authority,
                        'status': 'SENT',
                        'message_id': response['MessageId']
                    })

                    logger.info(f"Notification sent to {authority}: {response['MessageId']}")

                except Exception as e:
                    notifications_sent.append({
                        'authority': authority,
                        'status': 'FAILED',
                        'error': str(e)
                    })
                    logger.error(f"Failed to notify {authority}: {str(e)}")

            return {
                'notifications_sent': notifications_sent,
                'total_notifications': len(all_authorities),
                'successful_notifications': len([n for n in notifications_sent if n['status'] == 'SENT'])
            }

        except Exception as e:
            logger.error(f"Error notifying authorities: {str(e)}")
            return {
                'notifications_sent': [],
                'error': str(e)
            }

def lambda_handler(event, context):
    """Main Lambda handler for suspicious activity reporting"""
    try:
        content = event.get('content', '')
        metadata = event.get('metadata', {})
        user_id = event.get('user_id', 'anonymous')

        if not content:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No content provided for analysis'
                })
            }

        reporter = SuspiciousActivityReporter()

        # Analyze content for suspicious activity
        analysis = reporter.analyze_suspicious_activity(content, metadata)

        if analysis['requires_reporting']:
            # Create detailed report
            report = reporter.create_report(analysis, content, metadata)

            # Store evidence securely
            evidence_result = reporter.store_evidence(report, content)

            # Notify authorities if critical or high severity
            notification_result = {}
            if analysis['highest_severity'] in ['CRITICAL', 'HIGH']:
                notification_result = reporter.notify_authorities(report)

                # Log critical reports
                if analysis['highest_severity'] == 'CRITICAL':
                    logger.critical(f"CRITICAL SUSPICIOUS ACTIVITY REPORTED: "
                                  f"ID={report['report_id']}, "
                                  f"Categories={[a['category'] for a in analysis['detected_activities']]}")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'report_created': True,
                    'report_id': report['report_id'],
                    'severity': analysis['highest_severity'],
                    'activities_detected': len(analysis['detected_activities']),
                    'evidence_storage': evidence_result,
                    'authority_notifications': notification_result,
                    'requires_immediate_attention': analysis['highest_severity'] == 'CRITICAL'
                }, default=str)
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'report_created': False,
                    'reason': 'No suspicious activity detected',
                    'analysis': analysis
                }, default=str)
            }

    except Exception as e:
        logger.error(f"Error in suspicious activity reporter: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }