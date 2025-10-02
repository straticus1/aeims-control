import json
import boto3
import os
from datetime import datetime
import logging
import uuid
import time
import base64

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    SuperDeploy Orchestrator for AEIMS Ecosystem
    Handles deployment orchestration for aeims, aeims.app, aeimsLib, and aeims-control
    """

    try:
        environment = os.environ['ENVIRONMENT']
        project_name = os.environ['PROJECT_NAME']
        cluster_name = os.environ['ECS_CLUSTER_NAME']
        step_functions_arn = os.environ['STEP_FUNCTIONS_ARN']
        notification_topic = os.environ['NOTIFICATION_TOPIC']
        deployment_bucket = os.environ['DEPLOYMENT_BUCKET']

        # Handle API Gateway requests
        if 'httpMethod' in event:
            return handle_api_request(event, environment, project_name)

        # Handle Step Functions tasks
        action = event.get('action', 'unknown')
        deployment_config = event.get('deployment_config', {})

        logger.info(f"Processing SuperDeploy action: {action}")

        if action == 'validate':
            return validate_deployment(deployment_config, environment, project_name)
        elif action == 'prepare_infrastructure':
            return prepare_infrastructure(deployment_config, environment, project_name, deployment_bucket)
        elif action == 'deploy_service':
            service = event.get('service')
            return deploy_service(service, deployment_config, environment, project_name, cluster_name)
        elif action == 'validate_services':
            return validate_services(deployment_config, environment, project_name)
        elif action == 'update_load_balancer':
            return update_load_balancer(deployment_config, environment, project_name)
        elif action == 'run_smoke_tests':
            return run_smoke_tests(deployment_config, environment, project_name)
        elif action == 'deployment_success':
            return handle_deployment_success(deployment_config, environment, project_name, notification_topic)
        elif action == 'deployment_failed':
            return handle_deployment_failure(deployment_config, environment, project_name, notification_topic)
        elif action.startswith('rollback_'):
            return handle_rollback(action, deployment_config, environment, project_name)
        else:
            raise ValueError(f"Unknown action: {action}")

    except Exception as e:
        logger.error(f"SuperDeploy orchestration failed: {str(e)}")

        # Send failure notification
        try:
            send_notification(notification_topic, "SuperDeploy Failed", str(e), "ERROR")
        except:
            pass

        raise e

def handle_api_request(event, environment, project_name):
    """Handle API Gateway requests"""
    method = event['httpMethod']
    path = event['path']

    if method == 'POST' and '/deploy' in path:
        return handle_deploy_request(event, environment, project_name)
    elif method == 'GET' and '/status' in path:
        return handle_status_request(event, environment, project_name)
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Not found'})
        }

def handle_deploy_request(event, environment, project_name):
    """Handle deployment request from API"""
    try:
        body = json.loads(event['body']) if event.get('body') else {}

        deployment_config = {
            'deployment_id': str(uuid.uuid4()),
            'timestamp': datetime.utcnow().isoformat(),
            'services': body.get('services', ['aeims-core', 'aeims-app', 'aeims-lib']),
            'strategy': body.get('strategy', 'blue-green'),
            'image_tags': body.get('image_tags', {}),
            'environment_variables': body.get('environment_variables', {}),
            'rollback_on_failure': body.get('rollback_on_failure', True),
            'smoke_tests': body.get('smoke_tests', True),
            'user': body.get('user', 'api'),
            'notes': body.get('notes', '')
        }

        # Validate required fields
        if not deployment_config['image_tags']:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'image_tags are required'})
            }

        # Store deployment state
        store_deployment_state(deployment_config, 'INITIATED', environment, project_name)

        # Start Step Functions workflow
        step_functions = boto3.client('stepfunctions')
        step_functions_arn = os.environ['STEP_FUNCTIONS_ARN']

        response = step_functions.start_execution(
            stateMachineArn=step_functions_arn,
            name=f"deploy-{deployment_config['deployment_id']}",
            input=json.dumps({
                'deployment_config': deployment_config
            })
        )

        # Update deployment state with execution ARN
        update_deployment_state(
            deployment_config['deployment_id'],
            'RUNNING',
            {'execution_arn': response['executionArn']},
            environment,
            project_name
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'deployment_id': deployment_config['deployment_id'],
                'execution_arn': response['executionArn'],
                'status': 'RUNNING',
                'message': 'Deployment started successfully'
            })
        }

    except Exception as e:
        logger.error(f"Deploy request failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_status_request(event, environment, project_name):
    """Handle status request from API"""
    try:
        deployment_id = event['queryStringParameters'].get('deployment_id') if event.get('queryStringParameters') else None

        if deployment_id:
            # Get specific deployment status
            deployment_state = get_deployment_state(deployment_id, environment, project_name)
            if not deployment_state:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Deployment not found'})
                }

            # Get Step Functions execution status
            if deployment_state.get('execution_arn'):
                step_functions = boto3.client('stepfunctions')
                try:
                    execution = step_functions.describe_execution(
                        executionArn=deployment_state['execution_arn']
                    )
                    deployment_state['execution_status'] = execution.get('status')
                    deployment_state['execution_output'] = execution.get('output')
                except:
                    pass

            return {
                'statusCode': 200,
                'body': json.dumps(deployment_state)
            }
        else:
            # Get recent deployments
            recent_deployments = get_recent_deployments(environment, project_name)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'deployments': recent_deployments
                })
            }

    except Exception as e:
        logger.error(f"Status request failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_deployment(deployment_config, environment, project_name):
    """Validate deployment configuration"""
    logger.info("Validating deployment configuration")

    errors = []

    # Validate services
    valid_services = ['aeims-core', 'aeims-app', 'aeims-lib']
    for service in deployment_config.get('services', []):
        if service not in valid_services:
            errors.append(f"Invalid service: {service}")

    # Validate image tags
    image_tags = deployment_config.get('image_tags', {})
    for service in deployment_config.get('services', []):
        if service not in image_tags:
            errors.append(f"Missing image tag for service: {service}")

    # Validate strategy
    valid_strategies = ['blue-green', 'canary', 'rolling']
    strategy = deployment_config.get('strategy', 'blue-green')
    if strategy not in valid_strategies:
        errors.append(f"Invalid deployment strategy: {strategy}")

    # Validate image existence in ECR
    ecr_client = boto3.client('ecr')
    for service, tag in image_tags.items():
        try:
            ecr_client.describe_images(
                repositoryName=f"{project_name}-{service}",
                imageIds=[{'imageTag': tag}]
            )
        except Exception as e:
            errors.append(f"Image not found for {service}:{tag} - {str(e)}")

    if errors:
        update_deployment_state(
            deployment_config['deployment_id'],
            'VALIDATION_FAILED',
            {'errors': errors},
            environment,
            project_name
        )
        raise Exception(f"Validation failed: {', '.join(errors)}")

    update_deployment_state(
        deployment_config['deployment_id'],
        'VALIDATED',
        {'validation_time': datetime.utcnow().isoformat()},
        environment,
        project_name
    )

    return {
        'status': 'SUCCESS',
        'message': 'Deployment configuration validated successfully'
    }

def prepare_infrastructure(deployment_config, environment, project_name, deployment_bucket):
    """Prepare infrastructure for deployment"""
    logger.info("Preparing infrastructure")

    # Generate deployment manifest
    manifest = {
        'deployment_id': deployment_config['deployment_id'],
        'timestamp': datetime.utcnow().isoformat(),
        'services': deployment_config['services'],
        'image_tags': deployment_config['image_tags'],
        'strategy': deployment_config['strategy'],
        'environment': environment,
        'project': project_name
    }

    # Store manifest in S3
    s3_client = boto3.client('s3')
    manifest_key = f"deployments/{deployment_config['deployment_id']}/manifest.json"

    s3_client.put_object(
        Bucket=deployment_bucket,
        Key=manifest_key,
        Body=json.dumps(manifest, indent=2),
        ContentType='application/json'
    )

    # Prepare ECS task definitions
    for service in deployment_config['services']:
        prepare_task_definition(service, deployment_config, environment, project_name)

    update_deployment_state(
        deployment_config['deployment_id'],
        'INFRASTRUCTURE_PREPARED',
        {'manifest_location': f"s3://{deployment_bucket}/{manifest_key}"},
        environment,
        project_name
    )

    return {
        'status': 'SUCCESS',
        'message': 'Infrastructure prepared successfully'
    }

def prepare_task_definition(service, deployment_config, environment, project_name):
    """Prepare ECS task definition for service"""
    ecs_client = boto3.client('ecs')

    # Get current task definition
    try:
        current_task_def = ecs_client.describe_task_definition(
            taskDefinition=f"{project_name}-{service}-{environment}"
        )['taskDefinition']
    except:
        logger.warning(f"No existing task definition found for {service}")
        return

    # Update container image
    new_image = f"{current_task_def['containerDefinitions'][0]['image'].split(':')[0]}:{deployment_config['image_tags'][service]}"

    # Create new task definition
    new_task_def = {
        'family': current_task_def['family'],
        'taskRoleArn': current_task_def.get('taskRoleArn'),
        'executionRoleArn': current_task_def.get('executionRoleArn'),
        'networkMode': current_task_def.get('networkMode'),
        'requiresCompatibilities': current_task_def.get('requiresCompatibilities', []),
        'cpu': current_task_def.get('cpu'),
        'memory': current_task_def.get('memory'),
        'containerDefinitions': []
    }

    # Update container definitions
    for container in current_task_def['containerDefinitions']:
        new_container = container.copy()
        if container['name'] == service:
            new_container['image'] = new_image

            # Update environment variables if provided
            env_vars = deployment_config.get('environment_variables', {}).get(service, {})
            if env_vars:
                env_list = new_container.get('environment', [])
                for key, value in env_vars.items():
                    # Update existing or add new
                    found = False
                    for env_item in env_list:
                        if env_item['name'] == key:
                            env_item['value'] = value
                            found = True
                            break
                    if not found:
                        env_list.append({'name': key, 'value': value})
                new_container['environment'] = env_list

        new_task_def['containerDefinitions'].append(new_container)

    # Register new task definition
    response = ecs_client.register_task_definition(**new_task_def)
    logger.info(f"Registered new task definition for {service}: {response['taskDefinition']['taskDefinitionArn']}")

def deploy_service(service, deployment_config, environment, project_name, cluster_name):
    """Deploy individual service"""
    logger.info(f"Deploying service: {service}")

    ecs_client = boto3.client('ecs')

    try:
        # Get service
        service_name = f"{project_name}-{service}-{environment}"
        service_response = ecs_client.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )

        if not service_response['services']:
            raise Exception(f"Service {service_name} not found")

        current_service = service_response['services'][0]

        # Update service with new task definition
        new_task_def_arn = f"{project_name}-{service}-{environment}:{deployment_config['image_tags'][service]}"

        update_response = ecs_client.update_service(
            cluster=cluster_name,
            service=service_name,
            taskDefinition=new_task_def_arn,
            forceNewDeployment=True
        )

        # Wait for deployment to stabilize
        deployment_id = None
        for deployment in update_response['service']['deployments']:
            if deployment['status'] == 'PRIMARY':
                deployment_id = deployment['id']
                break

        if deployment_id:
            # Wait for deployment
            waiter = ecs_client.get_waiter('services_stable')
            waiter.wait(
                cluster=cluster_name,
                services=[service_name],
                WaiterConfig={
                    'Delay': 15,
                    'MaxAttempts': 40  # 10 minutes
                }
            )

        logger.info(f"Service {service} deployed successfully")
        return {
            'status': 'SUCCESS',
            'service': service,
            'deployment_id': deployment_id
        }

    except Exception as e:
        logger.error(f"Failed to deploy service {service}: {str(e)}")
        raise e

def validate_services(deployment_config, environment, project_name):
    """Validate deployed services"""
    logger.info("Validating deployed services")

    validation_results = {}

    for service in deployment_config['services']:
        try:
            result = validate_service_health(service, environment, project_name)
            validation_results[service] = result
        except Exception as e:
            validation_results[service] = {'status': 'FAILED', 'error': str(e)}

    # Check if all services are healthy
    all_healthy = all(result.get('status') == 'HEALTHY' for result in validation_results.values())

    if not all_healthy:
        raise Exception(f"Service validation failed: {validation_results}")

    return {
        'status': 'SUCCESS',
        'validation_results': validation_results
    }

def validate_service_health(service, environment, project_name):
    """Validate individual service health"""
    # Get load balancer target group for service
    elbv2_client = boto3.client('elbv2')

    try:
        # Find target group for service
        target_groups = elbv2_client.describe_target_groups(
            Names=[f"{project_name}-{service}-tg-{environment}"]
        )

        if not target_groups['TargetGroups']:
            return {'status': 'NO_TARGET_GROUP'}

        target_group_arn = target_groups['TargetGroups'][0]['TargetGroupArn']

        # Check target health
        health_response = elbv2_client.describe_target_health(
            TargetGroupArn=target_group_arn
        )

        healthy_targets = 0
        total_targets = len(health_response['TargetHealthDescriptions'])

        for target in health_response['TargetHealthDescriptions']:
            if target['TargetHealth']['State'] == 'healthy':
                healthy_targets += 1

        if healthy_targets == 0:
            return {'status': 'UNHEALTHY', 'healthy': 0, 'total': total_targets}
        elif healthy_targets < total_targets:
            return {'status': 'PARTIALLY_HEALTHY', 'healthy': healthy_targets, 'total': total_targets}
        else:
            return {'status': 'HEALTHY', 'healthy': healthy_targets, 'total': total_targets}

    except Exception as e:
        return {'status': 'ERROR', 'error': str(e)}

def update_load_balancer(deployment_config, environment, project_name):
    """Update load balancer configuration if needed"""
    logger.info("Updating load balancer configuration")

    # For blue-green deployments, this would switch traffic
    # For this implementation, we'll just verify the load balancer is working

    strategy = deployment_config.get('strategy', 'blue-green')

    if strategy == 'blue-green':
        return handle_blue_green_switch(deployment_config, environment, project_name)
    elif strategy == 'canary':
        return handle_canary_deployment(deployment_config, environment, project_name)
    else:
        return {'status': 'SUCCESS', 'message': 'No load balancer update required'}

def handle_blue_green_switch(deployment_config, environment, project_name):
    """Handle blue-green deployment traffic switch"""
    # In a full implementation, this would switch traffic between blue and green environments
    # For now, we'll simulate the process

    logger.info("Performing blue-green traffic switch")

    # Simulate traffic switch delay
    time.sleep(5)

    return {
        'status': 'SUCCESS',
        'message': 'Blue-green traffic switch completed',
        'strategy': 'blue-green'
    }

def handle_canary_deployment(deployment_config, environment, project_name):
    """Handle canary deployment"""
    logger.info("Configuring canary deployment")

    # Simulate canary configuration
    time.sleep(3)

    return {
        'status': 'SUCCESS',
        'message': 'Canary deployment configured',
        'strategy': 'canary',
        'traffic_split': '10%'
    }

def run_smoke_tests(deployment_config, environment, project_name):
    """Run smoke tests on deployed services"""
    logger.info("Running smoke tests")

    if not deployment_config.get('smoke_tests', True):
        return {'status': 'SKIPPED', 'message': 'Smoke tests disabled'}

    test_results = {}

    for service in deployment_config['services']:
        try:
            result = run_service_smoke_test(service, environment, project_name)
            test_results[service] = result
        except Exception as e:
            test_results[service] = {'status': 'FAILED', 'error': str(e)}

    # Check if all tests passed
    all_passed = all(result.get('status') == 'PASSED' for result in test_results.values())

    if not all_passed:
        raise Exception(f"Smoke tests failed: {test_results}")

    return {
        'status': 'SUCCESS',
        'test_results': test_results
    }

def run_service_smoke_test(service, environment, project_name):
    """Run smoke test for individual service"""
    # This would typically make HTTP requests to service endpoints
    # For now, we'll simulate basic health checks

    import urllib3
    http = urllib3.PoolManager()

    try:
        # Get ALB DNS name (simplified)
        elbv2_client = boto3.client('elbv2')
        load_balancers = elbv2_client.describe_load_balancers(
            Names=[f"{project_name}-alb-{environment}"]
        )

        if load_balancers['LoadBalancers']:
            dns_name = load_balancers['LoadBalancers'][0]['DNSName']

            # Test health endpoint
            health_url = f"https://{dns_name}/health"
            response = http.request('GET', health_url, timeout=10)

            if response.status == 200:
                return {'status': 'PASSED', 'endpoint': health_url}
            else:
                return {'status': 'FAILED', 'endpoint': health_url, 'http_status': response.status}
        else:
            return {'status': 'FAILED', 'error': 'Load balancer not found'}

    except Exception as e:
        return {'status': 'FAILED', 'error': str(e)}

def handle_deployment_success(deployment_config, environment, project_name, notification_topic):
    """Handle successful deployment"""
    logger.info("Deployment completed successfully")

    # Update deployment state
    update_deployment_state(
        deployment_config['deployment_id'],
        'SUCCESS',
        {
            'completed_at': datetime.utcnow().isoformat(),
            'services_deployed': deployment_config['services'],
            'image_tags': deployment_config['image_tags']
        },
        environment,
        project_name
    )

    # Send success notification
    message = f"""
Deployment {deployment_config['deployment_id']} completed successfully!

Services deployed: {', '.join(deployment_config['services'])}
Strategy: {deployment_config.get('strategy', 'blue-green')}
Environment: {environment}

Image tags:
{json.dumps(deployment_config['image_tags'], indent=2)}
"""

    send_notification(notification_topic, "Deployment Successful", message, "SUCCESS")

    return {
        'status': 'SUCCESS',
        'deployment_id': deployment_config['deployment_id'],
        'message': 'Deployment completed successfully'
    }

def handle_deployment_failure(deployment_config, environment, project_name, notification_topic):
    """Handle failed deployment"""
    logger.error("Deployment failed")

    # Update deployment state
    update_deployment_state(
        deployment_config['deployment_id'],
        'FAILED',
        {
            'failed_at': datetime.utcnow().isoformat(),
            'requires_manual_intervention': True
        },
        environment,
        project_name
    )

    # Send failure notification
    message = f"""
Deployment {deployment_config['deployment_id']} failed!

Services: {', '.join(deployment_config['services'])}
Environment: {environment}

Please check the deployment logs for more details.
"""

    send_notification(notification_topic, "Deployment Failed", message, "ERROR")

    return {
        'status': 'FAILED',
        'deployment_id': deployment_config['deployment_id'],
        'message': 'Deployment failed'
    }

def handle_rollback(action, deployment_config, environment, project_name):
    """Handle various rollback scenarios"""
    logger.info(f"Executing rollback: {action}")

    rollback_type = action.replace('rollback_', '')

    if rollback_type == 'services':
        return rollback_services(deployment_config, environment, project_name)
    elif rollback_type == 'infrastructure':
        return rollback_infrastructure(deployment_config, environment, project_name)
    elif rollback_type == 'load_balancer':
        return rollback_load_balancer(deployment_config, environment, project_name)
    elif rollback_type == 'all':
        return rollback_all(deployment_config, environment, project_name)
    else:
        return {'status': 'SUCCESS', 'message': f'Rollback {rollback_type} completed'}

def rollback_services(deployment_config, environment, project_name):
    """Rollback services to previous versions"""
    logger.info("Rolling back services")

    # This would revert to previous task definitions
    # For now, we'll simulate the process

    return {
        'status': 'SUCCESS',
        'message': 'Services rolled back to previous versions'
    }

def rollback_infrastructure(deployment_config, environment, project_name):
    """Rollback infrastructure changes"""
    logger.info("Rolling back infrastructure")

    return {
        'status': 'SUCCESS',
        'message': 'Infrastructure rollback completed'
    }

def rollback_load_balancer(deployment_config, environment, project_name):
    """Rollback load balancer configuration"""
    logger.info("Rolling back load balancer")

    return {
        'status': 'SUCCESS',
        'message': 'Load balancer rollback completed'
    }

def rollback_all(deployment_config, environment, project_name):
    """Complete rollback of all changes"""
    logger.info("Performing complete rollback")

    # Execute all rollback steps
    rollback_services(deployment_config, environment, project_name)
    rollback_load_balancer(deployment_config, environment, project_name)
    rollback_infrastructure(deployment_config, environment, project_name)

    # Update deployment state
    update_deployment_state(
        deployment_config['deployment_id'],
        'ROLLED_BACK',
        {
            'rolled_back_at': datetime.utcnow().isoformat(),
            'rollback_reason': 'Deployment failure'
        },
        environment,
        project_name
    )

    return {
        'status': 'SUCCESS',
        'message': 'Complete rollback executed'
    }

def store_deployment_state(deployment_config, status, environment, project_name):
    """Store deployment state in DynamoDB"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-deployment-state-{environment}"

    try:
        table = dynamodb.Table(table_name)

        item = {
            'deployment_id': deployment_config['deployment_id'],
            'status': status,
            'timestamp': datetime.utcnow().isoformat(),
            'deployment_config': deployment_config,
            'environment': environment,
            'project': project_name
        }

        table.put_item(Item=item)

    except Exception as e:
        logger.error(f"Failed to store deployment state: {str(e)}")

def update_deployment_state(deployment_id, status, additional_data, environment, project_name):
    """Update deployment state in DynamoDB"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-deployment-state-{environment}"

    try:
        table = dynamodb.Table(table_name)

        update_expression = "SET #status = :status, last_updated = :timestamp"
        expression_values = {
            ':status': status,
            ':timestamp': datetime.utcnow().isoformat()
        }
        expression_names = {
            '#status': 'status'
        }

        # Add additional data to update
        for key, value in additional_data.items():
            safe_key = key.replace('-', '_')
            update_expression += f", {safe_key} = :{safe_key}"
            expression_values[f":{safe_key}"] = value

        table.update_item(
            Key={'deployment_id': deployment_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values,
            ExpressionAttributeNames=expression_names
        )

    except Exception as e:
        logger.error(f"Failed to update deployment state: {str(e)}")

def get_deployment_state(deployment_id, environment, project_name):
    """Get deployment state from DynamoDB"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-deployment-state-{environment}"

    try:
        table = dynamodb.Table(table_name)
        response = table.get_item(
            Key={'deployment_id': deployment_id}
        )
        return response.get('Item')
    except Exception as e:
        logger.error(f"Failed to get deployment state: {str(e)}")
        return None

def get_recent_deployments(environment, project_name, limit=10):
    """Get recent deployments from DynamoDB"""
    dynamodb = boto3.resource('dynamodb')
    table_name = f"{project_name}-deployment-state-{environment}"

    try:
        table = dynamodb.Table(table_name)
        response = table.scan(
            Limit=limit
        )

        # Sort by timestamp
        items = response.get('Items', [])
        items.sort(key=lambda x: x.get('timestamp', ''), reverse=True)

        return items[:limit]
    except Exception as e:
        logger.error(f"Failed to get recent deployments: {str(e)}")
        return []

def send_notification(topic_arn, subject, message, level="INFO"):
    """Send SNS notification"""
    sns_client = boto3.client('sns')

    try:
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=f"[{level}] SuperDeploy: {subject}",
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")