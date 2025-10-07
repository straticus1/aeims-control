"""
FOSTA Content Filter Lambda Function

This function implements content filtering in compliance with the Fight Online Sex
Trafficking Act (FOSTA-SESTA) to detect and prevent prohibited content that facilitates
sex trafficking.

Author: AEIMS Platform
Last Updated: 2025
"""

import json
import logging
import boto3
import re
import hashlib
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
comprehend = boto3.client('comprehend')
textract = boto3.client('textract')
s3 = boto3.client('s3')
sns = boto3.client('sns')

# Configuration
CONFIDENCE_THRESHOLD = float(os.environ.get('CONFIDENCE_THRESHOLD', '0.8'))
ALERT_SNS_TOPIC = os.environ.get('ALERT_SNS_TOPIC_ARN')
QUARANTINE_BUCKET = os.environ.get('QUARANTINE_BUCKET')

class FOSTAContentFilter:
    """Main class for FOSTA content filtering operations"""

    def __init__(self):
        self.prohibited_patterns = [
            # Sex trafficking indicators
            r'\b(?:escort|massage)\s+(?:service|parlor)\b',
            r'\b(?:young|barely|teen)\s+(?:girl|woman)\b',
            r'\bno\s+questions?\s+asked\b',
            r'\bcash\s+only\b',
            r'\bdiscretion\s+guaranteed\b',
            r'\bprivate\s+room\b',
            # Commercial sex act indicators
            r'\b(?:donation|roses|gift)\s+for\s+(?:time|company)\b',
            r'\b(?:full\s+service|gfe|greek)\b',
            r'\b(?:incall|outcall)\s+available\b',
            # Trafficking language patterns
            r'\bnew\s+(?:in\s+)?town\b',
            r'\btravel(?:ing|ling)?\s+(?:girl|woman)\b',
            r'\b(?:exotic|foreign)\s+(?:girl|woman)\b'
        ]

        self.trafficking_keywords = [
            'escort', 'massage', 'companionship', 'entertainment',
            'discrete', 'discreet', 'private', 'personal', 'intimate',
            'donation', 'gift', 'roses', 'generous', 'upscale'
        ]

    def analyze_text_content(self, text: str) -> Dict[str, Any]:
        """Analyze text content for FOSTA violations"""
        try:
            results = {
                'violation_detected': False,
                'confidence_score': 0.0,
                'violation_types': [],
                'flagged_patterns': [],
                'risk_indicators': []
            }

            # Pattern matching for prohibited content
            pattern_matches = []
            for pattern in self.prohibited_patterns:
                matches = re.finditer(pattern, text, re.IGNORECASE)
                for match in matches:
                    pattern_matches.append({
                        'pattern': pattern,
                        'match': match.group(),
                        'position': match.span()
                    })

            if pattern_matches:
                results['violation_detected'] = True
                results['flagged_patterns'] = pattern_matches
                results['violation_types'].append('prohibited_pattern_match')
                results['confidence_score'] = min(0.9, len(pattern_matches) * 0.3)

            # Keyword density analysis
            keyword_count = 0
            words = text.lower().split()
            for keyword in self.trafficking_keywords:
                keyword_count += words.count(keyword)

            keyword_density = keyword_count / max(len(words), 1)
            if keyword_density > 0.05:  # 5% threshold
                results['violation_detected'] = True
                results['violation_types'].append('high_risk_keyword_density')
                results['risk_indicators'].append(f'keyword_density: {keyword_density:.3f}')
                results['confidence_score'] = max(results['confidence_score'], keyword_density * 2)

            # Use AWS Comprehend for additional analysis
            try:
                sentiment_response = comprehend.detect_sentiment(
                    Text=text[:5000],  # Comprehend limit
                    LanguageCode='en'
                )

                # Check for commercial/transactional sentiment patterns
                if sentiment_response['Sentiment'] == 'POSITIVE' and \
                   sentiment_response['SentimentScore']['Positive'] > 0.8:
                    results['risk_indicators'].append('suspicious_positive_sentiment')
                    results['confidence_score'] = max(results['confidence_score'], 0.3)

            except Exception as e:
                logger.warning(f"Comprehend analysis failed: {str(e)}")

            # Final confidence adjustment
            results['confidence_score'] = min(1.0, results['confidence_score'])

            return results

        except Exception as e:
            logger.error(f"Text analysis error: {str(e)}")
            raise

    def process_image_content(self, image_data: bytes) -> Dict[str, Any]:
        """Process image content using AWS Textract"""
        try:
            # Extract text from image
            response = textract.detect_document_text(
                Document={'Bytes': image_data}
            )

            # Combine extracted text
            extracted_text = ""
            for block in response['Blocks']:
                if block['BlockType'] == 'LINE':
                    extracted_text += block['Text'] + " "

            if extracted_text.strip():
                return self.analyze_text_content(extracted_text)
            else:
                return {
                    'violation_detected': False,
                    'confidence_score': 0.0,
                    'violation_types': [],
                    'flagged_patterns': [],
                    'risk_indicators': ['no_text_extracted']
                }

        except Exception as e:
            logger.error(f"Image processing error: {str(e)}")
            return {
                'violation_detected': False,
                'confidence_score': 0.0,
                'violation_types': ['processing_error'],
                'flagged_patterns': [],
                'risk_indicators': [f'error: {str(e)}']
            }

    def quarantine_content(self, content_id: str, content_data: bytes,
                          analysis_result: Dict[str, Any]) -> bool:
        """Quarantine flagged content"""
        try:
            if not QUARANTINE_BUCKET:
                logger.warning("No quarantine bucket configured")
                return False

            timestamp = datetime.now(timezone.utc).isoformat()
            key = f"fosta-violations/{timestamp}/{content_id}"

            # Store content
            s3.put_object(
                Bucket=QUARANTINE_BUCKET,
                Key=key,
                Body=content_data,
                Metadata={
                    'violation_type': ','.join(analysis_result['violation_types']),
                    'confidence_score': str(analysis_result['confidence_score']),
                    'quarantine_reason': 'FOSTA_compliance_violation',
                    'timestamp': timestamp
                }
            )

            # Store analysis report
            report_key = f"{key}.analysis.json"
            s3.put_object(
                Bucket=QUARANTINE_BUCKET,
                Key=report_key,
                Body=json.dumps(analysis_result, indent=2),
                ContentType='application/json'
            )

            logger.info(f"Content quarantined: {key}")
            return True

        except Exception as e:
            logger.error(f"Quarantine error: {str(e)}")
            return False

    def send_alert(self, content_id: str, analysis_result: Dict[str, Any]) -> bool:
        """Send alert for FOSTA violations"""
        try:
            if not ALERT_SNS_TOPIC:
                logger.warning("No alert SNS topic configured")
                return False

            message = {
                'alert_type': 'FOSTA_VIOLATION_DETECTED',
                'content_id': content_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'violation_types': analysis_result['violation_types'],
                'confidence_score': analysis_result['confidence_score'],
                'flagged_patterns': analysis_result['flagged_patterns'],
                'risk_indicators': analysis_result['risk_indicators'],
                'severity': 'HIGH' if analysis_result['confidence_score'] > 0.8 else 'MEDIUM',
                'action_required': True
            }

            sns.publish(
                TopicArn=ALERT_SNS_TOPIC,
                Subject=f"FOSTA Violation Alert - Content ID: {content_id}",
                Message=json.dumps(message, indent=2)
            )

            logger.info(f"FOSTA violation alert sent for content: {content_id}")
            return True

        except Exception as e:
            logger.error(f"Alert sending error: {str(e)}")
            return False


def lambda_handler(event, context):
    """
    Lambda handler for FOSTA content filtering

    Expected event structure:
    {
        "content_id": "unique_content_identifier",
        "content_type": "text|image",
        "content_data": "base64_encoded_content_or_text",
        "source": "upload|chat|profile|listing"
    }
    """
    try:
        logger.info(f"Processing FOSTA content filter request: {event.get('content_id', 'unknown')}")

        # Validate input
        required_fields = ['content_id', 'content_type', 'content_data']
        for field in required_fields:
            if field not in event:
                raise ValueError(f"Missing required field: {field}")

        content_id = event['content_id']
        content_type = event['content_type'].lower()
        content_data = event['content_data']
        source = event.get('source', 'unknown')

        # Initialize filter
        filter_instance = FOSTAContentFilter()

        # Process based on content type
        if content_type == 'text':
            analysis_result = filter_instance.analyze_text_content(content_data)
        elif content_type == 'image':
            import base64
            image_bytes = base64.b64decode(content_data)
            analysis_result = filter_instance.process_image_content(image_bytes)
        else:
            raise ValueError(f"Unsupported content type: {content_type}")

        # Determine action based on analysis
        action_taken = "none"
        violation_detected = analysis_result['violation_detected']
        confidence_score = analysis_result['confidence_score']

        if violation_detected and confidence_score >= CONFIDENCE_THRESHOLD:
            # High confidence violation - quarantine and alert
            if content_type == 'image':
                content_bytes = base64.b64decode(content_data)
            else:
                content_bytes = content_data.encode('utf-8')

            quarantined = filter_instance.quarantine_content(
                content_id, content_bytes, analysis_result
            )
            alert_sent = filter_instance.send_alert(content_id, analysis_result)

            action_taken = "quarantined_and_alerted"

        elif violation_detected:
            # Lower confidence - alert only
            filter_instance.send_alert(content_id, analysis_result)
            action_taken = "alerted"

        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'content_id': content_id,
                'filtered': True,
                'violation_detected': violation_detected,
                'confidence_score': confidence_score,
                'violation_types': analysis_result['violation_types'],
                'action_taken': action_taken,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'compliance_framework': 'FOSTA-SESTA',
                'risk_level': 'HIGH' if confidence_score > 0.8 else 'MEDIUM' if confidence_score > 0.5 else 'LOW'
            }
        }

        logger.info(f"FOSTA filtering completed for {content_id}: {action_taken}")
        return response

    except ValueError as e:
        logger.error(f"Input validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': {
                'error': 'Invalid input',
                'message': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }

    except Exception as e:
        logger.error(f"FOSTA content filter error: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal server error',
                'message': 'Content filtering failed',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        }