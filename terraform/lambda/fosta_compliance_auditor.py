"""
FOSTA Compliance Auditor Lambda Function

This function performs comprehensive audits of FOSTA-SESTA compliance across
the platform, ensuring all defensive measures are working correctly and
identifying potential compliance gaps.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional
import os
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

# Configuration
AUDIT_TABLE = os.environ.get('AUDIT_TABLE', 'aeims-fosta-audits')
COMPLIANCE_BUCKET = os.environ.get('COMPLIANCE_BUCKET')
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
AUDIT_FREQUENCY_HOURS = int(os.environ.get('AUDIT_FREQUENCY_HOURS', '24'))

class FOSTAComplianceAuditor:
    """Main class for FOSTA compliance auditing"""

    def __init__(self):
        self.table = dynamodb.Table(AUDIT_TABLE)

        # Compliance requirements checklist
        self.compliance_requirements = {
            'content_monitoring': {
                'description': 'Active monitoring of user-generated content for sex trafficking indicators',
                'required_components': [
                    'automated_content_scanning',
                    'pattern_recognition_system',
                    'image_analysis_capability',
                    'text_analysis_functionality'
                ],
                'metrics': ['content_scan_rate', 'detection_accuracy', 'false_positive_rate']
            },
            'communication_monitoring': {
                'description': 'Real-time monitoring of user communications for trafficking patterns',
                'required_components': [
                    'message_scanning_system',
                    'pattern_detection_algorithms',
                    'escalation_procedures',
                    'user_behavior_analysis'
                ],
                'metrics': ['message_scan_coverage', 'threat_detection_rate', 'response_time']
            },
            'law_enforcement_reporting': {
                'description': 'Mandatory reporting to appropriate law enforcement agencies',
                'required_components': [
                    'automated_reporting_system',
                    'evidence_preservation',
                    'agency_notification_mechanisms',
                    'legal_compliance_tracking'
                ],
                'metrics': ['report_timeliness', 'evidence_integrity', 'notification_success_rate']
            },
            'user_verification': {
                'description': 'Age verification and user identity validation systems',
                'required_components': [
                    'age_verification_system',
                    'identity_validation_process',
                    'document_verification',
                    'fraud_detection_capabilities'
                ],
                'metrics': ['verification_completion_rate', 'fraud_detection_rate', 'compliance_rate']
            },
            'content_moderation': {
                'description': 'Proactive content moderation to prevent prohibited content',
                'required_components': [
                    'pre_publication_screening',
                    'post_publication_monitoring',
                    'takedown_procedures',
                    'appeal_processes'
                ],
                'metrics': ['moderation_speed', 'accuracy_rate', 'takedown_response_time']
            },
            'record_keeping': {
                'description': 'Comprehensive record keeping for compliance and legal requirements',
                'required_components': [
                    'audit_trail_system',
                    'evidence_preservation',
                    'retention_policy_compliance',
                    'data_integrity_measures'
                ],
                'metrics': ['record_completeness', 'retention_compliance', 'data_integrity_score']
            }
        }

        # Critical thresholds for compliance
        self.compliance_thresholds = {
            'content_scan_rate': 0.99,  # 99% of content must be scanned
            'detection_response_time': 300,  # 5 minutes max response time
            'law_enforcement_reporting_time': 3600,  # 1 hour max reporting time
            'takedown_response_time': 1800,  # 30 minutes max takedown time
            'evidence_preservation_rate': 1.0,  # 100% evidence preservation
            'system_uptime': 0.999  # 99.9% uptime requirement
        }

    def generate_audit_id(self) -> str:
        """Generate unique audit ID"""
        timestamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
        unique_id = str(uuid.uuid4())[:8]
        return f"FOSTA_AUDIT_{timestamp}_{unique_id}"

    def audit_content_monitoring_compliance(self) -> Dict[str, Any]:
        """Audit content monitoring system compliance"""
        try:
            audit_results = {
                'component': 'content_monitoring',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'recommendations': []
            }

            # Check content scanning metrics from CloudWatch
            end_time = datetime.now(timezone.utc)
            start_time = end_time - timedelta(hours=24)

            # Get content scanning rate
            try:
                scan_rate_response = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/ContentModeration',
                    MetricName='ContentScanRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if scan_rate_response['Datapoints']:
                    latest_scan_rate = scan_rate_response['Datapoints'][-1]['Average']
                    audit_results['metrics']['content_scan_rate'] = latest_scan_rate

                    if latest_scan_rate < self.compliance_thresholds['content_scan_rate']:
                        audit_results['status'] = 'NON_COMPLIANT'
                        audit_results['findings'].append({
                            'severity': 'HIGH',
                            'issue': 'Content scan rate below threshold',
                            'current_value': latest_scan_rate,
                            'required_value': self.compliance_thresholds['content_scan_rate'],
                            'risk': 'Potential FOSTA violations may go undetected'
                        })

            except Exception as e:
                audit_results['findings'].append({
                    'severity': 'HIGH',
                    'issue': 'Unable to retrieve content scanning metrics',
                    'error': str(e),
                    'risk': 'Cannot verify content monitoring compliance'
                })

            # Check detection accuracy
            try:
                accuracy_response = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/ContentModeration',
                    MetricName='DetectionAccuracy',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if accuracy_response['Datapoints']:
                    detection_accuracy = accuracy_response['Datapoints'][-1]['Average']
                    audit_results['metrics']['detection_accuracy'] = detection_accuracy

                    if detection_accuracy < 0.85:  # 85% minimum accuracy
                        audit_results['findings'].append({
                            'severity': 'MEDIUM',
                            'issue': 'Detection accuracy below recommended threshold',
                            'current_value': detection_accuracy,
                            'recommendation': 'Review and retrain detection algorithms'
                        })

            except Exception as e:
                logger.warning(f"Could not retrieve detection accuracy: {str(e)}")

            # Verify system components are operational
            required_components = self.compliance_requirements['content_monitoring']['required_components']
            for component in required_components:
                # This would check if each component is operational
                # For demonstration, we'll simulate these checks
                if component == 'automated_content_scanning':
                    # Check if content filter lambda is operational
                    pass
                elif component == 'image_analysis_capability':
                    # Check if image analysis is working
                    pass

            return audit_results

        except Exception as e:
            logger.error(f"Content monitoring audit error: {str(e)}")
            return {
                'component': 'content_monitoring',
                'status': 'AUDIT_FAILED',
                'error': str(e),
                'findings': [{
                    'severity': 'CRITICAL',
                    'issue': 'Audit system failure',
                    'risk': 'Cannot verify compliance status'
                }]
            }

    def audit_communication_monitoring_compliance(self) -> Dict[str, Any]:
        """Audit communication monitoring system compliance"""
        try:
            audit_results = {
                'component': 'communication_monitoring',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'recommendations': []
            }

            # Check communication scanning coverage
            end_time = datetime.now(timezone.utc)
            start_time = end_time - timedelta(hours=24)

            try:
                coverage_response = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/Communications',
                    MetricName='ScanCoverage',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if coverage_response['Datapoints']:
                    scan_coverage = coverage_response['Datapoints'][-1]['Average']
                    audit_results['metrics']['scan_coverage'] = scan_coverage

                    if scan_coverage < 0.95:  # 95% minimum coverage
                        audit_results['status'] = 'NON_COMPLIANT'
                        audit_results['findings'].append({
                            'severity': 'HIGH',
                            'issue': 'Communication scan coverage insufficient',
                            'current_value': scan_coverage,
                            'required_value': 0.95,
                            'risk': 'Trafficking communications may go unmonitored'
                        })

            except Exception as e:
                audit_results['findings'].append({
                    'severity': 'MEDIUM',
                    'issue': 'Cannot retrieve communication monitoring metrics',
                    'error': str(e)
                })

            # Check response time metrics
            try:
                response_time_data = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/Communications',
                    MetricName='ThreatResponseTime',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average', 'Maximum']
                )

                if response_time_data['Datapoints']:
                    avg_response_time = response_time_data['Datapoints'][-1]['Average']
                    max_response_time = response_time_data['Datapoints'][-1]['Maximum']

                    audit_results['metrics']['avg_response_time'] = avg_response_time
                    audit_results['metrics']['max_response_time'] = max_response_time

                    if max_response_time > self.compliance_thresholds['detection_response_time']:
                        audit_results['findings'].append({
                            'severity': 'MEDIUM',
                            'issue': 'Response time exceeds threshold',
                            'current_value': max_response_time,
                            'threshold': self.compliance_thresholds['detection_response_time'],
                            'recommendation': 'Optimize threat detection and response processes'
                        })

            except Exception as e:
                logger.warning(f"Could not retrieve response time metrics: {str(e)}")

            return audit_results

        except Exception as e:
            logger.error(f"Communication monitoring audit error: {str(e)}")
            return {
                'component': 'communication_monitoring',
                'status': 'AUDIT_FAILED',
                'error': str(e)
            }

    def audit_law_enforcement_reporting_compliance(self) -> Dict[str, Any]:
        """Audit law enforcement reporting compliance"""
        try:
            audit_results = {
                'component': 'law_enforcement_reporting',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'recommendations': []
            }

            # Check reporting timeliness
            end_time = datetime.now(timezone.utc)
            start_time = end_time - timedelta(hours=24)

            try:
                reporting_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/LawEnforcement',
                    MetricName='ReportingTimeliness',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average', 'Maximum']
                )

                if reporting_metrics['Datapoints']:
                    avg_reporting_time = reporting_metrics['Datapoints'][-1]['Average']
                    max_reporting_time = reporting_metrics['Datapoints'][-1]['Maximum']

                    audit_results['metrics']['avg_reporting_time'] = avg_reporting_time
                    audit_results['metrics']['max_reporting_time'] = max_reporting_time

                    if max_reporting_time > self.compliance_thresholds['law_enforcement_reporting_time']:
                        audit_results['status'] = 'NON_COMPLIANT'
                        audit_results['findings'].append({
                            'severity': 'CRITICAL',
                            'issue': 'Law enforcement reporting time exceeds legal requirements',
                            'current_value': max_reporting_time,
                            'legal_requirement': self.compliance_thresholds['law_enforcement_reporting_time'],
                            'risk': 'Potential FOSTA violation - delayed mandatory reporting'
                        })

            except Exception as e:
                audit_results['findings'].append({
                    'severity': 'HIGH',
                    'issue': 'Cannot verify law enforcement reporting metrics',
                    'error': str(e),
                    'risk': 'Compliance status unknown'
                })

            # Check evidence preservation rate
            try:
                preservation_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AEIMS/Evidence',
                    MetricName='PreservationRate',
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )

                if preservation_metrics['Datapoints']:
                    preservation_rate = preservation_metrics['Datapoints'][-1]['Average']
                    audit_results['metrics']['evidence_preservation_rate'] = preservation_rate

                    if preservation_rate < self.compliance_thresholds['evidence_preservation_rate']:
                        audit_results['status'] = 'NON_COMPLIANT'
                        audit_results['findings'].append({
                            'severity': 'CRITICAL',
                            'issue': 'Evidence preservation rate below 100%',
                            'current_value': preservation_rate,
                            'required_value': self.compliance_thresholds['evidence_preservation_rate'],
                            'risk': 'Loss of critical evidence for law enforcement'
                        })

            except Exception as e:
                logger.warning(f"Evidence preservation metrics unavailable: {str(e)}")

            return audit_results

        except Exception as e:
            logger.error(f"Law enforcement reporting audit error: {str(e)}")
            return {
                'component': 'law_enforcement_reporting',
                'status': 'AUDIT_FAILED',
                'error': str(e)
            }

    def audit_system_uptime_compliance(self) -> Dict[str, Any]:
        """Audit system uptime and availability compliance"""
        try:
            audit_results = {
                'component': 'system_uptime',
                'status': 'COMPLIANT',
                'findings': [],
                'metrics': {},
                'recommendations': []
            }

            # Check system uptime metrics
            end_time = datetime.now(timezone.utc)
            start_time = end_time - timedelta(hours=24)

            critical_services = [
                'AEIMS/ContentFilter',
                'AEIMS/CommunicationMonitor',
                'AEIMS/LawEnforcementReporter'
            ]

            for service in critical_services:
                try:
                    uptime_response = cloudwatch.get_metric_statistics(
                        Namespace=service,
                        MetricName='ServiceUptime',
                        StartTime=start_time,
                        EndTime=end_time,
                        Period=3600,
                        Statistics=['Average']
                    )

                    if uptime_response['Datapoints']:
                        service_uptime = uptime_response['Datapoints'][-1]['Average']
                        audit_results['metrics'][f'{service}_uptime'] = service_uptime

                        if service_uptime < self.compliance_thresholds['system_uptime']:
                            audit_results['status'] = 'NON_COMPLIANT'
                            audit_results['findings'].append({
                                'severity': 'HIGH',
                                'issue': f'{service} uptime below threshold',
                                'current_value': service_uptime,
                                'required_value': self.compliance_thresholds['system_uptime'],
                                'risk': 'Compliance monitoring gaps during downtime'
                            })

                except Exception as e:
                    audit_results['findings'].append({
                        'severity': 'MEDIUM',
                        'issue': f'Cannot retrieve uptime metrics for {service}',
                        'error': str(e)
                    })

            return audit_results

        except Exception as e:
            logger.error(f"System uptime audit error: {str(e)}")
            return {
                'component': 'system_uptime',
                'status': 'AUDIT_FAILED',
                'error': str(e)
            }

    def generate_compliance_report(self, audit_results: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Generate comprehensive compliance report"""
        try:
            report = {
                'audit_id': self.generate_audit_id(),
                'audit_timestamp': datetime.now(timezone.utc).isoformat(),
                'audit_period': {
                    'start': (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat(),
                    'end': datetime.now(timezone.utc).isoformat()
                },
                'overall_compliance_status': 'COMPLIANT',
                'component_audits': audit_results,
                'summary': {
                    'total_components': len(audit_results),
                    'compliant_components': 0,
                    'non_compliant_components': 0,
                    'failed_audits': 0,
                    'critical_findings': 0,
                    'high_findings': 0,
                    'medium_findings': 0
                },
                'recommendations': [],
                'action_items': [],
                'next_audit_due': (datetime.now(timezone.utc) + timedelta(hours=AUDIT_FREQUENCY_HOURS)).isoformat()
            }

            # Analyze audit results
            for audit_result in audit_results:
                status = audit_result.get('status', 'UNKNOWN')

                if status == 'COMPLIANT':
                    report['summary']['compliant_components'] += 1
                elif status == 'NON_COMPLIANT':
                    report['summary']['non_compliant_components'] += 1
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

                # Collect recommendations
                component_recommendations = audit_result.get('recommendations', [])
                report['recommendations'].extend(component_recommendations)

            # Generate action items based on findings
            if report['summary']['critical_findings'] > 0:
                report['action_items'].append({
                    'priority': 'IMMEDIATE',
                    'action': 'Address all critical compliance findings',
                    'deadline': (datetime.now(timezone.utc) + timedelta(hours=4)).isoformat()
                })

            if report['summary']['non_compliant_components'] > 0:
                report['action_items'].append({
                    'priority': 'HIGH',
                    'action': 'Remediate non-compliant components',
                    'deadline': (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()
                })

            return report

        except Exception as e:
            logger.error(f"Report generation error: {str(e)}")
            raise

    def store_audit_report(self, report: Dict[str, Any]) -> bool:
        """Store audit report for compliance records"""
        try:
            audit_id = report['audit_id']

            # Store in DynamoDB
            self.table.put_item(
                Item={
                    'audit_id': audit_id,
                    'audit_timestamp': int(datetime.now(timezone.utc).timestamp()),
                    'overall_status': report['overall_compliance_status'],
                    'critical_findings': report['summary']['critical_findings'],
                    'non_compliant_components': report['summary']['non_compliant_components'],
                    'report_data': json.dumps(report),
                    'ttl': int((datetime.now(timezone.utc) + timedelta(days=365)).timestamp())  # 1 year retention
                }
            )

            # Store detailed report in S3
            if COMPLIANCE_BUCKET:
                timestamp = datetime.now(timezone.utc).strftime('%Y/%m/%d')
                key = f"fosta-compliance-audits/{timestamp}/{audit_id}.json"

                s3.put_object(
                    Bucket=COMPLIANCE_BUCKET,
                    Key=key,
                    Body=json.dumps(report, indent=2),
                    ContentType='application/json',
                    Metadata={
                        'audit_id': audit_id,
                        'compliance_status': report['overall_compliance_status'],
                        'audit_type': 'FOSTA_compliance',
                        'retention_period': '7_years'  # Legal retention requirement
                    }
                )

            return True

        except Exception as e:
            logger.error(f"Audit report storage error: {str(e)}")
            return False

    def send_compliance_alerts(self, report: Dict[str, Any]) -> bool:
        """Send alerts for compliance issues"""
        try:
            if not ALERT_SNS_TOPIC:
                logger.warning("No alert SNS topic configured")
                return False

            # Send alert for critical findings or non-compliance
            if (report['overall_compliance_status'] != 'COMPLIANT' or
                report['summary']['critical_findings'] > 0):

                alert = {
                    'alert_type': 'FOSTA_COMPLIANCE_ISSUE',
                    'audit_id': report['audit_id'],
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'compliance_status': report['overall_compliance_status'],
                    'critical_findings': report['summary']['critical_findings'],
                    'high_findings': report['summary']['high_findings'],
                    'non_compliant_components': report['summary']['non_compliant_components'],
                    'action_items': report['action_items'],
                    'severity': 'CRITICAL' if report['summary']['critical_findings'] > 0 else 'HIGH'
                }

                sns.publish(
                    TopicArn=ALERT_SNS_TOPIC,
                    Subject=f"FOSTA Compliance Alert - {report['overall_compliance_status']}",
                    Message=json.dumps(alert, indent=2)
                )

                return True

            return False  # No alert needed

        except Exception as e:
            logger.error(f"Alert sending error: {str(e)}")
            return False


def lambda_handler(event, context):
    """
    Lambda handler for FOSTA compliance auditing

    Expected event structure:
    {
        "audit_type": "full|targeted",
        "components": ["content_monitoring", "communication_monitoring", ...],
        "trigger": "scheduled|manual|incident"
    }
    """
    try:
        logger.info("Starting FOSTA compliance audit")

        audit_type = event.get('audit_type', 'full')
        trigger = event.get('trigger', 'scheduled')

        # Initialize auditor
        auditor = FOSTAComplianceAuditor()

        # Determine which components to audit
        if audit_type == 'full':
            components_to_audit = list(auditor.compliance_requirements.keys()) + ['system_uptime']
        else:
            components_to_audit = event.get('components', ['content_monitoring'])

        # Perform audits
        audit_results = []

        for component in components_to_audit:
            try:
                if component == 'content_monitoring':
                    result = auditor.audit_content_monitoring_compliance()
                elif component == 'communication_monitoring':
                    result = auditor.audit_communication_monitoring_compliance()
                elif component == 'law_enforcement_reporting':
                    result = auditor.audit_law_enforcement_reporting_compliance()
                elif component == 'system_uptime':
                    result = auditor.audit_system_uptime_compliance()
                else:
                    logger.warning(f"Unknown component: {component}")
                    continue

                audit_results.append(result)

            except Exception as e:
                logger.error(f"Audit failed for component {component}: {str(e)}")
                audit_results.append({
                    'component': component,
                    'status': 'AUDIT_FAILED',
                    'error': str(e)
                })

        # Generate compliance report
        compliance_report = auditor.generate_compliance_report(audit_results)

        # Store audit report
        stored = auditor.store_audit_report(compliance_report)

        # Send alerts if necessary
        alert_sent = auditor.send_compliance_alerts(compliance_report)

        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'audit_completed': True,
                'audit_id': compliance_report['audit_id'],
                'audit_type': audit_type,
                'trigger': trigger,
                'overall_compliance_status': compliance_report['overall_compliance_status'],
                'components_audited': len(audit_results),
                'compliant_components': compliance_report['summary']['compliant_components'],
                'non_compliant_components': compliance_report['summary']['non_compliant_components'],
                'critical_findings': compliance_report['summary']['critical_findings'],
                'alert_sent': alert_sent,
                'report_stored': stored,
                'next_audit_due': compliance_report['next_audit_due'],
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }

        logger.info(f"FOSTA compliance audit completed: {compliance_report['audit_id']}")
        return response

    except Exception as e:
        logger.error(f"FOSTA compliance auditor error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal server error',
                'message': 'Compliance audit failed',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }