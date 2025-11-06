# AEIMS Reconciliation System - User Guide

## 🎯 Overview

The AEIMS Reconciliation System provides **production-grade deployment safety** by detecting configuration drift, tracking deployment history, and enabling safe rollbacks. This system ensures that all services can be deployed safely, even when some services were deployed individually outside the control plane.

## ✨ Key Features

1. **Drift Detection** - Automatically detect when deployed services differ from desired state
2. **Manifest Tracking** - Track every deployment with full configuration history
3. **Smart Reconciliation** - Safely bring drifted services back to desired state
4. **Rollback Capability** - Instant rollback to any previous deployment
5. **Version Locking** - Pin all services to specific SHA256 digests
6. **Approval Gates** - Severity-based approval workflows
7. **Continuous Monitoring** - Real-time drift alerts via Slack/email
8. **Deployment Safety** - Pre/post-deployment verification

## 🚀 Quick Start

### Check for Drift

```bash
# Check drift for a specific service
./bin/aeims-ctl drift admin-service

# Check drift for all services
./bin/aeims-ctl drift all

# Output as JSON
./bin/aeims-ctl drift all --json
```

### Reconcile Services

```bash
# Reconcile a single service (with approval prompts)
./bin/aeims-ctl reconcile admin-service

# Dry-run to see what would happen
./bin/aeims-ctl reconcile admin-service --dry-run

# Reconcile all services automatically (CI/CD)
./bin/aeims-ctl reconcile all --auto-approve
```

### View Deployment History

```bash
# Show all deployment manifests
./bin/aeims-ctl manifest

# Show specific service manifest
./bin/aeims-ctl manifest admin-service

# View deployment history
./bin/aeims-ctl history admin-service

# View more history
./bin/aeims-ctl history admin-service --limit 20
```

### Rollback

```bash
# View deployment history to find deployment ID
./bin/aeims-ctl history admin-service

# Rollback to a specific deployment
./bin/aeims-ctl rollback admin-service admin-service-1699876543210
```

## 📊 Understanding Drift Severity

The system categorizes drift into 4 levels:

### CRITICAL ⛔
- **What**: Service not found, or major infrastructure changes
- **Action**: STOP - Manual intervention required
- **Example**: Service deleted, cluster changed

### HIGH 🔴
- **What**: Image changed, environment variables modified
- **Action**: REVIEW - Requires explicit approval
- **Example**: Hotfix applied manually, config changed in AWS console

### MEDIUM 🟡
- **What**: Scaling changes, minor config drift
- **Action**: REVIEW RECOMMENDED - Approval suggested
- **Example**: Desired count manually adjusted

### LOW 🔵
- **What**: Metadata changes, non-critical drift
- **Action**: SAFE TO PROCEED
- **Example**: Tags updated, descriptions changed

## 🔧 System Components

### 1. Manifest Tracker (`lib/manifest-tracker.js`)

Tracks every deployment with:
- Service name and version
- Docker image with SHA256 digest
- Configuration hash
- Git commit and branch
- AWS task definition ARN
- Deployment metadata (who, when, where)

**CLI Usage:**
```bash
# Initialize tracking
./lib/manifest-tracker.js init

# View current state
./lib/manifest-tracker.js current admin-service

# View deployment history
./lib/manifest-tracker.js history admin-service 10

# View all backups
./lib/manifest-tracker.js backups admin-service
```

### 2. Drift Detector (`lib/drift-detector.js`)

Compares desired state (manifests) with actual state (AWS):

**CLI Usage:**
```bash
# Check drift for a service
./lib/drift-detector.js service admin-service

# Check all services
./lib/drift-detector.js all

# Generate human-readable report
./lib/drift-detector.js report

# Check if safe to deploy (exits 1 if not)
./lib/drift-detector.js safe admin-service
```

### 3. Reconciliation Controller (`lib/reconciliation-controller.js`)

Automatically fixes drift with approval gates:

**CLI Usage:**
```bash
# Reconcile a service
./lib/reconciliation-controller.js service admin-service

# Dry-run
./lib/reconciliation-controller.js service admin-service --dry-run

# Auto-approve (CI/CD)
./lib/reconciliation-controller.js all --auto-approve

# Rollback
./lib/reconciliation-controller.js rollback admin-service admin-service-1699876543210
```

### 4. Version Lock Manager (`lib/version-lock.js`)

Pins all services to specific versions:

**CLI Usage:**
```bash
# Lock service version
./lib/version-lock.js lock admin-service 515966511618.dkr.ecr.us-east-1.amazonaws.com/admin latest

# Lock all services from docker-compose
./lib/version-lock.js lock-compose docker-compose-production.yml

# Lock all repositories
./lib/version-lock.js lock-repos ~/development

# Verify lock integrity
./lib/version-lock.js verify

# Generate lock report
./lib/version-lock.js report

# Update docker-compose with locked versions
./lib/version-lock.js update-compose docker-compose-production.yml docker-compose-locked.yml
```

### 5. Drift Monitor (`lib/drift-monitor.js`)

Continuous drift monitoring with alerts:

**CLI Usage:**
```bash
# Start monitoring daemon (5 min intervals)
./lib/drift-monitor.js start

# Check once (good for cron)
./lib/drift-monitor.js check

# View alert history
./lib/drift-monitor.js history 20

# Clear alerts
./lib/drift-monitor.js clear
```

**Environment Variables:**
```bash
# Custom check interval (1 minute)
DRIFT_CHECK_INTERVAL=60000 ./lib/drift-monitor.js start

# Slack alerts
SLACK_WEBHOOK_URL=https://hooks.slack.com/... ./lib/drift-monitor.js start

# Email alerts
ALERT_EMAIL=ops@example.com ./lib/drift-monitor.js start
```

### 6. Safe Deploy (`lib/safe-deploy.js`)

Deployment wrapper with all safety checks:

**CLI Usage:**
```bash
# Deploy with safety checks
./lib/safe-deploy.js admin-service

# Auto-approve for CI/CD
./lib/safe-deploy.js admin-service --auto-approve

# Skip drift check (not recommended)
./lib/safe-deploy.js admin-service --skip-drift-check

# Dry-run
./lib/safe-deploy.js admin-service --dry-run
```

## 📁 Directory Structure

```
aeims-control/
├── lib/
│   ├── manifest-tracker.js          # Deployment manifest tracking
│   ├── drift-detector.js            # Drift detection logic
│   ├── reconciliation-controller.js # Reconciliation orchestration
│   ├── version-lock.js              # Version pinning
│   ├── drift-monitor.js             # Continuous monitoring
│   └── safe-deploy.js               # Safe deployment wrapper
├── .aeims/
│   ├── manifests/                   # Deployment manifests
│   ├── state/                       # Current state files
│   ├── backups/                     # Pre-deployment backups
│   ├── version-lock.json            # Version lock file
│   └── drift-alerts.json            # Drift alert history
└── bin/
    └── aeims-ctl                    # Enhanced CLI with reconcile commands
```

## 🎬 Common Workflows

### Scenario 1: Deploy After Manual Hotfix

Someone manually scaled up `admin-service` during an incident. Now you need to deploy a new version.

```bash
# 1. Check what changed
./bin/aeims-ctl drift admin-service

# Output:
# ⚠️  MEDIUM - Detected 1 configuration drift(s)
#   desiredCount:
#     Manifest: 2
#     AWS:      5
#     Desired count changed manually: 2 → 5

# 2. Decide: Keep manual change or restore to manifest?
# Option A: Reconcile to manifest (restore to 2 instances)
./bin/aeims-ctl reconcile admin-service

# Option B: Update manifest to match current (accept 5 instances)
# Deploy with current count and update manifest
```

### Scenario 2: Rollback Failed Deployment

You deployed version 2.0 but it has bugs. Rollback to 1.9.

```bash
# 1. View deployment history
./bin/aeims-ctl history admin-service

# Output:
# 🔹 admin-service-1699876543210
#    Version: 2.0.0  (current - broken)
# 🔹 admin-service-1699876500000
#    Version: 1.9.0  (last good)

# 2. Rollback
./bin/aeims-ctl rollback admin-service admin-service-1699876500000

# System will:
# - Restore manifest to 1.9.0
# - Reconcile service to 1.9.0 configuration
# - Verify deployment succeeded
```

### Scenario 3: Detect Rogue Changes

Someone manually changed environment variables in the AWS console.

```bash
# 1. Continuous monitoring detects drift
# (If drift-monitor is running)

# 2. Receive Slack alert:
# "HIGH Drift Alert: admin-service
#  Environment variables changed: 3 drift(s)"

# 3. Investigate
./bin/aeims-ctl drift admin-service --json > drift-report.json

# 4. Reconcile or update manifest
./bin/aeims-ctl reconcile admin-service
```

### Scenario 4: Production Deployment with Safety

```bash
# 1. Pre-deployment checks
./bin/aeims-ctl drift admin-service

# 2. If drift detected, review changes

# 3. Deploy using safe wrapper
# (Integrate into deploy.sh or deploy-unified.sh)

# Manual deployment example:
./lib/safe-deploy.js admin-service

# System will:
# - Detect drift ✓
# - Ask for approval if HIGH/CRITICAL ✓
# - Create backup ✓
# - Lock version ✓
# - Execute deployment ✓
# - Create manifest ✓
# - Verify deployment ✓
# - Offer rollback if failed ✓
```

### Scenario 5: Version Locking for Release

Preparing for a production release with pinned versions.

```bash
# 1. Lock all current versions
./lib/version-lock.js lock-compose docker-compose-production.yml

# 2. Lock repository versions
./lib/version-lock.js lock-repos ~/development

# 3. Verify lock
./lib/version-lock.js verify

# 4. Generate lock report
./lib/version-lock.js report > VERSION-LOCK-REPORT.txt

# 5. Update docker-compose with digests
./lib/version-lock.js update-compose \
  docker-compose-production.yml \
  docker-compose-locked.yml

# Now docker-compose-locked.yml uses SHA256 digests:
# image: 515966511618.dkr.ecr.us-east-1.amazonaws.com/admin@sha256:abc123...
```

## 🔐 Security & Safety

### Approval Gates

The system enforces approvals based on drift severity:

| Severity | Default Behavior | Override |
|----------|-----------------|----------|
| CRITICAL | STOP - Requires explicit yes | `--auto-approve` |
| HIGH     | ASK - Defaults to no | `--auto-approve` |
| MEDIUM   | ASK - Defaults to yes | `--auto-approve` |
| LOW      | PROCEED | N/A |

### Backup Strategy

Before any destructive operation:
1. Current state saved to `.aeims/backups/`
2. Backup includes full manifest
3. Backups retained (last 50 per service)
4. Rollback uses backup to restore

### Drift Monitoring

Configure continuous monitoring:

```bash
# Create systemd service for monitoring
cat > /etc/systemd/system/aeims-drift-monitor.service <<EOF
[Unit]
Description=AEIMS Drift Monitor
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/aeims-control
Environment="DRIFT_CHECK_INTERVAL=300000"
Environment="SLACK_WEBHOOK_URL=https://hooks.slack.com/..."
ExecStart=/usr/bin/node /home/ubuntu/aeims-control/lib/drift-monitor.js start
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable aeims-drift-monitor
sudo systemctl start aeims-drift-monitor

# Check status
sudo systemctl status aeims-drift-monitor
```

## 🧪 Testing

### Test Drift Detection

```bash
# 1. Manually change a service
aws ecs update-service \
  --cluster aeims-cluster-production \
  --service admin-service \
  --desired-count 10

# 2. Detect drift
./bin/aeims-ctl drift admin-service

# 3. Reconcile
./bin/aeims-ctl reconcile admin-service
```

### Test Rollback

```bash
# 1. Deploy version 2
# (deploy normally)

# 2. Verify in history
./bin/aeims-ctl history admin-service

# 3. Rollback to version 1
./bin/aeims-ctl rollback admin-service <deployment-id>

# 4. Verify rollback
./bin/aeims-ctl manifest admin-service
```

## 🚨 Troubleshooting

### Issue: "No manifest found for service"

**Cause**: Service deployed before manifest tracking was enabled.

**Solution**:
```bash
# Create initial manifest for existing service
node -e "
const ManifestTracker = require('./lib/manifest-tracker');
const tracker = new ManifestTracker();

(async () => {
  await tracker.initialize();
  await tracker.createManifest({
    serviceName: 'admin-service',
    version: '1.0.0',
    imageName: '515966511618.dkr.ecr.us-east-1.amazonaws.com/admin',
    imageTag: 'latest',
    environment: 'production',
    config: {},
    taskDefinitionArn: 'arn:aws:ecs:...',
    desiredCount: 2
  });
})();
"
```

### Issue: "Drift detection failed"

**Cause**: AWS credentials not configured or service not found.

**Solution**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check service exists
aws ecs describe-services \
  --cluster aeims-cluster-production \
  --services admin-service
```

### Issue: "Version lock verify fails"

**Cause**: Image or commit changed since lock.

**Solution**:
```bash
# View verification details
./lib/version-lock.js verify

# Re-lock with current versions
./lib/version-lock.js lock-compose docker-compose-production.yml
```

## 📈 Best Practices

1. **Always check drift before deploying**
   ```bash
   ./bin/aeims-ctl drift <service>
   ```

2. **Use version locking for releases**
   ```bash
   ./lib/version-lock.js lock-compose docker-compose-production.yml
   ```

3. **Enable continuous monitoring in production**
   ```bash
   ./lib/drift-monitor.js start
   ```

4. **Review deployment history regularly**
   ```bash
   ./bin/aeims-ctl manifest
   ```

5. **Test rollback procedures**
   - Deploy to staging
   - Rollback to previous version
   - Verify functionality

6. **Document manual changes**
   - If you must make manual changes, document why
   - Update manifests to reflect manual changes
   - Or reconcile back to desired state

## 🎓 Advanced Usage

### Custom Drift Thresholds

Edit `lib/drift-monitor.js` to customize alert thresholds:

```javascript
const ALERT_THRESHOLD = {
  CRITICAL: 0,  // Alert immediately
  HIGH: 1,      // Alert if > 1 HIGH severity drifts
  MEDIUM: 5,    // Alert if > 5 MEDIUM severity drifts
  LOW: 10       // Alert if > 10 LOW severity drifts
};
```

### Integration with CI/CD

```yaml
# GitHub Actions example
- name: Check for drift
  run: ./bin/aeims-ctl drift all

- name: Deploy with safety
  run: ./lib/safe-deploy.js ${{ matrix.service }} --auto-approve

- name: Verify deployment
  run: ./bin/aeims-ctl drift ${{ matrix.service }}
```

### Custom Alert Handlers

```javascript
// Add custom alert handler
const DriftMonitor = require('./lib/drift-monitor');

function customAlertHandler(alertData) {
  // Send to PagerDuty, Datadog, etc.
  console.log('Custom alert:', alertData);
}

const monitor = new DriftMonitor();
monitor.alertHandlers.push(customAlertHandler);
monitor.start();
```

## 📚 API Reference

See individual module files for complete API documentation:
- `lib/manifest-tracker.js` - Lines 1-50
- `lib/drift-detector.js` - Lines 1-50
- `lib/reconciliation-controller.js` - Lines 1-50
- `lib/version-lock.js` - Lines 1-50
- `lib/drift-monitor.js` - Lines 1-50
- `lib/safe-deploy.js` - Lines 1-50

## 🤝 Support

For issues or questions:
1. Check this guide
2. Review module source code
3. Check `.aeims/` directory for state files
4. Review deployment history: `./bin/aeims-ctl history <service>`

## 🎉 Summary

You now have **enterprise-grade reconciliation** that can:
- ✅ Detect individually deployed services
- ✅ Reconcile mixed deployment states
- ✅ Identify services needing config updates
- ✅ Redeploy with safety checks
- ✅ Rollback instantly if needed
- ✅ Track full deployment history
- ✅ Monitor for drift continuously
- ✅ Lock versions with SHA256 digests

**The system is production-ready!** 🚀
