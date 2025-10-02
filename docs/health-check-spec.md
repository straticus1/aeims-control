# AEIMS Health Check Specification

## Overview
All AEIMS services must implement standardized health check endpoints for proper monitoring and load balancing.

## Required Endpoints

### 1. Basic Health Check
- **Endpoint**: `/health`
- **Method**: GET
- **Response Code**: 200 (healthy), 503 (unhealthy)
- **Response Format**: JSON

```json
{
  "status": "healthy|degraded|unhealthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "service": "service-name",
  "version": "1.0.0",
  "uptime": 3600,
  "checks": {
    "database": "healthy",
    "redis": "healthy",
    "external_apis": "healthy"
  }
}
```

### 2. Readiness Check
- **Endpoint**: `/health/ready`
- **Method**: GET
- **Purpose**: Check if service is ready to receive traffic
- **Response Code**: 200 (ready), 503 (not ready)

### 3. Liveness Check
- **Endpoint**: `/health/live`
- **Method**: GET
- **Purpose**: Check if service is alive (for container restart decisions)
- **Response Code**: 200 (alive), 503 (dead)

### 4. Deep Health Check
- **Endpoint**: `/health/deep`
- **Method**: GET
- **Purpose**: Comprehensive health check including dependencies
- **Response Code**: 200 (healthy), 503 (unhealthy)

## Implementation Guidelines

### Database Health Check
```json
{
  "database": {
    "status": "healthy",
    "connection_pool": {
      "active": 5,
      "idle": 10,
      "max": 20
    },
    "response_time_ms": 15
  }
}
```

### Redis Health Check
```json
{
  "redis": {
    "status": "healthy",
    "ping_response_ms": 2,
    "memory_usage": "15MB",
    "connected_clients": 3
  }
}
```

### External API Health Check
```json
{
  "external_apis": {
    "status": "healthy",
    "apis": {
      "aeims-core": {
        "status": "healthy",
        "response_time_ms": 45,
        "last_check": "2024-01-01T12:00:00Z"
      }
    }
  }
}
```

## Service-Specific Requirements

### AEIMS Core
- Must check PostgreSQL connection
- Must check Redis connection
- Must verify FreeSWITCH connectivity
- Must check all microservice dependencies

### AEIMS App
- Must check MySQL connection
- Must check Redis connection
- Must verify AEIMS Core API connectivity

### AEIMS Lib
- Must check Redis connection
- Must verify WebSocket server status
- Must check device connection pool

### Microservices
- Must check PostgreSQL connection
- Must check Redis connection
- Must verify parent service connectivity

## Monitoring Integration

### Prometheus Metrics
All health endpoints should expose metrics at `/metrics`:

```
# HELP service_health_status Current health status (1=healthy, 0=unhealthy)
# TYPE service_health_status gauge
service_health_status{service="aeims-core",check="database"} 1

# HELP service_response_time_seconds Response time for health checks
# TYPE service_response_time_seconds histogram
service_response_time_seconds_bucket{service="aeims-core",check="database",le="0.01"} 10
```

### Load Balancer Configuration
- Health check path: `/health/ready`
- Check interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 3 consecutive failures

## Error Handling
- Health checks should never throw exceptions
- Use circuit breaker pattern for external dependency checks
- Implement timeout for all dependency checks (max 5 seconds)
- Log health check failures for debugging

## Security Considerations
- Health check endpoints should be accessible without authentication
- Limit information exposure in health responses
- Consider rate limiting for health check endpoints
- Use internal network for deep health checks when possible