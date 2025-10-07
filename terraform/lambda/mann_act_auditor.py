"""
Mann Act Auditor Lambda function
Audits platform compliance with the Mann Act (White-Slave Traffic Act)
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class MannActAuditor:
    def __init__(self):
        """Initialize Mann Act compliance auditor"""
        self.cloudwatch = boto3.client('cloudwatch')
        self.dynamodb = boto3.resource('dynamodb')

        # Mann Act compliance requirements
        self.compliance_categories = {
            'interstate_monitoring': {
                'description': 'Monitoring of interstate transportation of individuals',
                'weight': 25,
                'requirements': [
                    'location_tracking',
                    'cross_state_detection',
                    'travel_pattern_analysis'
                ]
            },
            'content_filtering': {
                'description': 'Detection of content promoting illegal transportation',
                'weight': 30,
                'requirements': [
                    'automated_content_scanning',
                    'human_review_process',
                    'keyword_detection'
                ]
            },
            'reporting_mechanisms': {
                'description': 'Mandatory reporting of suspected violations',
                'weight': 25,
                'requirements': [
                    'law_enforcement_reporting',
                    'evidence_preservation',
                    'investigation_cooperation'
                ]
            },
            'prevention_measures': {
                'description': 'Proactive measures to prevent violations',
                'weight': 20,
                'requirements': [
                    'user_education',
                    'platform_controls',
                    'suspicious_activity_detection'
                ]
            }
        }

    def audit_interstate_monitoring(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit interstate monitoring capabilities"""
        monitoring_data = platform_data.get('interstate_monitoring', {})
        violations = []
        score = 100

        # Check location tracking
        if not monitoring_data.get('location_tracking_enabled', False):
            violations.append({
                'type': 'missing_location_tracking',
                'severity': 'HIGH',
                'description': 'No location tracking for interstate activity'
            })
            score -= 30

        # Check cross-state detection
        if not monitoring_data.get('cross_state_detection', False):
            violations.append({
                'type': 'missing_cross_state_detection',
                'severity': 'HIGH',
                'description': 'No automated cross-state activity detection'
            })
            score -= 25

        # Check travel pattern analysis
        if not monitoring_data.get('travel_pattern_analysis', False):
            violations.append({
                'type': 'missing_travel_analysis',
                'severity': 'MEDIUM',
                'description': 'No travel pattern analysis capabilities'
            })
            score -= 15

        # Check reporting frequency
        reporting_frequency = monitoring_data.get('reporting_frequency_hours', 72)
        if reporting_frequency > 24:
            violations.append({
                'type': 'slow_reporting',
                'severity': 'MEDIUM',
                'description': f'Reporting frequency ({reporting_frequency}h) exceeds 24h requirement'
            })
            score -= 10

        return {
            'category': 'interstate_monitoring',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_content_filtering(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit content filtering for Mann Act violations"""
        filtering_data = platform_data.get('content_filtering', {})
        violations = []
        score = 100

        # Check automated scanning
        if not filtering_data.get('automated_scanning', False):
            violations.append({
                'type': 'missing_automated_scanning',
                'severity': 'CRITICAL',
                'description': 'No automated content scanning for Mann Act violations'
            })
            score -= 40

        # Check human review
        if not filtering_data.get('human_review_process', False):
            violations.append({
                'type': 'missing_human_review',
                'severity': 'HIGH',
                'description': 'No human review process for flagged content'
            })
            score -= 25

        # Check keyword detection
        mann_act_keywords = filtering_data.get('mann_act_keywords', [])
        if len(mann_act_keywords) < 10:
            violations.append({
                'type': 'insufficient_keywords',
                'severity': 'MEDIUM',
                'description': f'Only {len(mann_act_keywords)} Mann Act keywords configured (minimum 10)'
            })
            score -= 15

        # Check response time
        response_time = filtering_data.get('average_response_time_minutes', 120)
        if response_time > 30:
            violations.append({
                'type': 'slow_response_time',
                'severity': 'MEDIUM',
                'description': f'Response time ({response_time}min) exceeds 30min requirement'
            })
            score -= 10

        return {
            'category': 'content_filtering',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_reporting_mechanisms(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit mandatory reporting mechanisms"""
        reporting_data = platform_data.get('reporting_mechanisms', {})
        violations = []
        score = 100

        # Check law enforcement reporting
        if not reporting_data.get('law_enforcement_reporting', False):
            violations.append({
                'type': 'missing_le_reporting',
                'severity': 'CRITICAL',
                'description': 'No law enforcement reporting mechanism'
            })
            score -= 40

        # Check evidence preservation
        if not reporting_data.get('evidence_preservation', False):
            violations.append({
                'type': 'missing_evidence_preservation',
                'severity': 'HIGH',
                'description': 'No evidence preservation capabilities'
            })
            score -= 25

        # Check investigation cooperation
        if not reporting_data.get('investigation_cooperation', False):
            violations.append({
                'type': 'poor_investigation_cooperation',
                'severity': 'HIGH',
                'description': 'No formal investigation cooperation process'
            })
            score -= 20

        # Check NCMEC reporting (if applicable)
        jurisdiction = platform_data.get('jurisdiction', '')
        if 'US' in jurisdiction and not reporting_data.get('ncmec_reporting', False):
            violations.append({
                'type': 'missing_ncmec_reporting',
                'severity': 'CRITICAL',
                'description': 'No NCMEC reporting for US-based platform'
            })
            score -= 35

        return {
            'category': 'reporting_mechanisms',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_prevention_measures(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit prevention measures"""
        prevention_data = platform_data.get('prevention_measures', {})
        violations = []
        score = 100

        # Check user education
        if not prevention_data.get('user_education_program', False):
            violations.append({
                'type': 'missing_user_education',
                'severity': 'MEDIUM',
                'description': 'No user education program for Mann Act compliance'
            })
            score -= 20

        # Check platform controls
        if not prevention_data.get('platform_controls', False):
            violations.append({
                'type': 'insufficient_platform_controls',
                'severity': 'HIGH',
                'description': 'Insufficient platform controls to prevent violations'
            })
            score -= 25

        # Check suspicious activity detection
        if not prevention_data.get('suspicious_activity_detection', False):
            violations.append({
                'type': 'missing_suspicious_detection',
                'severity': 'HIGH',
                'description': 'No suspicious activity detection system'
            })
            score -= 30

        # Check staff training
        if not prevention_data.get('staff_training_completed', False):
            violations.append({
                'type': 'insufficient_staff_training',
                'severity': 'MEDIUM',
                'description': 'Staff not trained on Mann Act compliance'
            })
            score -= 15

        return {
            'category': 'prevention_measures',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def generate_compliance_report(self, platform_data: Dict) -> Dict[str, Any]:
        """Generate comprehensive Mann Act compliance report"""
        audit_results = []

        # Perform all category audits
        audit_results.append(self.audit_interstate_monitoring(platform_data))
        audit_results.append(self.audit_content_filtering(platform_data))
        audit_results.append(self.audit_reporting_mechanisms(platform_data))
        audit_results.append(self.audit_prevention_measures(platform_data))

        # Calculate weighted compliance score
        total_weighted_score = 0
        total_weight = 0

        for result in audit_results:
            category = result['category']
            weight = self.compliance_categories[category]['weight']
            score = result['score']

            total_weighted_score += (score * weight)
            total_weight += weight

        overall_compliance_percentage = (total_weighted_score / (total_weight * 100)) * 100

        # Count violations by severity
        violation_counts = {'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0}
        all_violations = []

        for result in audit_results:
            for violation in result['violations']:
                severity = violation['severity']
                violation_counts[severity] += 1
                all_violations.append(violation)

        # Determine compliance status
        if violation_counts['CRITICAL'] > 0:
            compliance_status = 'NON_COMPLIANT'
        elif overall_compliance_percentage >= 85:
            compliance_status = 'FULLY_COMPLIANT'
        elif overall_compliance_percentage >= 70:
            compliance_status = 'MOSTLY_COMPLIANT'
        else:
            compliance_status = 'PARTIALLY_COMPLIANT'

        return {
            'platform_id': platform_data.get('platform_id', 'unknown'),
            'audit_timestamp': datetime.utcnow().isoformat(),
            'compliance_framework': 'Mann Act (18 USC 2421-2424)',
            'overall_compliance_percentage': round(overall_compliance_percentage, 2),
            'compliance_status': compliance_status,
            'category_results': audit_results,
            'violation_summary': violation_counts,
            'total_violations': len(all_violations),
            'critical_issues': violation_counts['CRITICAL'],
            'recommendations': self.generate_recommendations(all_violations),
            'next_audit_date': (datetime.utcnow() + timedelta(days=30)).isoformat(),
            'legal_requirements': {
                'interstate_monitoring_required': True,
                'mandatory_reporting': True,
                'evidence_preservation_required': True,
                'cooperation_with_law_enforcement': True
            }
        }

    def generate_recommendations(self, violations: List[Dict]) -> List[str]:
        """Generate specific recommendations based on violations"""
        recommendations = []

        critical_violations = [v for v in violations if v['severity'] == 'CRITICAL']
        if critical_violations:
            recommendations.append("URGENT: Address all critical compliance issues within 24 hours")

        violation_types = set(v['type'] for v in violations)

        if 'missing_automated_scanning' in violation_types:
            recommendations.append("Implement automated content scanning for Mann Act violations")

        if 'missing_le_reporting' in violation_types:
            recommendations.append("Establish direct law enforcement reporting channel immediately")

        if 'missing_location_tracking' in violation_types:
            recommendations.append("Deploy location tracking for interstate activity monitoring")

        if 'missing_evidence_preservation' in violation_types:
            recommendations.append("Implement secure evidence preservation system")

        if 'missing_ncmec_reporting' in violation_types:
            recommendations.append("Establish NCMEC reporting integration for US operations")

        return recommendations

def lambda_handler(event, context):
    """Main Lambda handler for Mann Act compliance auditing"""
    try:
        platform_data = event.get('platform_data', {})
        audit_type = event.get('audit_type', 'full')

        if not platform_data:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No platform data provided for audit'
                })
            }

        auditor = MannActAuditor()

        if audit_type == 'full':
            # Generate complete compliance report
            compliance_report = auditor.generate_compliance_report(platform_data)

            # Log compliance status
            platform_id = platform_data.get('platform_id', 'unknown')
            compliance_status = compliance_report['compliance_status']
            critical_issues = compliance_report['critical_issues']

            logger.info(f"Mann Act compliance audit completed: "
                       f"Platform={platform_id}, "
                       f"Status={compliance_status}, "
                       f"Critical Issues={critical_issues}")

            if compliance_status == 'NON_COMPLIANT':
                logger.critical(f"Platform {platform_id} is non-compliant with Mann Act regulations")

            return {
                'statusCode': 200,
                'body': json.dumps(compliance_report, default=str)
            }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown audit type: {audit_type}',
                    'supported_types': ['full']
                })
            }

    except Exception as e:
        logger.error(f"Error in Mann Act compliance auditor: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }