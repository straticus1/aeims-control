# AEIMS Service Architecture & Port Mapping

## Overview
This document provides a complete mapping of all AEIMS services, their ports, purposes, and interconnections.

## Port Allocation Summary

### External Ports (Host Machine Access)
These ports are exposed on your MacOS host machine:

| Port  | Service                  | Protocol | Purpose                              |
|-------|--------------------------|----------|--------------------------------------|
| 81    | aeims-app                | HTTP     | AEIMS marketing/showcase website    |
| 443   | aeims-app                | HTTPS    | AEIMS marketing SSL                 |
| 3000  | aeims-frontend           | HTTP     | SEXACOMMS React frontend             |
| 3306  | aeims-app-mysql          | MySQL    | App database                         |
| 5432  | aeims-core-postgres      | PostgreSQL | Core database                      |
| 6379  | aeims-redis              | Redis    | Cache & session storage              |
| 8000  | aeims-core               | HTTP     | Core API server                      |
| 8001  | aeims-user-service       | HTTP     | User management API                  |
| 8002  | aeims-billing-service    | HTTP     | Billing & payment API                |
| 8003  | aeims-telephony-service  | HTTP     | Telephony management API             |
| 8004  | aeims-call-service       | HTTP     | Call handling API                    |
| 8005  | aeims-operator-service   | HTTP     | Operator management API              |
| 8006  | aeims-session-service    | HTTP     | Session management API               |
| 8007  | aeims-analytics-service  | HTTP     | Analytics & reporting API            |
| 8008  | aeims-admin-service      | HTTP     | Admin interface API                  |
| 8009  | aeims-content-service    | HTTP     | Content management API               |
| 8010  | aeims-file-service       | HTTP     | File storage API                     |
| 8011  | aeims-marketing-service  | HTTP     | Marketing automation API             |
| 8012  | aeims-verification-service | HTTP   | Age/identity verification API        |
| 8081  | aeims-lib                | WebSocket | Device control & Buttplug.io        |
| 8085  | aeims-nginx              | HTTP     | Main reverse proxy/load balancer     |
| 8445  | aeims-nginx              | HTTPS    | SSL reverse proxy                    |

### Internal Ports (Container Network Only)
These ports are only accessible within the Docker network:

| Port  | Service         | Purpose                          |
|-------|-----------------|----------------------------------|
| 9000  | aeims-php-fpm   | PHP FastCGI Process Manager      |
| 3000  | aeims-grafana   | Monitoring dashboard (when enabled) |
| 9090  | aeims-prometheus | Metrics collection (when enabled) |

## Service Details

### 1. Database Services

#### aeims-core-postgres
- **Port:** 5432
- **Purpose:** Primary database for core services
- **Database:** aeims_core
- **User:** aeims_user
- **Password:** secure_password_123
- **Contains:** User accounts, operators, sessions, call records

#### aeims-app-mysql
- **Port:** 3306
- **Purpose:** Database for marketing website
- **Database:** aeims_app
- **User:** aeims_user  
- **Password:** secure_password_123
- **Contains:** CMS data, marketing content, analytics

#### aeims-redis
- **Port:** 6379
- **Purpose:** Cache, session storage, real-time data
- **Password:** secure_redis_pass
- **Used for:** Session management, rate limiting, WebSocket state

### 2. Core Services

#### aeims-core
- **Port:** 8000
- **Build Path:** ../aeims/telephony-platform/core
- **Language:** Python/Django
- **Purpose:** Main API server, orchestrates all services
- **Key Features:**
  - Authentication & authorization
  - Service orchestration
  - API gateway functionality
  - Database migrations

#### aeims-lib
- **Port:** 8081 (maps to container's 8080)
- **Build Path:** ../aeimsLib
- **Language:** PHP
- **Purpose:** Device control & integration
- **Key Features:**
  - Buttplug.io protocol support
  - WebSocket server for real-time device control
  - Supports 15+ adult device brands
  - VR/AR integration capabilities

### 3. Microservices

#### aeims-user-service
- **Port:** 8001 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/user-service
- **Language:** PHP
- **Purpose:** User account management
- **Endpoints:** /users/*

#### aeims-billing-service
- **Port:** 8002 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/billing-service
- **Language:** PHP
- **Purpose:** Payment processing & billing
- **Endpoints:** /billing/*
- **Features:** Discrete billing, multiple payment gateways

#### aeims-telephony-service
- **Port:** 8003 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/telephony-service
- **Language:** PHP
- **Purpose:** Phone system integration
- **Features:** FreeSWITCH, Asterisk, Twilio support

#### aeims-call-service
- **Port:** 8004 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/call-service
- **Language:** PHP
- **Purpose:** Call routing and management

#### aeims-operator-service
- **Port:** 8005 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/operator-service
- **Language:** PHP
- **Purpose:** Operator management
- **Features:** Cross-site operator support

#### aeims-session-service
- **Port:** 8006 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/session-service
- **Language:** PHP
- **Purpose:** Session management

#### aeims-analytics-service
- **Port:** 8007 (maps to container's 9000)
- **Build Path:** ../aeims/telephony-platform/services/analytics-service
- **Language:** PHP
- **Purpose:** Analytics and reporting
- **Endpoints:** /analytics/*

#### aeims-admin-service
- **Port:** 8008 (maps to container's 8000)
- **Build Path:** ../aeims/telephony-platform/services/admin-service
- **Language:** Python
- **Purpose:** Admin interface backend

#### aeims-content-service
- **Port:** 8009 (maps to container's 8000)
- **Build Path:** ../aeims/telephony-platform/services/content-service
- **Language:** Python
- **Purpose:** Content management

#### aeims-file-service
- **Port:** 8010 (maps to container's 8000)
- **Build Path:** ../aeims/telephony-platform/services/file-service
- **Language:** Python
- **Purpose:** File storage and CDN

#### aeims-marketing-service
- **Port:** 8011 (maps to container's 8000)
- **Build Path:** ../aeims/telephony-platform/services/marketing-service
- **Language:** Python
- **Purpose:** Marketing automation

#### aeims-verification-service
- **Port:** 8012 (maps to container's 8000)
- **Build Path:** ../aeims/telephony-platform/services/verification-service
- **Language:** Python
- **Purpose:** Age and identity verification

### 4. Frontend Services

#### aeims-frontend
- **Port:** 3000
- **Build Path:** ../aeims/telephony-platform/frontend
- **Framework:** React with TypeScript
- **Purpose:** SEXACOMMS operator/user interface
- **Features:**
  - Real-time chat interface
  - Video/audio call UI
  - Device control interface
  - Operator dashboard

#### aeims-app
- **Port:** 81 (HTTP), 443 (HTTPS)
- **Build Path:** ../aeims.app
- **Language:** PHP
- **Purpose:** AEIMS marketing website
- **Features:**
  - Product showcase
  - Pricing information
  - Documentation
  - Client portal

### 5. Infrastructure Services

#### aeims-nginx
- **Port:** 8085 (HTTP), 8445 (HTTPS)
- **Build Path:** ./nginx
- **Purpose:** Reverse proxy and load balancer
- **Routes:**
  - login.sexacomms.com → aeims-frontend
  - www.sexacomms.com → aeims-frontend
  - api.sexacomms.com → aeims-core
  - flirts.nyc → PHP site via aeims-php-fpm
  - nycflirts.com → PHP site via aeims-php-fpm
  - /api/* → aeims-core
  - /ws/* → aeims-lib (WebSocket)
  - /users/* → aeims-user-service
  - /billing/* → aeims-billing-service
  - /analytics/* → aeims-analytics-service

#### aeims-php-fpm
- **Port:** 9000 (internal only)
- **Image:** php:8.2-fpm
- **Purpose:** PHP FastCGI processor for sites
- **Serves:** flirts.nyc, nycflirts.com PHP sites

### 6. Monitoring Services (Optional)

#### aeims-prometheus
- **Port:** 9090 (when enabled)
- **Purpose:** Metrics collection
- **Profile:** monitoring

#### aeims-grafana  
- **Port:** 3001 (when enabled)
- **Purpose:** Metrics visualization
- **Profile:** monitoring
- **Default Login:** admin / admin123

## Service Dependencies

```
aeims-nginx
    ├── aeims-core
    │   ├── aeims-core-postgres
    │   └── aeims-redis
    ├── aeims-frontend
    │   └── aeims-core
    ├── aeims-app
    │   ├── aeims-app-mysql
    │   └── aeims-redis
    ├── aeims-lib
    │   └── aeims-redis
    ├── aeims-php-fpm
    └── [All Microservices]
        ├── aeims-core-postgres
        └── aeims-redis
```

## Network Architecture

All services communicate through the `aeims-network` Docker bridge network.

### External Access Points:
1. **Main Nginx Proxy:** http://localhost:8085 / https://localhost:8445
2. **AEIMS Marketing:** http://localhost:81 / https://localhost:443
3. **SEXACOMMS Frontend:** http://localhost:3000
4. **Core API:** http://localhost:8000
5. **Device Control WebSocket:** ws://localhost:8081

### Domain Routing (via nginx):
- `login.sexacomms.com` → SEXACOMMS Frontend (React)
- `www.sexacomms.com` → SEXACOMMS Frontend (React)
- `api.sexacomms.com` → Core API
- `flirts.nyc` → PHP Site
- `nycflirts.com` → PHP Site
- Default → AEIMS Marketing

## Volume Mounts

| Volume | Purpose | Used By |
|--------|---------|---------|
| aeims_postgres_data | PostgreSQL data | aeims-core-postgres |
| aeims_mysql_data | MySQL data | aeims-app-mysql |
| aeims_redis_data | Redis persistence | aeims-redis |
| aeims_logs | Application logs | Multiple services |
| aeims_uploads | User uploads | aeims-app |
| ../aeims/sites | PHP site files | aeims-nginx, aeims-php-fpm |

## Health Checks

Most services include health checks:
- **Databases:** Connection test
- **HTTP Services:** GET /health endpoint
- **Redis:** PING command
- **Nginx:** Config test

## Development Access

### Service URLs for Testing:
```bash
# Core API
curl http://localhost:8000/api/health

# AEIMS Marketing
curl http://localhost:81/

# SEXACOMMS Frontend
curl http://localhost:3000/

# Device Control WebSocket
wscat -c ws://localhost:8081/

# Via Nginx Proxy
curl http://localhost:8085/
curl http://localhost:8085/api/
curl http://localhost:8085/users/
```

### Database Access:
```bash
# PostgreSQL
psql -h localhost -p 5432 -U aeims_user -d aeims_core

# MySQL
mysql -h localhost -P 3306 -u aeims_user -p aeims_app

# Redis
redis-cli -h localhost -p 6379 -a secure_redis_pass
```

## Troubleshooting

### Check Service Status:
```bash
docker compose ps
```

### View Service Logs:
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f aeims-core
```

### Restart Services:
```bash
# All services
docker compose restart

# Specific service
docker compose restart aeims-nginx
```

### Port Conflicts:
If ports are already in use, update the `.env` file:
```
NGINX_HTTP_PORT=8086
NGINX_HTTPS_PORT=8446
AEIMS_APP_PORT=82
```

## Security Notes

1. **Change all default passwords** before production deployment
2. **SSL certificates** needed for HTTPS (currently using self-signed)
3. **Firewall rules** should restrict database ports in production
4. **Rate limiting** is configured in nginx for API endpoints
5. **CORS headers** configured for cross-origin requests

## Next Steps

1. Generate proper SSL certificates
2. Configure domain DNS to point to server
3. Set up backup strategies for databases
4. Enable monitoring services for production
5. Configure log aggregation
6. Set up CI/CD pipelines