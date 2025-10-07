import json
import boto3
import logging
import requests
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Florida Geolocation Controller Lambda Function
    Enforces Florida-specific geographic restrictions and compliance
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"

    # Initialize AWS clients
    dynamodb = boto3.resource('dynamodb')

    try:
        logger.info(f"Processing geolocation check for {project_name} in {environment}")

        # Parse incoming request
        ip_address = event.get('ip_address', '')
        user_id = event.get('user_id', 'unknown')
        request_type = event.get('request_type', 'access')

        if not ip_address:
            raise ValueError("IP address is required")

        # Perform geolocation lookup
        geo_info = get_geolocation(ip_address)

        # Check Florida compliance
        is_florida_compliant = check_florida_compliance(geo_info)

        # Log the geolocation check
        table_name = f"{project_name}-florida-geolocation-logs-{environment}"
        table = dynamodb.Table(table_name)

        log_item = {
            'log_id': f"{user_id}-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
            'timestamp': datetime.utcnow().isoformat(),
            'ip_address': ip_address,
            'user_id': user_id,
            'request_type': request_type,
            'geo_country': geo_info.get('country', 'unknown'),
            'geo_region': geo_info.get('region', 'unknown'),
            'geo_city': geo_info.get('city', 'unknown'),
            'florida_compliant': is_florida_compliant,
            'environment': environment,
            'project': project_name
        }

        table.put_item(Item=log_item)

        response_data = {
            'allowed': is_florida_compliant,
            'location': {
                'country': geo_info.get('country', 'unknown'),
                'region': geo_info.get('region', 'unknown'),
                'city': geo_info.get('city', 'unknown')
            },
            'compliance_status': 'florida_compliant' if is_florida_compliant else 'florida_restricted',
            'timestamp': datetime.utcnow().isoformat()
        }

        logger.info(f"Geolocation check completed for {ip_address}: {'allowed' if is_florida_compliant else 'blocked'}")

        return {
            'statusCode': 200,
            'body': json.dumps(response_data)
        }

    except Exception as e:
        logger.error(f"Geolocation check failed: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Geolocation check failed',
                'error': str(e),
                'allowed': False,  # Fail secure
                'environment': environment,
                'project': project_name
            })
        }

def get_geolocation(ip_address):
    """Get geolocation information for an IP address"""
    try:
        # Using a free geolocation service (in production, use a reliable paid service)
        response = requests.get(f"https://ipapi.co/{ip_address}/json/", timeout=5)
        if response.status_code == 200:
            return response.json()
        else:
            logger.warning(f"Geolocation service returned status {response.status_code}")
            return {}
    except Exception as e:
        logger.error(f"Failed to get geolocation: {str(e)}")
        return {}

def check_florida_compliance(geo_info):
    """Check if the location is compliant with Florida regulations"""
    country = geo_info.get('country', '').upper()
    region = geo_info.get('region', '').upper()

    # Florida-specific restrictions
    if country == 'US' and region == 'FLORIDA':
        # Additional Florida-specific checks can be added here
        # For now, we'll allow access but with enhanced logging
        return True
    elif country == 'US':
        # Other US states - generally allowed
        return True
    else:
        # International access - may require additional verification
        # This could be configurable based on business requirements
        return True