"""
TID (Trafficking in Persons) Compliance Auditor Lambda function
Audits platform compliance with anti-trafficking regulations
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class TIDComplianceAuditor:
    def __init__(self):
        """Initialize TID compliance auditor"""
        self.compliance_categories = [
            'content_moderation',
            'age_verification',
            'reporting_mechanisms',
            'law_enforcement_cooperation',
            'user_safety_features',
            'prevention_measures'
        ]

        self.severity_levels = {
            'CRITICAL': 10,
            'HIGH': 7,
            'MEDIUM': 4,
            'LOW': 1
        }

    def audit_content_moderation(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit content moderation practices"""
        violations = []
        score = 100

        moderation_data = platform_data.get('content_moderation', {})

        # Check automated scanning
        if not moderation_data.get('automated_scanning_enabled', False):
            violations.append({
                'type': 'missing_automated_scanning',
                'severity': 'HIGH',
                'description': 'No automated content scanning for trafficking indicators'
            })
            score -= self.severity_levels['HIGH']

        # Check human review process
        if not moderation_data.get('human_review_process', False):
            violations.append({
                'type': 'missing_human_review',
                'severity': 'MEDIUM',
                'description': 'No human review process for flagged content'
            })
            score -= self.severity_levels['MEDIUM']

        # Check response time
        response_time_hours = moderation_data.get('average_response_time_hours', 72)
        if response_time_hours > 24:
            violations.append({
                'type': 'slow_response_time',
                'severity': 'MEDIUM',
                'description': f'Response time ({response_time_hours}h) exceeds recommended 24h'
            })
            score -= self.severity_levels['MEDIUM']

        # Check training requirements
        if not moderation_data.get('staff_training_completed', False):
            violations.append({
                'type': 'insufficient_training',
                'severity': 'HIGH',
                'description': 'Moderation staff lack trafficking identification training'
            })
            score -= self.severity_levels['HIGH']

        return {
            'category': 'content_moderation',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_age_verification(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit age verification systems"""
        violations = []
        score = 100

        age_verification = platform_data.get('age_verification', {})

        # Check verification method
        verification_method = age_verification.get('method', 'none')
        if verification_method == 'none':
            violations.append({
                'type': 'no_age_verification',
                'severity': 'CRITICAL',
                'description': 'No age verification system in place'
            })
            score -= self.severity_levels['CRITICAL']
        elif verification_method == 'self_reported':
            violations.append({
                'type': 'weak_age_verification',
                'severity': 'HIGH',
                'description': 'Relies only on self-reported age'
            })
            score -= self.severity_levels['HIGH']

        # Check document verification
        if not age_verification.get('document_verification', False):
            violations.append({
                'type': 'missing_document_verification',
                'severity': 'MEDIUM',
                'description': 'No document-based age verification for high-risk content'
            })
            score -= self.severity_levels['MEDIUM']

        # Check re-verification requirements
        if not age_verification.get('periodic_reverification', False):
            violations.append({
                'type': 'no_reverification',
                'severity': 'LOW',
                'description': 'No periodic re-verification requirements'
            })
            score -= self.severity_levels['LOW']

        return {
            'category': 'age_verification',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_reporting_mechanisms(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit reporting and flagging systems"""
        violations = []
        score = 100

        reporting_data = platform_data.get('reporting_mechanisms', {})

        # Check reporting accessibility
        if not reporting_data.get('easy_reporting_access', False):
            violations.append({
                'type': 'difficult_reporting',
                'severity': 'MEDIUM',
                'description': 'Reporting mechanism not easily accessible'
            })
            score -= self.severity_levels['MEDIUM']

        # Check anonymous reporting
        if not reporting_data.get('anonymous_reporting_enabled', False):
            violations.append({
                'type': 'no_anonymous_reporting',
                'severity': 'MEDIUM',
                'description': 'No anonymous reporting option available'
            })
            score -= self.severity_levels['MEDIUM']

        # Check law enforcement hotline
        if not reporting_data.get('law_enforcement_hotline', False):
            violations.append({
                'type': 'missing_le_hotline',
                'severity': 'HIGH',
                'description': 'No direct law enforcement reporting channel'
            })
            score -= self.severity_levels['HIGH']

        # Check NCMEC reporting (for US platforms)
        jurisdiction = platform_data.get('jurisdiction', '')
        if 'US' in jurisdiction and not reporting_data.get('ncmec_reporting', False):
            violations.append({
                'type': 'missing_ncmec_reporting',
                'severity': 'CRITICAL',
                'description': 'No NCMEC reporting for US-based platform'
            })
            score -= self.severity_levels['CRITICAL']

        return {
            'category': 'reporting_mechanisms',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def audit_law_enforcement_cooperation(self, platform_data: Dict) -> Dict[str, Any]:
        """Audit law enforcement cooperation policies"""
        violations = []
        score = 100

        le_cooperation = platform_data.get('law_enforcement_cooperation', {})

        # Check response to legal requests
        if not le_cooperation.get('legal_request_compliance', False):
            violations.append({
                'type': 'poor_legal_compliance',
                'severity': 'CRITICAL',
                'description': 'Inadequate response to law enforcement requests'
            })
            score -= self.severity_levels['CRITICAL']

        # Check data preservation
        if not le_cooperation.get('data_preservation_capability', False):
            violations.append({
                'type': 'no_data_preservation',
                'severity': 'HIGH',
                'description': 'No capability to preserve evidence for investigations'
            })
            score -= self.severity_levels['HIGH']

        # Check emergency response
        emergency_response_time = le_cooperation.get('emergency_response_hours', 72)
        if emergency_response_time > 24:
            violations.append({
                'type': 'slow_emergency_response',
                'severity': 'HIGH',
                'description': f'Emergency response time ({emergency_response_time}h) too slow'
            })
            score -= self.severity_levels['HIGH']

        return {
            'category': 'law_enforcement_cooperation',
            'score': max(0, score),
            'violations': violations,
            'compliant': len(violations) == 0
        }

    def generate_compliance_report(self, platform_data: Dict) -> Dict[str, Any]:
        """Generate comprehensive compliance audit report"""
        audit_results = []

        # Perform all audits
        audit_results.append(self.audit_content_moderation(platform_data))
        audit_results.append(self.audit_age_verification(platform_data))
        audit_results.append(self.audit_reporting_mechanisms(platform_data))
        audit_results.append(self.audit_law_enforcement_cooperation(platform_data))

        # Calculate overall compliance
        total_score = sum(result['score'] for result in audit_results)
        max_possible_score = len(audit_results) * 100
        overall_compliance_percentage = (total_score / max_possible_score) * 100

        # Count violations by severity
        violation_counts = {'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0}
        all_violations = []

        for result in audit_results:
            for violation in result['violations']:
                severity = violation['severity']
                violation_counts[severity] += 1
                all_violations.append(violation)

        # Determine overall compliance status
        if overall_compliance_percentage >= 90:
            compliance_status = 'FULLY_COMPLIANT'
        elif overall_compliance_percentage >= 70:
            compliance_status = 'MOSTLY_COMPLIANT'
        elif overall_compliance_percentage >= 50:
            compliance_status = 'PARTIALLY_COMPLIANT'
        else:
            compliance_status = 'NON_COMPLIANT'

        return {
            'platform_id': platform_data.get('platform_id', 'unknown'),
            'audit_timestamp': datetime.utcnow().isoformat(),
            'overall_compliance_percentage': round(overall_compliance_percentage, 2),
            'compliance_status': compliance_status,
            'category_results': audit_results,
            'violation_summary': violation_counts,
            'total_violations': len(all_violations),
            'critical_issues': violation_counts['CRITICAL'],
            'recommendations': self.generate_recommendations(all_violations),
            'next_audit_date': (datetime.utcnow() + timedelta(days=90)).isoformat()
        }

    def generate_recommendations(self, violations: List[Dict]) -> List[str]:
        """Generate recommendations based on violations"""
        recommendations = []

        critical_violations = [v for v in violations if v['severity'] == 'CRITICAL']
        if critical_violations:
            recommendations.append("Immediately address all critical compliance issues")

        high_violations = [v for v in violations if v['severity'] == 'HIGH']
        if high_violations:
            recommendations.append("Develop action plan for high-priority violations within 30 days")

        violation_types = set(v['type'] for v in violations)

        if 'no_age_verification' in violation_types or 'weak_age_verification' in violation_types:
            recommendations.append("Implement robust age verification system with document validation")

        if 'missing_automated_scanning' in violation_types:
            recommendations.append("Deploy AI-powered content scanning for trafficking indicators")

        if 'missing_le_hotline' in violation_types:
            recommendations.append("Establish direct law enforcement reporting channel")

        return recommendations

def lambda_handler(event, context):
    """Main Lambda handler for TID compliance auditing"""
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

        auditor = TIDComplianceAuditor()

        if audit_type == 'full':
            # Generate complete compliance report
            compliance_report = auditor.generate_compliance_report(platform_data)

            # Log compliance status
            platform_id = platform_data.get('platform_id', 'unknown')
            compliance_status = compliance_report['compliance_status']
            critical_issues = compliance_report['critical_issues']

            logger.info(f"TID compliance audit completed: "
                       f"Platform={platform_id}, "
                       f"Status={compliance_status}, "
                       f"Critical Issues={critical_issues}")

            if compliance_status == 'NON_COMPLIANT':
                logger.warning(f"Platform {platform_id} is non-compliant with TID regulations")

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
        logger.error(f"Error in TID compliance auditor: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }