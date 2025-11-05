#!/bin/bash

###############################################################################
# AEIMS Emergency Site Restoration Script
# Quickly diagnose and fix common issues causing site downtime
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SITES=("flirts.nyc" "nycflirts.com")
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_IPS=("3.232.106.161" "34.235.56.81")

# Logging
LOG_FILE="logs/emergency-restore-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

###############################################################################
# STEP 1: Diagnose Issues
###############################################################################

diagnose() {
    log "=== DIAGNOSTIC PHASE ==="

    local issues=0

    # Check DNS resolution
    log "Checking DNS resolution..."
    for site in "${SITES[@]}"; do
        if dig +short "$site" | grep -q "[0-9]"; then
            success "DNS OK: $site"
        else
            error "DNS FAILED: $site"
            ((issues++))
        fi
    done

    # Check HTTP response
    log "Checking HTTP responses..."
    for site in "${SITES[@]}"; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$site" || echo "000")
        if [ "$http_code" = "200" ]; then
            success "HTTP OK: $site (200)"
        elif [ "$http_code" = "503" ]; then
            warning "HTTP 503: $site (Service Unavailable)"
            ((issues++))
        else
            error "HTTP ERROR: $site ($http_code)"
            ((issues++))
        fi
    done

    # Check EC2 instances
    log "Checking EC2 instance status..."
    for ip in "${INSTANCE_IPS[@]}"; do
        instance_id=$(aws ec2 describe-instances \
            --filters "Name=ip-address,Values=$ip" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text 2>/dev/null || echo "")

        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            state=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text 2>/dev/null || echo "unknown")

            if [ "$state" = "running" ]; then
                success "EC2 RUNNING: $ip ($instance_id)"
            else
                error "EC2 NOT RUNNING: $ip ($instance_id) - State: $state"
                ((issues++))
            fi
        else
            warning "Cannot find EC2 instance for IP: $ip"
        fi
    done

    # Check SSH connectivity
    log "Checking SSH connectivity..."
    for ip in "${INSTANCE_IPS[@]}"; do
        if nc -z -w 5 "$ip" 22 2>/dev/null; then
            success "SSH PORT OPEN: $ip"
        else
            error "SSH PORT CLOSED: $ip"
            ((issues++))
        fi
    done

    log "=== DIAGNOSIS COMPLETE: $issues issues found ==="
    return $issues
}

###############################################################################
# STEP 2: Fix EC2 Instances
###############################################################################

fix_ec2_instances() {
    log "=== FIXING EC2 INSTANCES ==="

    for ip in "${INSTANCE_IPS[@]}"; do
        instance_id=$(aws ec2 describe-instances \
            --filters "Name=ip-address,Values=$ip" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text 2>/dev/null || echo "")

        if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
            warning "Cannot find instance for $ip - skipping"
            continue
        fi

        state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")

        if [ "$state" != "running" ]; then
            log "Starting instance $instance_id..."
            aws ec2 start-instances --instance-ids "$instance_id"

            log "Waiting for instance to start..."
            aws ec2 wait instance-running --instance-ids "$instance_id"

            success "Instance $instance_id started"

            # Wait additional time for services to initialize
            log "Waiting 60 seconds for services to initialize..."
            sleep 60
        fi
    done
}

###############################################################################
# STEP 3: Fix via SSH
###############################################################################

fix_via_ssh() {
    local ip=$1
    log "=== FIXING VIA SSH: $ip ==="

    # Create remote fix script
    cat > /tmp/aeims-remote-fix.sh << 'REMOTESCRIPT'
#!/bin/bash
set -e

echo "=== Starting AEIMS Emergency Fix ==="

# Restart services
echo "Restarting services..."
sudo systemctl restart postgresql || true
sudo systemctl restart apache2 || true
sudo systemctl restart nginx || true
sudo systemctl restart php8.1-fpm || true

# Fix permissions
echo "Fixing permissions..."
sudo chown -R www-data:www-data /var/www/aeims || true
sudo chmod -R 755 /var/www/aeims || true
sudo chmod -R 775 /var/www/aeims/data || true
sudo chmod -R 775 /var/www/aeims/logs || true

# Install dependencies if needed
if [ ! -d "/var/www/aeims/vendor" ]; then
    echo "Installing composer dependencies..."
    cd /var/www/aeims
    composer install --no-dev --optimize-autoloader || true
fi

# Create sites.json if missing
if [ ! -f "/var/www/aeims/data/sites.json" ]; then
    echo "Creating sites.json..."
    sudo mkdir -p /var/www/aeims/data
    cat > /tmp/sites.json << 'SITESEOF'
{
    "sites": {
        "flirts_nyc": {
            "site_id": "flirts_nyc",
            "domain": "flirts.nyc",
            "name": "Flirts NYC",
            "active": true,
            "created_at": "'$(date '+%Y-%m-%d %H:%M:%S')'"
        },
        "nycflirts_com": {
            "site_id": "nycflirts_com",
            "domain": "nycflirts.com",
            "name": "NYC Flirts",
            "active": true,
            "created_at": "'$(date '+%Y-%m-%d %H:%M:%S')'"
        }
    },
    "last_updated": "'$(date '+%Y-%m-%d %H:%M:%S')'"
}
SITESEOF
    sudo mv /tmp/sites.json /var/www/aeims/data/sites.json
    sudo chown www-data:www-data /var/www/aeims/data/sites.json
fi

# Test local connectivity
echo "Testing local site..."
curl -I http://localhost/ || echo "WARNING: Local test failed"

echo "=== Fix complete ==="
REMOTESCRIPT

    # Copy and execute script
    if scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no /tmp/aeims-remote-fix.sh "ubuntu@$ip:/tmp/" 2>/dev/null; then
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ubuntu@$ip" "bash /tmp/aeims-remote-fix.sh" 2>&1 | tee -a "$LOG_FILE"; then
            success "Remote fix completed on $ip"
            return 0
        else
            error "Remote fix failed on $ip"
            return 1
        fi
    else
        error "Cannot connect via SSH to $ip"
        return 1
    fi
}

###############################################################################
# STEP 4: Fix via AWS Systems Manager
###############################################################################

fix_via_ssm() {
    local ip=$1
    log "=== FIXING VIA SSM: $ip ==="

    instance_id=$(aws ec2 describe-instances \
        --filters "Name=ip-address,Values=$ip" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "")

    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        error "Cannot find instance for $ip"
        return 1
    fi

    log "Sending SSM command to $instance_id..."

    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=[
            "sudo systemctl restart postgresql apache2 nginx php8.1-fpm",
            "sudo chown -R www-data:www-data /var/www/aeims",
            "cd /var/www/aeims && composer install --no-dev --optimize-autoloader",
            "curl -I http://localhost/"
        ]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$command_id" ]; then
        log "Waiting for SSM command to complete..."
        sleep 10

        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Failed")

        if [ "$status" = "Success" ]; then
            success "SSM fix completed on $instance_id"
            return 0
        else
            error "SSM fix failed on $instance_id: $status"
            return 1
        fi
    else
        error "Failed to send SSM command"
        return 1
    fi
}

###############################################################################
# STEP 5: Verify Recovery
###############################################################################

verify_recovery() {
    log "=== VERIFYING RECOVERY ==="

    local failures=0

    for site in "${SITES[@]}"; do
        log "Testing $site..."

        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$site" || echo "000")

        if [ "$http_code" = "200" ]; then
            success "$site is UP (HTTP 200)"
        else
            error "$site is DOWN (HTTP $http_code)"
            ((failures++))
        fi
    done

    if [ $failures -eq 0 ]; then
        success "=== ALL SITES RESTORED ==="
        return 0
    else
        error "=== $failures SITES STILL DOWN ==="
        return 1
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    log "========================================="
    log "AEIMS Emergency Site Restoration"
    log "Started: $(date)"
    log "========================================="

    # Phase 1: Diagnose
    if diagnose; then
        success "No issues found - sites are healthy"
        exit 0
    fi

    # Phase 2: Fix EC2 instances
    fix_ec2_instances

    # Phase 3: Try SSH fix first
    for ip in "${INSTANCE_IPS[@]}"; do
        if fix_via_ssh "$ip"; then
            log "SSH fix succeeded for $ip"
        else
            warning "SSH fix failed for $ip, trying SSM..."
            fix_via_ssm "$ip" || warning "SSM fix also failed for $ip"
        fi
    done

    # Wait for services to stabilize
    log "Waiting 30 seconds for services to stabilize..."
    sleep 30

    # Phase 4: Verify
    if verify_recovery; then
        success "========================================="
        success "RECOVERY COMPLETE"
        success "All sites are now operational"
        success "Log: $LOG_FILE"
        success "========================================="
        exit 0
    else
        error "========================================="
        error "RECOVERY FAILED"
        error "Manual intervention required"
        error "See playbook: /Users/ryan/development/SITE-RESTORATION-PLAYBOOK.md"
        error "Log: $LOG_FILE"
        error "========================================="
        exit 1
    fi
}

# Run main function
main "$@"
