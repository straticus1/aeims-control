"""
Interstate Activity Tracker Lambda function
Monitors interstate commerce activities for Mann Act compliance
"""
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class InterstateActivityTracker:
    def __init__(self):
        """Initialize interstate activity tracker"""
        self.dynamodb = boto3.resource('dynamodb')
        self.sns = boto3.client('sns')

        # High-risk patterns for interstate tracking
        self.risk_patterns = [
            'traveling',
            'out of state',
            'road trip',
            'cross state',
            'interstate',
            'border crossing'
        ]

        # US state abbreviations
        self.states = [
            'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
            'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
            'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
            'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
            'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY'
        ]

    def analyze_content(self, content: str, metadata: Dict) -> Dict[str, Any]:
        """Analyze content for interstate activity indicators"""
        interstate_indicators = []
        risk_score = 0

        content_lower = content.lower()

        # Check for state mentions
        mentioned_states = []
        for state in self.states:
            if state.lower() in content_lower:
                mentioned_states.append(state)

        if len(mentioned_states) > 1:
            interstate_indicators.append('multiple_states_mentioned')
            risk_score += 3

        # Check for travel/movement patterns
        for pattern in self.risk_patterns:
            if pattern in content_lower:
                interstate_indicators.append(f'pattern_{pattern.replace(" ", "_")}')
                risk_score += 2

        # Check for location metadata
        user_location = metadata.get('user_location', {})
        content_location = metadata.get('content_location', {})

        if user_location and content_location:
            user_state = user_location.get('state')
            content_state = content_location.get('state')

            if user_state and content_state and user_state != content_state:
                interstate_indicators.append('cross_state_posting')
                risk_score += 4

        # Check for transportation references
        transport_terms = ['plane', 'flight', 'train', 'bus', 'drive', 'driving']
        for term in transport_terms:
            if term in content_lower:
                interstate_indicators.append(f'transport_{term}')
                risk_score += 1

        # Determine risk level
        if risk_score >= 8:
            risk_level = 'HIGH'
        elif risk_score >= 5:
            risk_level = 'MEDIUM'
        elif risk_score >= 2:
            risk_level = 'LOW'
        else:
            risk_level = 'NONE'

        return {
            'risk_level': risk_level,
            'risk_score': risk_score,
            'interstate_indicators': interstate_indicators,
            'mentioned_states': mentioned_states,
            'analysis_timestamp': datetime.utcnow().isoformat()
        }

    def track_user_activity(self, user_id: str, activity_data: Dict) -> Dict[str, Any]:
        """Track interstate activity for a specific user"""
        try:
            table = self.dynamodb.Table('interstate-activity-tracking')

            # Get user's activity history
            response = table.query(
                KeyConditionExpression='user_id = :user_id',
                ExpressionAttributeValues={':user_id': user_id},
                ScanIndexForward=False,
                Limit=50
            )

            activities = response.get('Items', [])

            # Analyze pattern across activities
            state_pattern = self.analyze_state_pattern(activities + [activity_data])

            # Store new activity
            activity_record = {
                'user_id': user_id,
                'timestamp': datetime.utcnow().isoformat(),
                'activity_data': activity_data,
                'state_pattern': state_pattern,
                'ttl': int((datetime.utcnow() + timedelta(days=90)).timestamp())
            }

            table.put_item(Item=activity_record)

            return {
                'tracking_success': True,
                'state_pattern': state_pattern,
                'activity_count': len(activities) + 1
            }

        except Exception as e:
            logger.error(f"Error tracking user activity: {str(e)}")
            return {
                'tracking_success': False,
                'error': str(e)
            }

    def analyze_state_pattern(self, activities: List[Dict]) -> Dict[str, Any]:
        """Analyze interstate movement patterns"""
        states_visited = set()
        state_transitions = []

        previous_state = None
        for activity in sorted(activities, key=lambda x: x.get('timestamp', '')):
            location = activity.get('location', {})
            current_state = location.get('state')

            if current_state:
                states_visited.add(current_state)

                if previous_state and previous_state != current_state:
                    state_transitions.append({
                        'from': previous_state,
                        'to': current_state,
                        'timestamp': activity.get('timestamp')
                    })

                previous_state = current_state

        # Calculate risk based on pattern
        pattern_risk = 0
        if len(states_visited) > 3:
            pattern_risk += 3
        if len(state_transitions) > 2:
            pattern_risk += 2

        return {
            'states_visited': list(states_visited),
            'state_count': len(states_visited),
            'transitions': state_transitions,
            'transition_count': len(state_transitions),
            'pattern_risk_score': pattern_risk
        }

def lambda_handler(event, context):
    """Main Lambda handler for interstate activity tracking"""
    try:
        action = event.get('action', 'analyze')
        tracker = InterstateActivityTracker()

        if action == 'analyze':
            content = event.get('content', '')
            metadata = event.get('metadata', {})
            user_id = event.get('user_id', 'anonymous')

            if not content:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'No content provided for analysis'
                    })
                }

            # Analyze content for interstate indicators
            analysis_result = tracker.analyze_content(content, metadata)

            # Track user activity if user identified
            if user_id != 'anonymous':
                activity_data = {
                    'content_analysis': analysis_result,
                    'location': metadata.get('location', {}),
                    'platform': metadata.get('platform', 'unknown')
                }
                tracking_result = tracker.track_user_activity(user_id, activity_data)
                analysis_result['tracking'] = tracking_result

            # Log high-risk interstate activity
            if analysis_result['risk_level'] in ['HIGH', 'MEDIUM']:
                logger.warning(f"Interstate activity detected: "
                             f"Risk={analysis_result['risk_level']}, "
                             f"Score={analysis_result['risk_score']}, "
                             f"User={user_id}")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'analysis': analysis_result,
                    'user_id': user_id,
                    'function_name': context.function_name,
                    'request_id': context.aws_request_id
                }, default=str)
            }

        elif action == 'track':
            user_id = event.get('user_id')
            activity_data = event.get('activity_data', {})

            if not user_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': 'User ID required for tracking'
                    })
                }

            tracking_result = tracker.track_user_activity(user_id, activity_data)

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'tracking_result': tracking_result,
                    'user_id': user_id
                }, default=str)
            }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown action: {action}',
                    'supported_actions': ['analyze', 'track']
                })
            }

    except Exception as e:
        logger.error(f"Error in interstate activity tracker: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'request_id': context.aws_request_id
            })
        }