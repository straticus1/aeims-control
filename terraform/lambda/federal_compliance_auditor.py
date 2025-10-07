"""
Federal Compliance Auditor Lambda Function

This function performs comprehensive audits of federal compliance requirements
including FOSTA-SESTA, COPPA, Section 230, and other federal regulations.

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
cloudwatch = boto3.client('cloudwatch')

# Configuration
AUDIT_TABLE = os.environ.get('FEDERAL_AUDIT_TABLE', 'aeims-federal-compliance-audits')
COMPLIANCE_BUCKET = os.environ.get('COMPLIANCE_BUCKET')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')

class FederalComplianceAuditor:
    """Main class for federal compliance auditing"""

    def __init__(self):
        self.table = dynamodb.Table(AUDIT_TABLE)

        self.federal_requirements = {
            'fosta_sesta': {
                'name': 'Fight Online Sex Trafficking Act',
                'requirements': [
                    'content_monitoring_active',
                    'law_enforcement_reporting',
                    'user_verification_systems',
                    'evidence_preservation'
                ],
                'metrics': ['detection_rate', 'response_time', 'reporting_compliance']
            },
            'coppa': {
                'name': 'Children\'s Online Privacy Protection Act',
                'requirements': [
                    'age_verification_under_13',
                    'parental_consent_mechanisms',
                    'data_minimization_children',
                    'safe_harbor_compliance'
                ],
                'metrics': ['age_verification_rate', 'consent_compliance', 'data_protection_score']
            },
            'section_230': {
                'name': 'Communications Decency Act Section 230',
                'requirements': [
                    'good_faith_moderation',
                    'neutral_platform_operations',
                    'user_generated_content_policies',
                    'notice_takedown_procedures'
                ],
                'metrics': ['moderation_consistency', 'response_timeliness', 'policy_enforcement']
            },
            'interstate_commerce': {
                'name': 'Interstate Commerce Regulations',
                'requirements': [
                    'cross_state_activity_monitoring',
                    'federal_jurisdiction_compliance',
                    'commerce_clause_adherence'
                ],
                'metrics': ['interstate_detection_rate', 'compliance_score']
            }
        }

    def audit_fosta_sesta_compliance(self) -> Dict[str, Any]:
        """Audit FOSTA-SESTA compliance"""
        try:
            audit_result = {
                'regulation': 'fosta_sesta',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'score': 100.0
            }

            # Check content monitoring metrics
            try:
                end_time = datetime.now(timezone.utc)
                start_time = end_time - timedelta(hours=24)

                # Content detection rate
                detection_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/FOSTACompliance',
                    MetricName='ContentDetectionRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if detection_metrics['Datapoints']:
                    detection_rate = detection_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['content_detection_rate'] = detection_rate

                    if detection_rate < 0.95:
                        audit_result['status'] = 'NON_COMPLIANT'
                        audit_result['findings'].append({
                            'severity': 'HIGH',
                            'issue': 'Content detection rate below FOSTA threshold',
                            'current': detection_rate,
                            'required': 0.95
                        })
                        audit_result['score'] -= 25

                # Law enforcement reporting timeliness
                reporting_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/LawEnforcement',
                    MetricName='ReportingTimeliness',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if reporting_metrics['Datapoints']:
                    reporting_time = reporting_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['avg_reporting_time'] = reporting_time

                    if reporting_time > 3600:  # 1 hour threshold
                        audit_result['status'] = 'NON_COMPLIANT'
                        audit_result['findings'].append({
                            'severity': 'CRITICAL',
                            'issue': 'Law enforcement reporting exceeds time limits',
                            'current': reporting_time,
                            'required': 3600
                        })
                        audit_result['score'] -= 40

            except Exception as e:
                audit_result['findings'].append({
                    'severity': 'HIGH',
                    'issue': 'Unable to retrieve FOSTA compliance metrics',
                    'error': str(e)
                })
                audit_result['score'] -= 20

            return audit_result

        except Exception as e:
            logger.error(f"FOSTA-SESTA audit error: {str(e)}")
            return {
                'regulation': 'fosta_sesta',
                'status': 'AUDIT_FAILED',
                'error': str(e),
                'score': 0.0
            }

    def audit_coppa_compliance(self) -> Dict[str, Any]:
        """Audit COPPA compliance"""
        try:
            audit_result = {
                'regulation': 'coppa',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'score': 100.0
            }

            # Check age verification metrics
            try:
                end_time = datetime.now(timezone.utc)
                start_time = end_time - timedelta(hours=24)

                age_verification_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/COPPA',
                    MetricName='AgeVerificationRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if age_verification_metrics['Datapoints']:
                    verification_rate = age_verification_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['age_verification_rate'] = verification_rate

                    if verification_rate < 1.0:  # Must be 100% for under 13
                        audit_result['status'] = 'NON_COMPLIANT'
                        audit_result['findings'].append({
                            'severity': 'CRITICAL',
                            'issue': 'Age verification not at 100% for users under 13',
                            'current': verification_rate,
                            'required': 1.0
                        })
                        audit_result['score'] -= 50

                # Check parental consent compliance
                consent_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/COPPA',
                    MetricName='ParentalConsentRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if consent_metrics['Datapoints']:
                    consent_rate = consent_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['parental_consent_rate'] = consent_rate

                    if consent_rate < 1.0:
                        audit_result['status'] = 'NON_COMPLIANT'
                        audit_result['findings'].append({
                            'severity': 'CRITICAL',
                            'issue': 'Parental consent not obtained for all required users',
                            'current': consent_rate,
                            'required': 1.0
                        })
                        audit_result['score'] -= 30

            except Exception as e:
                audit_result['findings'].append({
                    'severity': 'HIGH',
                    'issue': 'Unable to retrieve COPPA compliance metrics',
                    'error': str(e)
                })
                audit_result['score'] -= 25

            return audit_result

        except Exception as e:
            logger.error(f"COPPA audit error: {str(e)}")
            return {
                'regulation': 'coppa',
                'status': 'AUDIT_FAILED',
                'error': str(e),
                'score': 0.0
            }

    def audit_section_230_compliance(self) -> Dict[str, Any]:
        """Audit Section 230 compliance"""
        try:
            audit_result = {
                'regulation': 'section_230',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'score': 100.0
            }

            # Check content moderation consistency
            try:
                end_time = datetime.now(timezone.utc)
                start_time = end_time - timedelta(hours=24)

                moderation_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/ContentModeration',
                    MetricName='ModerationConsistency',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if moderation_metrics['Datapoints']:
                    consistency_score = moderation_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['moderation_consistency'] = consistency_score

                    if consistency_score < 0.85:
                        audit_result['findings'].append({
                            'severity': 'MEDIUM',
                            'issue': 'Content moderation consistency below best practices',
                            'current': consistency_score,
                            'recommended': 0.85
                        })
                        audit_result['score'] -= 15

                # Check response timeliness
                response_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/ContentModeration',
                    MetricName='ResponseTimeliness',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if response_metrics['Datapoints']:
                    response_time = response_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['avg_response_time'] = response_time

                    if response_time > 1800:  # 30 minutes
                        audit_result['findings'].append({
                            'severity': 'MEDIUM',
                            'issue': 'Content moderation response time exceeds best practices',
                            'current': response_time,
                            'recommended': 1800
                        })
                        audit_result['score'] -= 10

            except Exception as e:
                audit_result['findings'].append({
                    'severity': 'MEDIUM',
                    'issue': 'Unable to retrieve Section 230 compliance metrics',
                    'error': str(e)
                })
                audit_result['score'] -= 15

            return audit_result

        except Exception as e:
            logger.error(f"Section 230 audit error: {str(e)}")
            return {
                'regulation': 'section_230',
                'status': 'AUDIT_FAILED',
                'error': str(e),
                'score': 0.0
            }

    def audit_interstate_commerce_compliance(self) -> Dict[str, Any]:
        """Audit Interstate Commerce compliance"""
        try:
            audit_result = {
                'regulation': 'interstate_commerce',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'score': 100.0
            }

            # Check interstate activity detection
            try:
                end_time = datetime.now(timezone.utc)
                start_time = end_time - timedelta(hours=24)

                detection_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/InterstateCommerce',
                    MetricName='DetectionRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if detection_metrics['Datapoints']:
                    detection_rate = detection_metrics['Datapoints'][-1]['Average']
                    audit_result['metrics']['interstate_detection_rate'] = detection_rate

                    if detection_rate < 0.9:
                        audit_result['findings'].append({
                            'severity': 'MEDIUM',
                            'issue': 'Interstate commerce detection rate below threshold',
                            'current': detection_rate,
                            'required': 0.9
                        })
                        audit_result['score'] -= 20

            except Exception as e:
                audit_result['findings'].append({
                    'severity': 'MEDIUM',
                    'issue': 'Unable to retrieve interstate commerce metrics',
                    'error': str(e)
                })
                audit_result['score'] -= 15

            return audit_result

        except Exception as e:
            logger.error(f"Interstate commerce audit error: {str(e)}")
            return {
                'regulation': 'interstate_commerce',
                'status': 'AUDIT_FAILED',
                'error': str(e),
                'score': 0.0
            }

    def generate_federal_compliance_report(self, audit_results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate comprehensive federal compliance report"""
        try:
            report = {
                'audit_id': f"FEDERAL_AUDIT_{int(datetime.now(timezone.utc).timestamp())}",
                'audit_timestamp': datetime.now(timezone.utc).isoformat(),
                'overall_compliance_status': 'COMPLIANT',
                'regulation_audits': audit_results,
                'summary': {
                    'total_regulations': len(audit_results),
                    'compliant_regulations': 0,
                    'non_compliant_regulations': 0,
                    'failed_audits': 0,
                    'overall_score': 0.0,
                    'critical_findings': 0,
                    'high_findings': 0,
                    'medium_findings': 0
                },
                'action_items': [],
                'next_audit_due': (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
            }

            total_score = 0.0
            for audit_result in audit_results:
                status = audit_result.get('status', 'UNKNOWN')
                score = audit_result.get('score', 0.0)
                total_score += score

                if status == 'COMPLIANT':
                    report['summary']['compliant_regulations'] += 1
                elif status == 'NON_COMPLIANT':
                    report['summary']['non_compliant_regulations'] += 1
                    report['overall_compliance_status'] = 'NON_COMPLIANT'
                elif status == 'AUDIT_FAILED':
                    report['summary']['failed_audits'] += 1
                    report['overall_compliance_status'] = 'AUDIT_INCOMPLETE'

                # Count findings by severity
                for finding in audit_result.get('findings', []):
                    severity = finding.get('severity', 'UNKNOWN').upper()
                    if severity == 'CRITICAL':
                        report['summary']['critical_findings'] += 1
                    elif severity == 'HIGH':
                        report['summary']['high_findings'] += 1
                    elif severity == 'MEDIUM':
                        report['summary']['medium_findings'] += 1

            report['summary']['overall_score'] = total_score / max(len(audit_results), 1)

            # Generate action items
            if report['summary']['critical_findings'] > 0:
                report['action_items'].append({
                    'priority': 'IMMEDIATE',
                    'action': 'Address critical federal compliance violations',
                    'deadline': (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
                })

            if report['summary']['non_compliant_regulations'] > 0:
                report['action_items'].append({
                    'priority': 'HIGH',
                    'action': 'Remediate non-compliant regulations',
                    'deadline': (datetime.now(timezone.utc) + timedelta(hours=12)).isoformat()
                })

            return report

        except Exception as e:
            logger.error(f"Federal compliance report generation error: {str(e)}")
            raise

    def store_federal_audit_report(self, report: Dict[str, Any]) -> bool:
        """Store federal compliance audit report"""
        try:
            audit_id = report['audit_id']

            # Store in DynamoDB
            self.table.put_item(
                Item={
                    'audit_id': audit_id,
                    'audit_timestamp': int(datetime.now(timezone.utc).timestamp()),
                    'overall_status': report['overall_compliance_status'],
                    'overall_score': report['summary']['overall_score'],
                    'critical_findings': report['summary']['critical_findings'],
                    'non_compliant_regulations': report['summary']['non_compliant_regulations'],
                    'report_data': json.dumps(report),
                    'ttl': int((datetime.now(timezone.utc) + timedelta(days=365)).timestamp())
                }
            )

            # Store in S3 if bucket configured
            if COMPLIANCE_BUCKET:
                timestamp = datetime.now(timezone.utc).strftime('%Y/%m/%d')
                key = f"federal-compliance-audits/{timestamp}/{audit_id}.json"

                s3.put_object(
                    Bucket=COMPLIANCE_BUCKET,
                    Key=key,
                    Body=json.dumps(report, indent=2),
                    ContentType='application/json',
                    Metadata={
                        'audit_id': audit_id,
                        'compliance_status': report['overall_compliance_status'],
                        'audit_type': 'federal_compliance'
                    }
                )

            return True

        except Exception as e:
            logger.error(f"Federal audit report storage error: {str(e)}")
            return False

    def send_compliance_alerts(self, report: Dict[str, Any]) -> bool:
        """Send alerts for federal compliance issues"""
        try:
            if not ALERT_SNS_TOPIC:
                return False

            if (report['overall_compliance_status'] != 'COMPLIANT' or
                report['summary']['critical_findings'] > 0):

                alert = {
                    'alert_type': 'FEDERAL_COMPLIANCE_ISSUE',
                    'audit_id': report['audit_id'],
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'compliance_status': report['overall_compliance_status'],
                    'overall_score': report['summary']['overall_score'],
                    'critical_findings': report['summary']['critical_findings'],
                    'non_compliant_regulations': report['summary']['non_compliant_regulations'],
                    'action_items': report['action_items'],
                    'severity': 'CRITICAL' if report['summary']['critical_findings'] > 0 else 'HIGH'
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject=f"Federal Compliance Alert - {report['overall_compliance_status']}",
                    Message=json.dumps(alert, indent=2)
                )

                return True

            return False

        except Exception as e:
            logger.error(f"Federal compliance alert error: {str(e)}")
            return False


def lambda_handler(event, context):
    """Lambda handler for federal compliance auditing"""
    try:
        logger.info("Starting federal compliance audit")

        audit_type = event.get('audit_type', 'full')
        regulations = event.get('regulations', ['fosta_sesta', 'coppa', 'section_230', 'interstate_commerce'])

        auditor = FederalComplianceAuditor()
        audit_results = []

        for regulation in regulations:
            try:
                if regulation == 'fosta_sesta':
                    result = auditor.audit_fosta_sesta_compliance()
                elif regulation == 'coppa':
                    result = auditor.audit_coppa_compliance()
                elif regulation == 'section_230':
                    result = auditor.audit_section_230_compliance()
                elif regulation == 'interstate_commerce':
                    result = auditor.audit_interstate_commerce_compliance()
                else:
                    continue

                audit_results.append(result)

            except Exception as e:
                logger.error(f"Audit failed for regulation {regulation}: {str(e)}")
                audit_results.append({
                    'regulation': regulation,
                    'status': 'AUDIT_FAILED',
                    'error': str(e),
                    'score': 0.0
                })

        # Generate compliance report
        compliance_report = auditor.generate_federal_compliance_report(audit_results)

        # Store report
        stored = auditor.store_federal_audit_report(compliance_report)

        # Send alerts if necessary
        alert_sent = auditor.send_compliance_alerts(compliance_report)

        response = {
            'statusCode': 200,
            'body': {
                'audit_completed': True,
                'audit_id': compliance_report['audit_id'],
                'overall_compliance_status': compliance_report['overall_compliance_status'],
                'overall_score': compliance_report['summary']['overall_score'],
                'regulations_audited': len(audit_results),
                'compliant_regulations': compliance_report['summary']['compliant_regulations'],
                'non_compliant_regulations': compliance_report['summary']['non_compliant_regulations'],
                'critical_findings': compliance_report['summary']['critical_findings'],
                'alert_sent': alert_sent,
                'report_stored': stored,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }

        return response

    except Exception as e:
        logger.error(f"Federal compliance auditor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal server error',
                'message': 'Federal compliance audit failed',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }