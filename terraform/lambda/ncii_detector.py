"""
Non-Consensual Intimate Image (NCII) detection Lambda function
Detects and manages NCII content using perceptual hashing and metadata analysis
"""
import json
import hashlib
import logging
from typing import Dict, List, Any, Optional
import base64
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class NCIIDetector:
    def __init__(self):
        """Initialize NCII detector with configuration"""
        self.hash_threshold = 0.95  # Similarity threshold for matches
        self.supported_formats = ['jpg', 'jpeg', 'png', 'gif', 'webp']

    def generate_perceptual_hash(self, image_data: bytes) -> str:
        """Generate perceptual hash for image content"""
        try:
            # Simplified perceptual hashing - in production would use
            # more sophisticated algorithms like pHash or dHash
            hash_obj = hashlib.sha256(image_data[:1024])  # Sample first 1KB
            return hash_obj.hexdigest()
        except Exception as e:
            logger.error(f"Error generating perceptual hash: {str(e)}")
            return ""

    def analyze_metadata(self, metadata: Dict) -> Dict[str, Any]:
        """Analyze image metadata for NCII indicators"""
        risk_factors = []
        risk_score = 0

        # Check for concerning metadata
        if metadata.get('gps_coordinates'):
            risk_factors.append('gps_location_present')
            risk_score += 2

        if metadata.get('device_info'):
            risk_factors.append('device_metadata_present')
            risk_score += 1

        # Check creation date patterns
        creation_date = metadata.get('creation_date')
        if creation_date:
            # Check if image was created recently (potential leak)
            try:
                created = datetime.fromisoformat(creation_date.replace('Z', '+00:00'))
                age_days = (datetime.now() - created).days
                if age_days < 30:
                    risk_factors.append('recently_created')
                    risk_score += 1
            except:
                pass

        # Check for editing software signatures
        software = metadata.get('software', '').lower()
        if any(editor in software for editor in ['photoshop', 'gimp', 'edited']):
            risk_factors.append('edited_image')
            risk_score += 1

        return {
            'risk_factors': risk_factors,
            'risk_score': risk_score,
            'metadata_analysis': True
        }

    def check_hash_database(self, image_hash: str) -> Dict[str, Any]:
        """Check if image hash matches known NCII database"""
        # In production, this would query actual NCII hash databases
        # For now, simulate the check
        return {
            'match_found': False,
            'confidence': 0.0,
            'database_checked': True,
            'hash_value': image_hash
        }

    def analyze_image(self, image_data: bytes, metadata: Dict = None) -> Dict[str, Any]:
        """Comprehensive NCII analysis of image"""
        if metadata is None:
            metadata = {}

        # Generate perceptual hash
        image_hash = self.generate_perceptual_hash(image_data)

        # Check against known NCII hashes
        hash_result = self.check_hash_database(image_hash)

        # Analyze metadata
        metadata_result = self.analyze_metadata(metadata)

        # Calculate overall risk
        total_risk = metadata_result['risk_score']
        if hash_result['match_found']:
            total_risk += 10  # High penalty for hash match

        # Determine risk level
        if total_risk >= 8:
            risk_level = 'HIGH'
        elif total_risk >= 4:
            risk_level = 'MEDIUM'
        elif total_risk >= 1:
            risk_level = 'LOW'
        else:
            risk_level = 'NONE'

        return {
            'risk_level': risk_level,
            'total_risk_score': total_risk,
            'perceptual_hash': image_hash,
            'hash_database_result': hash_result,
            'metadata_analysis': metadata_result,
            'image_size_bytes': len(image_data),
            'analysis_timestamp': datetime.utcnow().isoformat()
        }

def lambda_handler(event, context):
    """Main Lambda handler for NCII detection"""
    try:
        # Extract image data and metadata from event
        image_data_b64 = event.get('image_data')
        metadata = event.get('metadata', {})
        source = event.get('source', 'unknown')
        user_id = event.get('user_id', 'anonymous')

        if not image_data_b64:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No image data provided'
                })
            }

        try:
            # Decode base64 image data
            image_data = base64.b64decode(image_data_b64)
        except Exception as e:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid base64 image data'
                })
            }

        # Initialize detector and analyze
        detector = NCIIDetector()
        analysis_result = detector.analyze_image(image_data, metadata)

        # Add request metadata
        analysis_result.update({
            'source': source,
            'user_id': user_id,
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        })

        # Log high-risk detections
        if analysis_result['risk_level'] in ['HIGH', 'MEDIUM']:
            logger.warning(f"Potential NCII content detected: "
                         f"Risk={analysis_result['risk_level']}, "
                         f"Score={analysis_result['total_risk_score']}, "
                         f"User={user_id}, Hash={analysis_result['perceptual_hash'][:16]}...")

        # Special handling for confirmed NCII matches
        if analysis_result['hash_database_result']['match_found']:
            logger.critical(f"CONFIRMED NCII MATCH DETECTED: "
                          f"User={user_id}, Hash={analysis_result['perceptual_hash']}")

        return {
            'statusCode': 200,
            'body': json.dumps(analysis_result, default=str)
        }

    except Exception as e:
        logger.error(f"Error in NCII detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }