import json
import boto3
import logging
from datetime import datetime, timedelta
import numpy as np

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Predictive Scaling Lambda Function
    Analyzes historical metrics to predict scaling needs for AEIMS platform
    """

    # Configuration from Terraform template variables
    environment = "${environment}"
    project_name = "${project_name}"

    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    ecs = boto3.client('ecs')

    try:
        logger.info(f"Starting predictive scaling analysis for {project_name} in {environment}")

        # Get ECS services for the project
        cluster_name = f"{project_name}-cluster-{environment}"

        # List services in the cluster
        services_response = ecs.list_services(cluster=cluster_name)
        services = services_response['serviceArns']

        scaling_recommendations = []

        for service_arn in services:
            service_name = service_arn.split('/')[-1]

            if project_name in service_name:
                logger.info(f"Analyzing service: {service_name}")

                # Get historical CPU utilization
                end_time = datetime.utcnow()
                start_time = end_time - timedelta(days=7)

                cpu_metrics = cloudwatch.get_metric_statistics(
                    Namespace='AWS/ECS',
                    MetricName='CPUUtilization',
                    Dimensions=[
                        {
                            'Name': 'ServiceName',
                            'Value': service_name
                        },
                        {
                            'Name': 'ClusterName',
                            'Value': cluster_name
                        }
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,  # 1 hour intervals
                    Statistics=['Average', 'Maximum']
                )

                if cpu_metrics['Datapoints']:
                    # Simple predictive algorithm
                    cpu_values = [dp['Average'] for dp in cpu_metrics['Datapoints']]
                    max_cpu_values = [dp['Maximum'] for dp in cpu_metrics['Datapoints']]

                    avg_cpu = np.mean(cpu_values)
                    max_cpu = np.max(max_cpu_values)
                    trend = np.polyfit(range(len(cpu_values)), cpu_values, 1)[0]

                    # Predict next hour's CPU usage
                    predicted_cpu = avg_cpu + (trend * 24)  # 24 hours ahead

                    # Scaling recommendation logic
                    current_tasks = get_current_task_count(ecs, cluster_name, service_name)
                    recommended_tasks = current_tasks

                    if predicted_cpu > 70:
                        recommended_tasks = min(current_tasks + 2, 10)  # Scale up
                        action = "scale_up"
                    elif predicted_cpu < 30 and current_tasks > 2:
                        recommended_tasks = max(current_tasks - 1, 2)  # Scale down
                        action = "scale_down"
                    else:
                        action = "no_change"

                    scaling_recommendations.append({
                        'service': service_name,
                        'current_tasks': current_tasks,
                        'recommended_tasks': recommended_tasks,
                        'predicted_cpu': round(predicted_cpu, 2),
                        'avg_cpu_7days': round(avg_cpu, 2),
                        'max_cpu_7days': round(max_cpu, 2),
                        'trend': round(trend, 4),
                        'action': action
                    })

                    logger.info(f"Service {service_name}: predicted CPU {predicted_cpu:.2f}%, action: {action}")

        logger.info(f"Predictive scaling analysis completed. {len(scaling_recommendations)} services analyzed")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Predictive scaling analysis completed',
                'environment': environment,
                'project': project_name,
                'timestamp': datetime.utcnow().isoformat(),
                'recommendations': scaling_recommendations
            })
        }

    except Exception as e:
        logger.error(f"Predictive scaling analysis failed: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Predictive scaling analysis failed',
                'error': str(e),
                'environment': environment,
                'project': project_name
            })
        }

def get_current_task_count(ecs, cluster_name, service_name):
    """Get current running task count for a service"""
    try:
        response = ecs.describe_services(
            cluster=cluster_name,
            services=[service_name]
        )

        if response['services']:
            return response['services'][0]['runningCount']
        return 0
    except Exception:
        return 0