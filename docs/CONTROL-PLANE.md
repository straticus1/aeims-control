# AEIMS Control Plane

## Overview

The AEIMS Control Plane (`aeims-ctl`) is a unified command-line interface for managing all AEIMS services across multiple repositories and deployment environments. It provides a single point of control for the entire AEIMS infrastructure.

## Features

✅ **Unified Service Management** - Control all services from a single CLI
✅ **Multi-Repository Support** - Manages services across aeims, aeims-control, aeims-asterisk, and aeimsLib
✅ **JSON Output** - Machine-readable output with `--json` flag
✅ **Health Monitoring** - Built-in health check capabilities
✅ **Log Streaming** - Easy access to service logs with follow support
✅ **Colorized Output** - Beautiful, readable terminal output
✅ **Docker Compose Integration** - Seamless integration with existing docker-compose files

## Installation

### 1. Make the CLI executable

```bash
chmod +x ~/development/aeims-control/bin/aeims-ctl
```

### 2. Add to PATH (optional but recommended)

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/development/aeims-control/bin:$PATH"
```

Then reload your shell:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

### 3. Verify installation

```bash
aeims-ctl --help
```

## Usage

### Basic Commands

#### List all services
```bash
aeims-ctl list
```

Output:
```
AEIMS Service Registry

Total services: 18

aeims-control (9 services)
  ● redis                     [database:6379]
  ● postgres                  [database:5432]
  ● mysql                     [database:3306]
  ● aeims-lib                 [websocket:3000]
  ● aeims-core                [api:8000]
  ...
```

#### Check status of all services
```bash
aeims-ctl status
```

#### Check status of a specific service
```bash
aeims-ctl status redis
aeims-ctl status aeims-core
```

#### Start services
```bash
# Start a specific service
aeims-ctl start redis

# Start all services
aeims-ctl start all
```

#### Stop services
```bash
# Stop a specific service
aeims-ctl stop redis

# Stop all services
aeims-ctl stop all
```

#### Restart services
```bash
# Restart a specific service
aeims-ctl restart aeims-core

# Restart all services
aeims-ctl restart all
```

#### View logs
```bash
# View logs (last 100 lines)
aeims-ctl logs aeims-core

# Follow logs in real-time
aeims-ctl logs aeims-core --follow
aeims-ctl logs aeims-lib -f
```

#### Check health endpoints
```bash
# Check all health endpoints
aeims-ctl health

# Check specific service health
aeims-ctl health aeims-core
```

#### Show running containers
```bash
aeims-ctl ps
```

#### Detect unregistered services
```bash
# Scan local Docker containers
aeims-ctl detect

# Scan AWS ECS services
aeims-ctl detect --aws

# Scan both local and AWS
aeims-ctl detect --all

# Get JSON output
aeims-ctl detect --all --json
```

#### Enroll discovered service
```bash
# Generate enrollment configuration
aeims-ctl enroll <container-name>

# Example
aeims-ctl enroll my-custom-api
```

### Global Flags

#### `--json` - JSON output
```bash
aeims-ctl status --json
aeims-ctl list --json
aeims-ctl health --json
```

Example JSON output:
```json
{
  "redis": {
    "status": "running",
    "health": "healthy",
    "ports": 6379,
    "type": "database",
    "repo": "aeims-control"
  },
  "aeims-core": {
    "status": "running",
    "health": "healthy",
    "ports": 8000,
    "type": "api",
    "repo": "aeims-control"
  }
}
```

#### `--verbose` / `-v` - Verbose output
```bash
aeims-ctl start redis --verbose
aeims-ctl restart all -v
```

Shows the actual docker-compose commands being executed.

#### `--follow` / `-f` - Follow logs
```bash
aeims-ctl logs aeims-core --follow
aeims-ctl logs nginx -f
```

#### `--help` / `-h` - Show help
```bash
aeims-ctl --help
aeims-ctl -h
```

## Service Registry

The control plane manages services across three repositories:

### aeims-control (9 services)
- **redis** - Redis cache & session store (port 6379)
- **postgres** - PostgreSQL primary database (port 5432)
- **mysql** - MySQL legacy database (port 3306)
- **aeims-lib** - WebSocket & device control server (port 3000)
- **aeims-core** - Core API server (port 8000)
- **aeims-admin** - Admin interface (port 8001)
- **aeims-app** - React frontend application (port 3001)
- **nginx** - Reverse proxy & load balancer (port 80)
- **health-monitor** - Health monitoring service

### aeims (3 services)
- **admin-service** - Customer auth & site management (port 8000)
- **id-verify-service** - Operator legal compliance (port 8001)
- **aeims-web** - Main AEIMS web application (port 8080)

### aeims/telephony-platform (6 services)
- **user-service** - User management API (port 8001)
- **billing-service** - Billing & payment API (port 8002)
- **call-service** - Call handling API (port 8003)
- **operator-service** - Operator management API (port 8004)
- **conference-service** - Conference calling API (port 8005)
- **notification-service** - Notification API (port 8006)

## Architecture

### How it works

1. **Service Registry** - Maintains a mapping of all services to their:
   - Repository location
   - Docker Compose file
   - Port number
   - Health endpoint
   - Service type

2. **Docker Compose Integration** - Executes docker-compose commands in the correct repository context

3. **Multi-Repo Awareness** - Intelligently groups services by repository for efficient batch operations

4. **Health Monitoring** - Checks HTTP health endpoints to verify service health

### Directory Structure

```
~/development/
├── aeims-control/
│   ├── bin/
│   │   └── aeims-ctl              # Main CLI script
│   ├── docker-compose-production.yml
│   └── ...
├── aeims/
│   ├── docker-compose.yml
│   └── telephony-platform/
│       └── docker-compose.yml
├── aeims-asterisk/
└── aeimsLib/
```

## Common Workflows

### Development Workflow

```bash
# Start core services
aeims-ctl start redis
aeims-ctl start postgres
aeims-ctl start mysql

# Check they're running
aeims-ctl status

# Start application services
aeims-ctl start aeims-core
aeims-ctl start aeims-lib

# Follow logs while developing
aeims-ctl logs aeims-core -f

# Restart after changes
aeims-ctl restart aeims-core
```

### Production Deployment

```bash
# Check current status
aeims-ctl status

# Start all services
aeims-ctl start all

# Verify health
aeims-ctl health

# Monitor logs
aeims-ctl logs nginx -f
```

### Troubleshooting

```bash
# Check which containers are running
aeims-ctl ps

# Get detailed status
aeims-ctl status --verbose

# Check health endpoints
aeims-ctl health

# View error logs
aeims-ctl logs aeims-core | grep ERROR

# Restart problematic service
aeims-ctl restart aeims-core

# Full system restart
aeims-ctl restart all
```

### Monitoring

```bash
# Continuous health monitoring
watch -n 5 'aeims-ctl health'

# Status dashboard
watch -n 2 'aeims-ctl status'

# JSON output for scripting
aeims-ctl status --json | jq '.[] | select(.status != "running")'
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Check service status
  run: |
    ~/development/aeims-control/bin/aeims-ctl status --json > status.json

- name: Start services
  run: |
    ~/development/aeims-control/bin/aeims-ctl start all

- name: Health check
  run: |
    ~/development/aeims-control/bin/aeims-ctl health --json
```

### Bash Scripting Example

```bash
#!/bin/bash

# Get service status as JSON
STATUS=$(aeims-ctl status --json)

# Check if aeims-core is running
CORE_STATUS=$(echo "$STATUS" | jq -r '.["aeims-core"].status')

if [ "$CORE_STATUS" != "running" ]; then
  echo "aeims-core is not running, starting..."
  aeims-ctl start aeims-core
fi

# Check health
HEALTH=$(aeims-ctl health --json)
CORE_HEALTH=$(echo "$HEALTH" | jq -r '.["aeims-core"].healthy')

if [ "$CORE_HEALTH" != "true" ]; then
  echo "aeims-core is unhealthy!"
  exit 1
fi
```

## Advanced Usage

### Service Dependencies

Start services in dependency order:

```bash
# 1. Start databases first
aeims-ctl start redis
aeims-ctl start postgres
aeims-ctl start mysql

# 2. Wait for them to be healthy
sleep 5

# 3. Start backend services
aeims-ctl start aeims-core
aeims-ctl start aeims-lib

# 4. Start frontend services
aeims-ctl start aeims-app
aeims-ctl start nginx
```

### Custom Health Checks

The control plane checks these health endpoints:

| Service | Health Endpoint |
|---------|----------------|
| aeims-lib | http://localhost:3000/health |
| aeims-core | http://localhost:8000/health |
| aeims-admin | http://localhost:8001/health.php |
| aeims-app | http://localhost:3001/ |
| nginx | http://localhost:8080/health |
| admin-service | http://localhost:8000/health |
| id-verify-service | http://localhost:8001/health |
| All microservices | http://localhost:{port}/health |

### Port Reference

Quick reference for all service ports:

```bash
# Databases
Redis:     6379
PostgreSQL: 5432
MySQL:     3306

# Core Services
aeims-lib:  3000 (WebSocket)
aeims-core: 8000 (API)
aeims-admin: 8001 (Web)
aeims-app:  3001 (Frontend)
nginx:      80 (HTTP), 443 (HTTPS)

# Microservices
user-service:     8001
billing-service:  8002
call-service:     8003
operator-service: 8004
conference-service: 8005
notification-service: 8006
```

## Troubleshooting

### Common Issues

#### 1. "Service not found" error

**Problem:** Service name not in registry
**Solution:** Check available services with `aeims-ctl list`

#### 2. "Docker compose file not found"

**Problem:** Repository not in expected location
**Solution:** Ensure all repos are in `~/development/`

#### 3. Health check fails

**Problem:** Service running but not responding
**Solution:**
```bash
# Check container logs
aeims-ctl logs <service>

# Restart the service
aeims-ctl restart <service>
```

#### 4. Permission denied

**Problem:** Script not executable
**Solution:**
```bash
chmod +x ~/development/aeims-control/bin/aeims-ctl
```

### Debug Mode

Use verbose mode to see what's happening:

```bash
aeims-ctl start redis --verbose
aeims-ctl status --verbose
```

This shows the actual docker-compose commands being executed.

## Future Enhancements

Planned features:

- [ ] Service dependency graph visualization
- [ ] Automated rollback on failed deployments
- [ ] Prometheus metrics integration
- [ ] Slack/email notifications for service failures
- [ ] Auto-scaling support
- [ ] Blue-green deployment support
- [ ] Integration with Kubernetes
- [ ] Service performance metrics
- [ ] Log aggregation and search
- [ ] Configuration management

## Contributing

To add a new service to the registry:

1. Edit `/Users/ryan/development/aeims-control/bin/aeims-ctl`
2. Add entry to `this.serviceRegistry` object:

```javascript
'my-service': {
  repo: 'aeims-control',              // Repository name
  compose: 'docker-compose.yml',       // Compose file
  type: 'api',                         // Service type
  port: 8080,                          // Port number
  healthEndpoint: 'http://localhost:8080/health'  // Health check URL
}
```

3. Test the new service:
```bash
aeims-ctl list
aeims-ctl status my-service
```

## Support

For issues or questions:
- GitHub: https://github.com/afterdarksystems/aeims
- Email: coleman.ryan@gmail.com

## License

Copyright © 2024 AfterDark Systems. All rights reserved.
