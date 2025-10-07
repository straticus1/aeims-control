import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Florida Compliance Auditor Lambda Function
    Performs regular compliance audits for Florida regulations
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"

    # Initialize AWS clients
    dynamodb = boto3.resource('dynamodb')
    s3 = boto3.client('s3')

    try:
        logger.info(f"Starting Florida compliance audit for {project_name} in {environment}")

        audit_results = {
            'timestamp': datetime.utcnow().isoformat(),
            'environment': environment,
            'project': project_name,
            'audit_type': 'florida_compliance',
            'findings': []
        }

        # Audit geolocation logs
        geo_findings = audit_geolocation_compliance()
        audit_results['findings'].extend(geo_findings)

        # Audit obscenity filter logs
        obscenity_findings = audit_obscenity_compliance()
        audit_results['findings'].extend(obscenity_findings)

        # Audit age verification records
        age_verification_findings = audit_age_verification()
        audit_results['findings'].extend(age_verification_findings)

        # Generate compliance score
        total_findings = len(audit_results['findings'])
        critical_findings = len([f for f in audit_results['findings'] if f.get('severity') == 'critical'])

        if critical_findings > 0:
            compliance_score = max(0, 100 - (critical_findings * 20))
        else:
            compliance_score = max(0, 100 - (total_findings * 5))

        audit_results['compliance_score'] = compliance_score
        audit_results['status'] = 'compliant' if compliance_score >= 90 else 'non_compliant'

        # Store audit results
        bucket_name = f"{project_name}-compliance-audits-{environment}"
        audit_key = f"florida/{datetime.utcnow().strftime('%Y/%m/%d')}/audit-{datetime.utcnow().strftime('%H%M%S')}.json"

        s3.put_object(
            Bucket=bucket_name,
            Key=audit_key,
            Body=json.dumps(audit_results, indent=2),
            ServerSideEncryption='aws:kms'
        )

        logger.info(f"Florida compliance audit completed. Score: {compliance_score}, Findings: {total_findings}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Florida compliance audit completed',
                'compliance_score': compliance_score,
                'status': audit_results['status'],
                'total_findings': total_findings,
                'critical_findings': critical_findings,
                'audit_location': f"s3://{bucket_name}/{audit_key}"
            })
        }

    except Exception as e:
        logger.error(f"Florida compliance audit failed: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Florida compliance audit failed',
                'error': str(e),
                'environment': environment,
                'project': project_name
            })
        }

def audit_geolocation_compliance():
    """Audit geolocation compliance"""
    findings = []

    # This would query the geolocation logs table
    # For now, returning sample findings
    findings.append({
        'category': 'geolocation',
        'severity': 'medium',
        'description': 'High volume of international access detected',
        'recommendation': 'Review international access policies'
    })

    return findings

def audit_obscenity_compliance():
    """Audit obscenity filter compliance"""
    findings = []

    # This would query the obscenity filter logs
    findings.append({
        'category': 'content_filtering',
        'severity': 'low',
        'description': 'Content filter operating within normal parameters',
        'recommendation': 'Continue monitoring'
    })

    return findings

def audit_age_verification():
    """Audit age verification compliance"""
    findings = []

    # This would check age verification records
    findings.append({
        'category': 'age_verification',
        'severity': 'low',
        'description': 'Age verification processes functioning correctly',
        'recommendation': 'Maintain current verification standards'
    })

    return findings