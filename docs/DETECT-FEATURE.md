# AEIMS Control Plane - Service Detection Feature

## Overview

The `detect` command discovers running services that are not yet enrolled in the AEIMS control plane registry. This is essential for:

- 🔍 **Auditing** - Find orphaned or forgotten services
- ☁️ **Cloud Discovery** - Detect AWS ECS services running in production
- 🐳 **Local Discovery** - Find all Docker containers on your machine
- 📋 **Inventory Management** - Maintain accurate service registry
- 🔒 **Security** - Identify unauthorized services

## Usage

### Basic Detection (Local Only)

```bash
aeims-ctl detect
```

Scans local Docker containers and reports:
- Container name, image, and status
- Port mappings
- Whether it's enrolled in the registry
- Enrollment suggestions

### AWS ECS Detection

```bash
aeims-ctl detect --aws
```

Scans AWS ECS infrastructure and reports:
- ECS services in all clusters
- Running tasks
- Service status and counts
- Enrollment status

### Comprehensive Detection

```bash
aeims-ctl detect --all
```

Scans both local and AWS environments for complete visibility.

### JSON Output

```bash
aeims-ctl detect --json
aeims-ctl detect --aws --json
aeims-ctl detect --all --json
```

Returns machine-readable JSON for automation and scripting.

## Detection Modes

| Command | Scope | Description |
|---------|-------|-------------|
| `aeims-ctl detect` | Local | Scans local Docker containers (default) |
| `aeims-ctl detect --local` | Local | Explicitly scan local containers |
| `aeims-ctl detect --aws` | Cloud | Scans AWS ECS clusters, services, and tasks |
| `aeims-ctl detect --all` | Both | Scans local + AWS |

## What Gets Detected?

### Local Docker Containers

The detect command finds:
- ✅ All running Docker containers
- ✅ Container ID, name, and image
- ✅ Port mappings (host:container)
- ✅ Container status and uptime
- ✅ Enrollment status (registered vs unregistered)

**Detection Logic:**
- Checks if container name includes any registered service name
- Checks if container name contains "aeims"
- Flags containers as enrolled/unregistered

### AWS ECS Services

The detect command discovers:
- ✅ All ECS clusters in your AWS account
- ✅ Services running in each cluster
- ✅ Service status (ACTIVE, DRAINING, INACTIVE)
- ✅ Desired vs running task counts
- ✅ Task definitions
- ✅ Individual running tasks

**AWS Resources Scanned:**
- ECS Clusters: `aws ecs list-clusters`
- ECS Services: `aws ecs list-services`
- Service Details: `aws ecs describe-services`
- Running Tasks: `aws ecs list-tasks`
- Task Details: `aws ecs describe-tasks`

## Example Output

### Local Detection

```bash
$ aeims-ctl detect

Service Detection Results

Summary:
  Total services found: 4
  Enrolled: 4
  Unregistered: 0

Local Docker Containers (4):

Container                 Enrolled     Ports                Status
──────────────────────────────────────────────────────────────────────────────
aeims-web-1               ✓ Yes       8080,8080            Up 16 hours
aeims-postgres            ✓ Yes       5432,5432            Up 16 hours (healthy)
admin-service-1           ✓ Yes       8000,8000            Up 3 days
id-verify-service-1       ✓ Yes       8001,8001            Up 3 days
```

### AWS Detection

```bash
$ aeims-ctl detect --aws

Service Detection Results

Summary:
  Total services found: 8
  Enrolled: 3
  Unregistered: 5

AWS ECS Services (8):

Service                        Enrolled     Cluster                   Status
──────────────────────────────────────────────────────────────────────────────────
aeims-production               ✓ Yes       aeims-cluster             ACTIVE
nginx-service                  ✗ No        aeims-cluster             ACTIVE
admin-api                      ✗ No        aeims-cluster             ACTIVE
task-aeims-core                ✗ No        aeims-cluster             RUNNING
task-aeims-worker              ✗ No        aeims-cluster             RUNNING

💡 Tip: Enroll unregistered services with:
    aeims-ctl enroll <container-name>
```

### JSON Output

```bash
$ aeims-ctl detect --json
{
  "local": [
    {
      "id": "a1b2c3d4e5f6",
      "name": "aeims-web-1",
      "image": "aeims/web:latest",
      "ports": [
        { "host": "8080", "container": "80" }
      ],
      "status": "Up 16 hours",
      "enrolled": true,
      "source": "local"
    }
  ],
  "aws": [],
  "summary": {
    "total": 4,
    "enrolled": 4,
    "unregistered": 0
  }
}
```

## Service Enrollment

After detecting unregistered services, you can enroll them:

```bash
aeims-ctl enroll <container-name>
```

This generates a configuration snippet to add to the service registry.

### Example Enrollment

```bash
$ aeims-ctl enroll my-custom-service

Service Enrollment Configuration

Add the following to this.serviceRegistry in aeims-ctl:

'my-custom-service': {
  "name": "my-custom-service",
  "repo": "discovered",
  "compose": "docker-compose.yml",
  "type": "discovered",
  "port": 8080,
  "healthEndpoint": "http://localhost:8080/health"
}

✓ Configuration generated. Manual enrollment required.
```

Then manually edit `/Users/ryan/development/aeims-control/bin/aeims-ctl` and add the service to the registry.

## Use Cases

### 1. Security Audit

Find unauthorized containers running on your system:

```bash
aeims-ctl detect --json | jq '.local[] | select(.enrolled == false)'
```

### 2. Cloud Infrastructure Audit

Discover all AWS ECS services:

```bash
aeims-ctl detect --aws --json > aws-services.json
```

### 3. Automated Monitoring

Check for rogue containers in a cron job:

```bash
#!/bin/bash
UNREGISTERED=$(aeims-ctl detect --json | jq '.summary.unregistered')
if [ "$UNREGISTERED" -gt 0 ]; then
  echo "⚠️ Found $UNREGISTERED unregistered services!"
  aeims-ctl detect
fi
```

### 4. Service Discovery Script

Auto-discover and list all services:

```bash
#!/bin/bash
echo "Scanning for services..."
aeims-ctl detect --all --json > detected-services.json

# Extract unregistered services
jq '.local[] | select(.enrolled == false) | .name' detected-services.json

# AWS unregistered
jq '.aws[] | select(.enrolled == false) | .name' detected-services.json
```

### 5. Compliance Reporting

Generate a report of all running services:

```bash
aeims-ctl detect --all --json | \
  jq '{
    date: now | strftime("%Y-%m-%d"),
    total: .summary.total,
    enrolled: .summary.enrolled,
    unregistered: .summary.unregistered,
    local_containers: [.local[].name],
    aws_services: [.aws[].name]
  }' > compliance-report.json
```

## AWS Configuration

### Prerequisites

1. **AWS CLI installed**
   ```bash
   aws --version
   ```

2. **AWS credentials configured**
   ```bash
   aws configure
   ```

3. **Required IAM permissions:**
   - `ecs:ListClusters`
   - `ecs:ListServices`
   - `ecs:DescribeServices`
   - `ecs:ListTasks`
   - `ecs:DescribeTasks`

### IAM Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:ListClusters",
        "ecs:ListServices",
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:DescribeTasks"
      ],
      "Resource": "*"
    }
  ]
}
```

### AWS Region

The detect command uses your default AWS region from:
- `AWS_REGION` environment variable
- `AWS_DEFAULT_REGION` environment variable
- `~/.aws/config` default region

To scan a specific region:

```bash
AWS_REGION=us-west-2 aeims-ctl detect --aws
```

## Detection Algorithm

### Local Container Detection

1. Execute `docker ps` to get all running containers
2. Parse container ID, name, image, ports, status
3. Extract port mappings from Docker format
4. Check if container name matches any registered service
5. Check if container name contains "aeims"
6. Flag as enrolled/unregistered

### AWS ECS Detection

1. Check if AWS CLI is available
2. List all ECS clusters in the account
3. For each cluster:
   - List all services
   - Describe service details (status, counts, task definition)
   - List running tasks
   - Describe task details
4. Check if service name is in the registry
5. Flag as enrolled/unregistered

## Limitations

### Local Detection

- ✅ Works with Docker only (not Podman or containerd directly)
- ✅ Requires Docker daemon running
- ✅ Only detects running containers (not stopped)
- ⚠️ May have false positives on enrollment detection

### AWS Detection

- ✅ Requires AWS CLI installed
- ✅ Requires AWS credentials configured
- ✅ Requires IAM permissions for ECS read access
- ⚠️ Only scans default region (unless overridden)
- ⚠️ May timeout with large numbers of clusters/services
- ⚠️ Does not scan EC2 instances directly

## Troubleshooting

### "Docker not found"

**Problem:** Docker CLI not in PATH
**Solution:**
```bash
which docker
export PATH="/usr/local/bin:$PATH"
```

### "AWS CLI not found"

**Problem:** AWS CLI not installed
**Solution:**
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### "No ECS clusters found"

**Problem:** No ECS infrastructure in AWS account/region
**Solution:**
- Check correct AWS credentials: `aws sts get-caller-identity`
- Check correct region: `aws configure get region`
- Try different region: `AWS_REGION=us-east-1 aeims-ctl detect --aws`

### "Access Denied" errors

**Problem:** IAM permissions insufficient
**Solution:** Add required ECS read permissions to your IAM user/role

### Verbose Mode

Use `--verbose` to see detailed error messages:

```bash
aeims-ctl detect --aws --verbose
```

## Integration Examples

### CI/CD Pipeline

```yaml
# .github/workflows/audit.yml
name: Service Audit
on:
  schedule:
    - cron: '0 0 * * *'  # Daily

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - name: Detect Services
        run: |
          aeims-ctl detect --all --json > audit.json

      - name: Check for Unregistered
        run: |
          UNREG=$(jq '.summary.unregistered' audit.json)
          if [ "$UNREG" -gt 0 ]; then
            echo "::error::Found $UNREG unregistered services"
            exit 1
          fi
```

### Monitoring Script

```bash
#!/bin/bash
# monitor-services.sh

SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Run detection
RESULT=$(aeims-ctl detect --all --json)
UNREG=$(echo "$RESULT" | jq '.summary.unregistered')

if [ "$UNREG" -gt 0 ]; then
  MESSAGE="⚠️ Found $UNREG unregistered services in AEIMS"
  curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"$MESSAGE\"}" \
    "$SLACK_WEBHOOK"
fi
```

### Automatic Enrollment

```bash
#!/bin/bash
# auto-enroll.sh

# Detect all services
aeims-ctl detect --json > detected.json

# Get unregistered local containers
UNREG=$(jq -r '.local[] | select(.enrolled == false) | .name' detected.json)

for container in $UNREG; do
  echo "Enrolling $container..."
  aeims-ctl enroll "$container" --json >> enrollments.json
done

echo "Enrollment configurations saved to enrollments.json"
echo "Manually add these to aeims-ctl service registry"
```

## Future Enhancements

Planned features:

- [ ] Auto-enrollment (add services to registry automatically)
- [ ] Persistent enrollment database
- [ ] Multi-region AWS scanning
- [ ] EC2 instance detection
- [ ] Kubernetes pod detection
- [ ] Docker Swarm service detection
- [ ] Azure Container Instances support
- [ ] Google Cloud Run support
- [ ] Service dependency detection
- [ ] Anomaly detection (unexpected services)

## Related Commands

- `aeims-ctl list` - View enrolled services
- `aeims-ctl status` - Check status of enrolled services
- `aeims-ctl ps` - Show running Docker containers
- `aeims-ctl enroll <name>` - Enroll a discovered service

## Best Practices

1. **Run detection regularly** - Schedule weekly audits
2. **Investigate unregistered services** - Verify they should be running
3. **Keep registry updated** - Enroll legitimate services
4. **Monitor for changes** - Track service drift over time
5. **Document discovered services** - Maintain inventory
6. **Secure AWS credentials** - Use IAM roles when possible
7. **Limit AWS permissions** - Only grant necessary ECS read access

## Support

For issues or questions about the detect feature:
- GitHub: https://github.com/afterdarksystems/aeims/issues
- Documentation: [CONTROL-PLANE.md](./CONTROL-PLANE.md)
- Email: coleman.ryan@gmail.com
