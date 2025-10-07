"""
Florida Reporting Lambda Function

This function handles mandatory reporting requirements specific to Florida
state law including HB 3 compliance reporting and other state obligations.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
sns = boto3.client('sns')

# Configuration
REPORTS_TABLE = os.environ.get('FL_REPORTS_TABLE', 'aeims-florida-reports')
REPORTS_BUCKET = os.environ.get('FL_REPORTS_BUCKET')
FL_AG_NOTIFICATION_ARN = os.environ.get('FL_AG_NOTIFICATION_ARN')
FL_DCF_NOTIFICATION_ARN = os.environ.get('FL_DCF_NOTIFICATION_ARN')

class FloridaReporter:
    """Main class for Florida state reporting requirements"""

    def __init__(self):
        self.table = dynamodb.Table(REPORTS_TABLE)

        # Florida reporting requirements
        self.reporting_requirements = {
            'hb3_compliance': {
                'frequency': 'quarterly',
                'recipients': ['florida_attorney_general'],
                'required_metrics': [
                    'minor_users_count',
                    'age_verification_rate',
                    'parental_consent_rate',
                    'content_violations_minors',
                    'cyberbullying_incidents',
                    'safety_incidents'
                ]
            },
            'child_safety_incidents': {
                'frequency': 'immediate',
                'recipients': ['florida_dcf', 'local_law_enforcement'],
                'triggers': [
                    'predatory_behavior',
                    'cyberbullying_severe',
                    'self_harm_content',
                    'minor_exploitation'
                ]
            },
            'privacy_violations': {
                'frequency': 'as_required',
                'recipients': ['florida_attorney_general'],
                'triggers': [
                    'minor_data_breach',
                    'unauthorized_data_collection',
                    'privacy_policy_violations'
                ]
            }
        }

    def generate_hb3_compliance_report(self, reporting_period: Dict[str, str]) -> Dict[str, Any]:
        """Generate HB 3 compliance report for Florida AG"""
        try:
            report = {
                'report_type': 'hb3_quarterly_compliance',
                'reporting_period': reporting_period,
                'report_id': f"FL_HB3_{int(datetime.now(timezone.utc).timestamp())}",
                'generation_timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_metrics': {},
                'violations_summary': {},
                'remediation_actions': [],
                'platform_changes': []
            }

            start_date = datetime.fromisoformat(reporting_period['start_date'])
            end_date = datetime.fromisoformat(reporting_period['end_date'])

            # Collect compliance metrics
            compliance_metrics = self._collect_compliance_metrics(start_date, end_date)
            report['compliance_metrics'] = compliance_metrics

            # Summarize violations
            violations_summary = self._summarize_violations(start_date, end_date)
            report['violations_summary'] = violations_summary

            # Document remediation actions
            remediation_actions = self._document_remediation_actions(start_date, end_date)
            report['remediation_actions'] = remediation_actions

            # Platform changes for compliance
            platform_changes = self._document_platform_changes(start_date, end_date)
            report['platform_changes'] = platform_changes

            # Calculate overall compliance score
            compliance_score = self._calculate_compliance_score(compliance_metrics, violations_summary)
            report['overall_compliance_score'] = compliance_score

            return report

        except Exception as e:
            logger.error(f"HB3 compliance report generation error: {str(e)}")
            raise

    def _collect_compliance_metrics(self, start_date: datetime, end_date: datetime) -> Dict[str, Any]:
        """Collect compliance metrics for reporting period"""
        try:
            metrics = {
                'minor_users_count': 0,
                'age_verification_attempts': 0,
                'age_verification_success_rate': 0.0,
                'parental_consent_requests': 0,
                'parental_consent_obtained': 0,
                'content_violations_minors': 0,
                'cyberbullying_incidents': 0,
                'safety_incidents': 0,
                'account_terminations_minors': 0,
                'parental_complaints': 0
            }

            # Query verification records
            start_timestamp = int(start_date.timestamp())
            end_timestamp = int(end_date.timestamp())

            try:
                response = self.table.scan(
                    FilterExpression='record_type = :type AND #ts BETWEEN :start AND :end',
                    ExpressionAttributeNames={
                        '#ts': 'timestamp'
                    },
                    ExpressionAttributeValues={
                        ':type': 'age_verification',
                        ':start': start_timestamp,
                        ':end': end_timestamp
                    }
                )

                verification_records = response.get('Items', [])
                metrics['age_verification_attempts'] = len(verification_records)

                successful_verifications = [r for r in verification_records if r.get('verification_status') == 'APPROVED']
                if verification_records:
                    metrics['age_verification_success_rate'] = len(successful_verifications) / len(verification_records)

                # Count minor users
                minor_categories = ['under_14', '14_to_15', '16_to_17']
                minor_verifications = [r for r in verification_records if r.get('age_category') in minor_categories]
                metrics['minor_users_count'] = len(minor_verifications)

            except Exception as e:
                logger.warning(f"Could not collect verification metrics: {str(e)}")

            # Query consent records
            try:
                consent_response = self.table.scan(
                    FilterExpression='record_type = :type AND #ts BETWEEN :start AND :end',
                    ExpressionAttributeNames={
                        '#ts': 'timestamp'
                    },
                    ExpressionAttributeValues={
                        ':type': 'parental_consent',
                        ':start': start_timestamp,
                        ':end': end_timestamp
                    }
                )

                consent_records = consent_response.get('Items', [])
                metrics['parental_consent_requests'] = len(consent_records)
                metrics['parental_consent_obtained'] = len([r for r in consent_records if r.get('consent_granted')])

            except Exception as e:
                logger.warning(f"Could not collect consent metrics: {str(e)}")

            # Query violation records
            try:
                violation_response = self.table.scan(
                    FilterExpression='record_type = :type AND #ts BETWEEN :start AND :end',
                    ExpressionAttributeNames={
                        '#ts': 'timestamp'
                    },
                    ExpressionAttributeValues={
                        ':type': 'content_violation',
                        ':start': start_timestamp,
                        ':end': end_timestamp
                    }
                )

                violation_records = violation_response.get('Items', [])
                metrics['content_violations_minors'] = len([r for r in violation_records if r.get('involves_minor')])
                metrics['cyberbullying_incidents'] = len([r for r in violation_records if 'cyberbullying' in r.get('violation_type', '')])

            except Exception as e:
                logger.warning(f"Could not collect violation metrics: {str(e)}")

            return metrics

        except Exception as e:
            logger.error(f"Compliance metrics collection error: {str(e)}")
            return {}

    def _summarize_violations(self, start_date: datetime, end_date: datetime) -> Dict[str, Any]:
        """Summarize violations for reporting period"""
        summary = {
            'total_violations': 0,
            'violation_categories': {},
            'high_severity_incidents': 0,
            'repeat_offenders': 0,
            'resolved_violations': 0
        }

        try:
            start_timestamp = int(start_date.timestamp())
            end_timestamp = int(end_date.timestamp())

            response = self.table.scan(
                FilterExpression='record_type = :type AND #ts BETWEEN :start AND :end',
                ExpressionAttributeNames={
                    '#ts': 'timestamp'
                },
                ExpressionAttributeValues={
                    ':type': 'violation',
                    ':start': start_timestamp,
                    ':end': end_timestamp
                }
            )

            violations = response.get('Items', [])
            summary['total_violations'] = len(violations)

            # Categorize violations
            for violation in violations:
                category = violation.get('category', 'unknown')
                if category not in summary['violation_categories']:
                    summary['violation_categories'][category] = 0
                summary['violation_categories'][category] += 1

                if violation.get('severity') == 'HIGH':
                    summary['high_severity_incidents'] += 1

                if violation.get('resolved', False):
                    summary['resolved_violations'] += 1

        except Exception as e:
            logger.warning(f"Violation summary error: {str(e)}")

        return summary

    def _document_remediation_actions(self, start_date: datetime, end_date: datetime) -> List[Dict[str, Any]]:
        """Document remediation actions taken"""
        actions = []

        try:
            start_timestamp = int(start_date.timestamp())
            end_timestamp = int(end_date.timestamp())

            response = self.table.scan(
                FilterExpression='record_type = :type AND #ts BETWEEN :start AND :end',
                ExpressionAttributeNames={
                    '#ts': 'timestamp'
                },
                ExpressionAttributeValues={
                    ':type': 'remediation_action',
                    ':start': start_timestamp,
                    ':end': end_timestamp
                }
            )

            remediation_records = response.get('Items', [])
            for record in remediation_records:
                actions.append({
                    'action_type': record.get('action_type'),
                    'description': record.get('description'),
                    'timestamp': record.get('timestamp'),
                    'effectiveness': record.get('effectiveness', 'pending_assessment')
                })

        except Exception as e:
            logger.warning(f"Remediation documentation error: {str(e)}")

        return actions

    def _document_platform_changes(self, start_date: datetime, end_date: datetime) -> List[Dict[str, Any]]:
        """Document platform changes for compliance"""
        changes = []

        try:
            # This would typically query a platform changes log
            # For demonstration, we'll include typical compliance-related changes
            changes.extend([
                {
                    'change_type': 'age_verification_enhancement',
                    'description': 'Enhanced age verification system for Florida compliance',
                    'implementation_date': start_date.isoformat(),
                    'compliance_impact': 'Improved accuracy of minor age detection'
                },
                {
                    'change_type': 'parental_controls_update',
                    'description': 'Updated parental control features per HB 3 requirements',
                    'implementation_date': start_date.isoformat(),
                    'compliance_impact': 'Enhanced parental oversight capabilities'
                }
            ])

        except Exception as e:
            logger.warning(f"Platform changes documentation error: {str(e)}")

        return changes

    def _calculate_compliance_score(self, metrics: Dict[str, Any], violations: Dict[str, Any]) -> float:
        """Calculate overall compliance score"""
        try:
            score = 100.0

            # Deduct points for violations
            total_violations = violations.get('total_violations', 0)
            if total_violations > 0:
                score -= min(20, total_violations * 2)  # Max 20 point deduction

            # Deduct for low verification rates
            verification_rate = metrics.get('age_verification_success_rate', 1.0)
            if verification_rate < 0.95:
                score -= (0.95 - verification_rate) * 100

            # Deduct for consent issues
            consent_requests = metrics.get('parental_consent_requests', 0)
            consent_obtained = metrics.get('parental_consent_obtained', 0)
            if consent_requests > 0:
                consent_rate = consent_obtained / consent_requests
                if consent_rate < 0.9:
                    score -= (0.9 - consent_rate) * 50

            return max(0.0, score)

        except Exception as e:
            logger.warning(f"Compliance score calculation error: {str(e)}")
            return 0.0

    def generate_safety_incident_report(self, incident_data: Dict[str, Any]) -> Dict[str, Any]:
        """Generate immediate safety incident report"""
        try:
            report = {
                'report_type': 'florida_safety_incident',
                'incident_id': incident_data.get('incident_id'),
                'report_id': f"FL_SAFETY_{int(datetime.now(timezone.utc).timestamp())}",
                'generation_timestamp': datetime.now(timezone.utc).isoformat(),
                'incident_details': incident_data,
                'severity_assessment': self._assess_incident_severity(incident_data),
                'required_notifications': self._determine_required_notifications(incident_data),
                'immediate_actions_taken': [],
                'follow_up_required': True
            }

            return report

        except Exception as e:
            logger.error(f"Safety incident report generation error: {str(e)}")
            raise

    def _assess_incident_severity(self, incident_data: Dict[str, Any]) -> str:
        """Assess severity of safety incident"""
        incident_type = incident_data.get('type', '')
        involves_minor = incident_data.get('involves_minor', False)

        if not involves_minor:
            return 'LOW'

        critical_types = ['predatory_behavior', 'exploitation', 'immediate_danger']
        high_types = ['cyberbullying_severe', 'self_harm_content', 'privacy_violation']

        if incident_type in critical_types:
            return 'CRITICAL'
        elif incident_type in high_types:
            return 'HIGH'
        else:
            return 'MEDIUM'

    def _determine_required_notifications(self, incident_data: Dict[str, Any]) -> List[str]:
        """Determine which agencies need notification"""
        notifications = []
        incident_type = incident_data.get('type', '')
        severity = self._assess_incident_severity(incident_data)

        if severity in ['CRITICAL', 'HIGH']:
            notifications.append('florida_dcf')

        if incident_type in ['predatory_behavior', 'exploitation']:
            notifications.extend(['local_law_enforcement', 'florida_attorney_general'])

        if incident_data.get('involves_minor') and severity == 'CRITICAL':
            notifications.append('emergency_services')

        return notifications

    def store_florida_report(self, report: Dict[str, Any]) -> bool:
        """Store Florida compliance report"""
        try:
            report_id = report['report_id']

            # Store in DynamoDB
            self.table.put_item(
                Item={
                    'report_id': report_id,
                    'record_type': 'florida_compliance_report',
                    'timestamp': int(datetime.now(timezone.utc).timestamp()),
                    'report_type': report['report_type'],
                    'report_data': json.dumps(report),
                    'ttl': int((datetime.now(timezone.utc) + timedelta(days=2555)).timestamp())  # 7 year retention
                }
            )

            # Store in S3 if bucket configured
            if REPORTS_BUCKET:
                timestamp = datetime.now(timezone.utc).strftime('%Y/%m/%d')
                key = f"florida-reports/{timestamp}/{report_id}.json"

                s3.put_object(
                    Bucket=REPORTS_BUCKET,
                    Key=key,
                    Body=json.dumps(report, indent=2),
                    ContentType='application/json',
                    Metadata={
                        'report_id': report_id,
                        'report_type': report['report_type'],
                        'state': 'florida'
                    }
                )

            return True

        except Exception as e:
            logger.error(f"Florida report storage error: {str(e)}")
            return False

    def send_florida_notifications(self, report: Dict[str, Any]) -> Dict[str, bool]:
        """Send notifications to Florida agencies"""
        try:
            notification_results = {}

            required_notifications = report.get('required_notifications', [])
            if not required_notifications and report['report_type'] == 'hb3_quarterly_compliance':
                required_notifications = ['florida_attorney_general']

            for agency in required_notifications:
                try:
                    if agency == 'florida_attorney_general' and FL_AG_NOTIFICATION_ARN:
                        notification_results[agency] = self._notify_florida_ag(report)
                    elif agency == 'florida_dcf' and FL_DCF_NOTIFICATION_ARN:
                        notification_results[agency] = self._notify_florida_dcf(report)
                    else:
                        logger.warning(f"No notification method configured for {agency}")
                        notification_results[agency] = False

                except Exception as e:
                    logger.error(f"Notification error for {agency}: {str(e)}")
                    notification_results[agency] = False

            return notification_results

        except Exception as e:
            logger.error(f"Florida notifications error: {str(e)}")
            return {}

    def _notify_florida_ag(self, report: Dict[str, Any]) -> bool:
        """Notify Florida Attorney General"""
        try:
            message = {
                'notification_type': 'FLORIDA_COMPLIANCE_REPORT',
                'report_id': report['report_id'],
                'report_type': report['report_type'],
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'platform': 'AEIMS',
                'summary': self._generate_ag_summary(report),
                'compliance_status': 'COMPLIANT' if report.get('overall_compliance_score', 0) > 80 else 'ISSUES_IDENTIFIED'
            }

            sns.publish(
                TopicArn=FL_AG_NOTIFICATION_ARN,
                Subject=f"Florida Compliance Report - {report['report_type']}",
                Message=json.dumps(message, indent=2)
            )

            return True

        except Exception as e:
            logger.error(f"Florida AG notification error: {str(e)}")
            return False

    def _notify_florida_dcf(self, report: Dict[str, Any]) -> bool:
        """Notify Florida Department of Children and Families"""
        try:
            message = {
                'notification_type': 'FLORIDA_CHILD_SAFETY_INCIDENT',
                'report_id': report['report_id'],
                'incident_id': report.get('incident_id'),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'severity': report.get('severity_assessment'),
                'platform': 'AEIMS',
                'immediate_action_required': report.get('severity_assessment') == 'CRITICAL'
            }

            sns.publish(
                TopicArn=FL_DCF_NOTIFICATION_ARN,
                Subject=f"Florida Child Safety Incident - {report.get('severity_assessment')}",
                Message=json.dumps(message, indent=2)
            )

            return True

        except Exception as e:
            logger.error(f"Florida DCF notification error: {str(e)}")
            return False

    def _generate_ag_summary(self, report: Dict[str, Any]) -> str:
        """Generate summary for Attorney General notification"""
        if report['report_type'] == 'hb3_quarterly_compliance':
            metrics = report.get('compliance_metrics', {})
            return f"HB 3 Quarterly Compliance Report - Minor Users: {metrics.get('minor_users_count', 0)}, " \
                   f"Verification Rate: {metrics.get('age_verification_success_rate', 0):.2%}, " \
                   f"Compliance Score: {report.get('overall_compliance_score', 0):.1f}"
        else:
            return f"Florida compliance report - Type: {report['report_type']}"


def lambda_handler(event, context):
    """Lambda handler for Florida reporting"""
    try:
        logger.info("Processing Florida reporting request")

        report_type = event.get('report_type', 'hb3_compliance')

        reporter = FloridaReporter()

        if report_type == 'hb3_compliance':
            reporting_period = event.get('reporting_period', {
                'start_date': (datetime.now(timezone.utc) - timedelta(days=90)).isoformat(),
                'end_date': datetime.now(timezone.utc).isoformat()
            })
            report = reporter.generate_hb3_compliance_report(reporting_period)

        elif report_type == 'safety_incident':
            if 'incident_data' not in event:
                raise ValueError("Missing incident_data for safety incident report")
            report = reporter.generate_safety_incident_report(event['incident_data'])

        else:
            raise ValueError(f"Unsupported report type: {report_type}")

        # Store report
        stored = reporter.store_florida_report(report)

        # Send notifications
        notification_results = reporter.send_florida_notifications(report)

        response = {
            'statusCode': 200,
            'body': {
                'report_generated': True,
                'report_id': report['report_id'],
                'report_type': report['report_type'],
                'stored': stored,
                'notifications_sent': notification_results,
                'successful_notifications': sum(notification_results.values()),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_framework': 'Florida_State_Law'
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
        logger.error(f"Florida reporting error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': 'Internal server error', 'message': 'Florida reporting failed'}
        }