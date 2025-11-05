#!/bin/bash

###############################################################################
# AEIMS Site Monitoring Setup
# Configures comprehensive monitoring and alerting for all client sites
###############################################################################

set -euo pipefail

# Configuration
SITES=(
    "flirts.nyc"
    "nycflirts.com"
    "fantasyflirts.live"
    "holyflirts.com"
)
ALERT_EMAIL="${ALERT_EMAIL:-coleman.ryan@gmail.com}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SNS_TOPIC_NAME="aeims-site-alerts"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

###############################################################################
# Create SNS Topic for Alerts
###############################################################################

setup_sns() {
    log "Setting up SNS topic for alerts..."

    # Create SNS topic
    topic_arn=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --region "$AWS_REGION" \
        --query 'TopicArn' \
        --output text 2>/dev/null || \
        aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

    if [ -n "$topic_arn" ]; then
        success "SNS topic created/found: $topic_arn"

        # Subscribe email
        aws sns subscribe \
            --topic-arn "$topic_arn" \
            --protocol email \
            --notification-endpoint "$ALERT_EMAIL" \
            --region "$AWS_REGION" 2>/dev/null || true

        success "Email subscription added: $ALERT_EMAIL"
        echo "$topic_arn"
    else
        echo "ERROR: Failed to create SNS topic"
        return 1
    fi
}

###############################################################################
# Create CloudWatch Alarms
###############################################################################

setup_cloudwatch_alarms() {
    local topic_arn=$1
    log "Setting up CloudWatch alarms..."

    # Get ALB ARN
    alb_arn=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, 'aeims')].LoadBalancerArn" \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$alb_arn" ]; then
        alb_name=$(echo "$alb_arn" | awk -F'/' '{print $(NF-2)"/"$(NF-1)"/"$NF}')

        # 5XX Errors
        aws cloudwatch put-metric-alarm \
            --alarm-name "AEIMS-HTTP-5XX-Errors" \
            --alarm-description "Alert when ALB returns 5XX errors" \
            --metric-name "HTTPCode_Target_5XX_Count" \
            --namespace "AWS/ApplicationELB" \
            --statistic "Sum" \
            --period 300 \
            --threshold 10 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 1 \
            --dimensions "Name=LoadBalancer,Value=$alb_name" \
            --alarm-actions "$topic_arn" \
            --region "$AWS_REGION"

        success "Created alarm: AEIMS-HTTP-5XX-Errors"

        # Unhealthy Target Count
        aws cloudwatch put-metric-alarm \
            --alarm-name "AEIMS-Unhealthy-Targets" \
            --alarm-description "Alert when targets become unhealthy" \
            --metric-name "UnHealthyHostCount" \
            --namespace "AWS/ApplicationELB" \
            --statistic "Average" \
            --period 300 \
            --threshold 1 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 2 \
            --dimensions "Name=LoadBalancer,Value=$alb_name" \
            --alarm-actions "$topic_arn" \
            --region "$AWS_REGION"

        success "Created alarm: AEIMS-Unhealthy-Targets"

        # High Response Time
        aws cloudwatch put-metric-alarm \
            --alarm-name "AEIMS-High-Response-Time" \
            --alarm-description "Alert when response time is high" \
            --metric-name "TargetResponseTime" \
            --namespace "AWS/ApplicationELB" \
            --statistic "Average" \
            --period 300 \
            --threshold 3 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 2 \
            --dimensions "Name=LoadBalancer,Value=$alb_name" \
            --alarm-actions "$topic_arn" \
            --region "$AWS_REGION"

        success "Created alarm: AEIMS-High-Response-Time"
    fi

    # ECS Service CPU
    for service in "aeims-core" "aeims-app" "aeims-lib"; do
        aws cloudwatch put-metric-alarm \
            --alarm-name "AEIMS-$service-High-CPU" \
            --alarm-description "Alert when $service CPU is high" \
            --metric-name "CPUUtilization" \
            --namespace "AWS/ECS" \
            --statistic "Average" \
            --period 300 \
            --threshold 80 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 2 \
            --dimensions "Name=ServiceName,Value=$service" "Name=ClusterName,Value=aeims-cluster" \
            --alarm-actions "$topic_arn" \
            --region "$AWS_REGION" 2>/dev/null || true

        success "Created alarm: AEIMS-$service-High-CPU"
    done
}

###############################################################################
# Setup Health Check Script
###############################################################################

setup_health_check_script() {
    log "Creating health check script..."

    cat > /tmp/aeims-health-check.sh << 'HEALTHSCRIPT'
#!/bin/bash

SITES=(
    "flirts.nyc"
    "nycflirts.com"
    "fantasyflirts.live"
    "holyflirts.com"
)
ALERT_EMAIL="coleman.ryan@gmail.com"
LOG_FILE="/var/log/aeims-health-check.log"

check_site() {
    local site=$1
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$site" 2>/dev/null || echo "000")

    if [ "$http_code" != "200" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $site returned HTTP $http_code" >> "$LOG_FILE"

        # Send alert email
        echo "ALERT: $site is returning HTTP $http_code

Site: https://$site
Time: $(date '+%Y-%m-%d %H:%M:%S')
Status Code: $http_code

This is an automated alert from the AEIMS monitoring system.

To investigate:
1. Check application logs
2. Verify database connectivity
3. Review recent deployments
4. Run emergency restore: /Users/ryan/development/aeims-control/scripts/emergency-site-restore.sh

Playbook: /Users/ryan/development/SITE-RESTORATION-PLAYBOOK.md
" | mail -s "AEIMS ALERT: $site DOWN (HTTP $http_code)" "$ALERT_EMAIL"

        return 1
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OK: $site (HTTP $http_code)" >> "$LOG_FILE"
        return 0
    fi
}

# Check all sites
failed_sites=0
for site in "${SITES[@]}"; do
    check_site "$site" || ((failed_sites++))
done

# Exit with error if any site failed
exit $failed_sites
HEALTHSCRIPT

    success "Health check script created at /tmp/aeims-health-check.sh"
}

###############################################################################
# Setup Cron Job
###############################################################################

setup_cron() {
    log "Setting up cron job for health checks..."

    # This should be run on the monitoring server or locally
    echo "*/5 * * * * /usr/local/bin/aeims-health-check.sh" > /tmp/aeims-cron

    success "Cron job configuration created at /tmp/aeims-cron"
    log "To install: sudo crontab /tmp/aeims-cron"
}

###############################################################################
# Setup Uptime Robot (via API)
###############################################################################

setup_uptime_robot() {
    log "Uptime Robot setup instructions:"
    echo "
1. Go to https://uptimerobot.com
2. Create monitors for each site:
   - flirts.nyc
   - nycflirts.com
   - fantasyflirts.live
   - holyflirts.com

3. Configure:
   - Monitor Type: HTTPS
   - Monitoring Interval: 5 minutes
   - Alert Contacts: coleman.ryan@gmail.com

4. Set up alert when down for 2 checks (10 minutes)
"
}

###############################################################################
# Create Monitoring Dashboard
###############################################################################

create_dashboard() {
    log "Creating CloudWatch dashboard..."

    dashboard_body=$(cat <<'DASH'
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/ApplicationELB", "TargetResponseTime", { "stat": "Average" } ],
                    [ ".", "HTTPCode_Target_5XX_Count", { "stat": "Sum" } ],
                    [ ".", "HTTPCode_Target_4XX_Count", { "stat": "Sum" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "AEIMS ALB Health",
                "yAxis": {
                    "left": {
                        "label": "Count/Time"
                    }
                }
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/ECS", "CPUUtilization", { "stat": "Average" } ],
                    [ ".", "MemoryUtilization", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "AEIMS ECS Resources"
            }
        }
    ]
}
DASH
)

    aws cloudwatch put-dashboard \
        --dashboard-name "AEIMS-Overview" \
        --dashboard-body "$dashboard_body" \
        --region "$AWS_REGION" 2>/dev/null || true

    success "CloudWatch dashboard created: AEIMS-Overview"
}

###############################################################################
# Main Setup
###############################################################################

main() {
    log "========================================="
    log "AEIMS Monitoring Setup"
    log "========================================="

    # Setup SNS
    topic_arn=$(setup_sns)

    # Setup CloudWatch Alarms
    setup_cloudwatch_alarms "$topic_arn"

    # Setup Health Check Script
    setup_health_check_script

    # Setup Cron
    setup_cron

    # Create Dashboard
    create_dashboard

    # Uptime Robot Instructions
    setup_uptime_robot

    success "========================================="
    success "Monitoring Setup Complete"
    success "========================================="
    echo ""
    echo "Next Steps:"
    echo "1. Check email for SNS subscription confirmation"
    echo "2. Install health check script:"
    echo "   sudo cp /tmp/aeims-health-check.sh /usr/local/bin/"
    echo "   sudo chmod +x /usr/local/bin/aeims-health-check.sh"
    echo "3. Install cron job:"
    echo "   sudo crontab /tmp/aeims-cron"
    echo "4. Setup Uptime Robot monitors (see instructions above)"
    echo "5. View CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=AEIMS-Overview"
}

main "$@"
