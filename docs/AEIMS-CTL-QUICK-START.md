# AEIMS Control Plane - Quick Start Guide

## Installation

```bash
# Make executable
chmod +x ~/development/aeims-control/bin/aeims-ctl

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/development/aeims-control/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

## Essential Commands

### View all services
```bash
aeims-ctl list
```

### Check service status
```bash
aeims-ctl status                # All services
aeims-ctl status redis          # Specific service
```

### Start services
```bash
aeims-ctl start all             # Start everything
aeims-ctl start redis           # Start one service
```

### Stop services
```bash
aeims-ctl stop all              # Stop everything
aeims-ctl stop redis            # Stop one service
```

### Restart services
```bash
aeims-ctl restart all           # Restart everything
aeims-ctl restart aeims-core    # Restart one service
```

### View logs
```bash
aeims-ctl logs aeims-core       # View logs
aeims-ctl logs nginx -f         # Follow logs in real-time
```

### Check health
```bash
aeims-ctl health                # Check all health endpoints
aeims-ctl health aeims-core     # Check specific service
```

### Container list
```bash
aeims-ctl ps                    # Show all running containers
```

### Detect unregistered services
```bash
aeims-ctl detect                # Scan local Docker containers
aeims-ctl detect --aws          # Scan AWS ECS services
aeims-ctl detect --all          # Scan everything
```

### Enroll discovered service
```bash
aeims-ctl enroll my-container   # Generate enrollment config
```

## JSON Output

Add `--json` to any command for machine-readable output:

```bash
aeims-ctl status --json
aeims-ctl list --json
aeims-ctl health --json
```

## Common Workflows

### Development startup
```bash
# Start databases
aeims-ctl start redis postgres mysql

# Start core services
aeims-ctl start aeims-core aeims-lib

# Check status
aeims-ctl status

# Follow logs
aeims-ctl logs aeims-core -f
```

### Production deployment
```bash
# Start all services
aeims-ctl start all

# Verify health
aeims-ctl health

# Check status
aeims-ctl status
```

### Troubleshooting
```bash
# Check what's running
aeims-ctl ps

# Get status with details
aeims-ctl status --verbose

# View error logs
aeims-ctl logs aeims-core | grep ERROR

# Restart problematic service
aeims-ctl restart aeims-core
```

## Service List

**Databases:** redis, postgres, mysql
**Core Services:** aeims-core, aeims-lib, aeims-admin, aeims-app
**Infrastructure:** nginx, health-monitor
**Microservices:** user-service, billing-service, call-service, operator-service, conference-service, notification-service
**Web Services:** admin-service, id-verify-service, aeims-web

## Help

```bash
aeims-ctl --help
```

## Full Documentation

See [CONTROL-PLANE.md](./CONTROL-PLANE.md) for complete documentation.
