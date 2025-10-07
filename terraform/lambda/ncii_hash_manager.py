"""
NCII Hash Database Manager Lambda function
Manages perceptual hashes for non-consensual intimate images
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import hashlib
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class NCIIHashManager:
    def __init__(self):
        """Initialize NCII hash manager"""
        self.similarity_threshold = 0.95
        self.hash_types = ['phash', 'dhash', 'ahash', 'whash']

    def calculate_perceptual_hashes(self, image_data: bytes) -> Dict[str, str]:
        """Calculate multiple types of perceptual hashes for an image"""
        hashes = {}

        try:
            # Simplified hash calculation - in production would use
            # proper perceptual hashing libraries like imagehash

            # Basic content hash (phash simulation)
            phash = hashlib.sha256(image_data[:2048]).hexdigest()[:16]
            hashes['phash'] = phash

            # Difference hash simulation (dhash)
            dhash = hashlib.md5(image_data[::2]).hexdigest()[:16]
            hashes['dhash'] = dhash

            # Average hash simulation (ahash)
            ahash = hashlib.sha1(image_data[::4]).hexdigest()[:16]
            hashes['ahash'] = ahash

            # Wavelet hash simulation (whash)
            whash = hashlib.blake2b(image_data[::8], digest_size=8).hexdigest()
            hashes['whash'] = whash

        except Exception as e:
            logger.error(f"Error calculating perceptual hashes: {str(e)}")

        return hashes

    def add_hash_to_database(self, hashes: Dict[str, str], metadata: Dict) -> Dict[str, Any]:
        """Add hash set to NCII database"""
        try:
            # Generate unique record ID
            record_id = hashlib.sha256(
                f"{hashes.get('phash', '')}{datetime.utcnow().isoformat()}".encode()
            ).hexdigest()[:16]

            # Create database record
            hash_record = {
                'record_id': record_id,
                'hashes': hashes,
                'metadata': {
                    'source': metadata.get('source', 'unknown'),
                    'reporter': metadata.get('reporter', 'anonymous'),
                    'case_number': metadata.get('case_number', ''),
                    'jurisdiction': metadata.get('jurisdiction', ''),
                    'victim_consent': metadata.get('victim_consent', False),
                    'law_enforcement_verified': metadata.get('law_enforcement_verified', False)
                },
                'created_timestamp': datetime.utcnow().isoformat(),
                'status': 'ACTIVE',
                'match_count': 0,
                'last_matched': None
            }

            # In production, would store in actual database
            logger.info(f"Hash record created: {record_id}")

            return {
                'success': True,
                'record_id': record_id,
                'hash_count': len(hashes)
            }

        except Exception as e:
            logger.error(f"Error adding hash to database: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }

    def search_hash_database(self, query_hashes: Dict[str, str]) -> Dict[str, Any]:
        """Search for matching hashes in NCII database"""
        try:
            # In production, would query actual database with similarity matching
            # For now, simulate the search

            matches = []
            total_searched = 1000  # Simulated database size

            # Simulate finding matches based on hash similarity
            for hash_type, hash_value in query_hashes.items():
                # Simulate hash comparison logic
                if self._simulate_hash_match(hash_value):
                    match_record = {
                        'record_id': f"match_{hash_type}_{hash_value[:8]}",
                        'hash_type': hash_type,
                        'similarity': 0.98,  # Simulated similarity score
                        'matched_hash': hash_value,
                        'case_info': {
                            'case_number': 'NCII-2024-001',
                            'jurisdiction': 'Federal',
                            'status': 'VERIFIED'
                        }
                    }
                    matches.append(match_record)

            highest_similarity = max([m['similarity'] for m in matches]) if matches else 0.0

            return {
                'matches_found': len(matches) > 0,
                'match_count': len(matches),
                'highest_similarity': highest_similarity,
                'matches': matches,
                'database_size': total_searched,
                'search_timestamp': datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Error searching hash database: {str(e)}")
            return {
                'matches_found': False,
                'error': str(e)
            }

    def _simulate_hash_match(self, hash_value: str) -> bool:
        """Simulate hash matching logic"""
        # Simple simulation - in production would use proper similarity algorithms
        return hash_value.startswith(('a', 'b', 'c'))  # Simulate 30% match rate

    def remove_hash_from_database(self, record_id: str, reason: str) -> Dict[str, Any]:
        """Remove hash record from database"""
        try:
            # In production, would mark record as inactive or delete
            logger.info(f"Hash record removed: {record_id}, Reason: {reason}")

            return {
                'success': True,
                'record_id': record_id,
                'action': 'removed',
                'reason': reason,
                'timestamp': datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Error removing hash from database: {str(e)}")
            return {
                'success': False,
                'error': str(e)
            }

def lambda_handler(event, context):
    """Main Lambda handler for NCII hash management"""
    try:
        action = event.get('action', 'search')
        manager = NCIIHashManager()

        if action == 'add':
            # Add new hash to database
            image_data_b64 = event.get('image_data')
            metadata = event.get('metadata', {})

            if not image_data_b64:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'No image data provided'
                    })
                }

            try:
                image_data = base64.b64decode(image_data_b64)
            except Exception:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'Invalid base64 image data'
                    })
                }

            # Calculate hashes and add to database
            hashes = manager.calculate_perceptual_hashes(image_data)
            result = manager.add_hash_to_database(hashes, metadata)

            if result['success']:
                logger.info(f"NCII hash added to database: {result['record_id']}")
                return {
                    'statusCode': 201,
                    'body': json.dumps({
                        'message': 'Hash added to NCII database',
                        'record_id': result['record_id'],
                        'hash_count': result['hash_count']
                    })
                }
            else:
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'error': 'Failed to add hash to database',
                        'details': result.get('error', 'Unknown error')
                    })
                }

        elif action == 'search':
            # Search for matching hashes
            query_hashes = event.get('hashes', {})

            if not query_hashes:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'No hashes provided for search'
                    })
                }

            # Search database
            search_result = manager.search_hash_database(query_hashes)

            if search_result.get('matches_found'):
                logger.warning(f"NCII hash match found: "
                             f"Matches={search_result['match_count']}, "
                             f"Similarity={search_result['highest_similarity']}")

            return {
                'statusCode': 200,
                'body': json.dumps(search_result, default=str)
            }

        elif action == 'remove':
            # Remove hash from database
            record_id = event.get('record_id')
            reason = event.get('reason', 'No reason provided')

            if not record_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'Record ID required for removal'
                    })
                }

            result = manager.remove_hash_from_database(record_id, reason)

            if result['success']:
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Hash record removed successfully',
                        'record_id': record_id
                    })
                }
            else:
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'error': 'Failed to remove hash record',
                        'details': result.get('error', 'Unknown error')
                    })
                }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown action: {action}',
                    'supported_actions': ['add', 'search', 'remove']
                })
            }

    except Exception as e:
        logger.error(f"Error in NCII hash manager: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }