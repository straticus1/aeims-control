#!/bin/bash
set -x
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== STARTING UBUNTU 22.04 BOOTSTRAP SCRIPT ==="
echo "Starting at $(date)"

# Update system first
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install essential packages for Ubuntu 22.04
apt-get install -y \
    awscli \
    curl \
    wget \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https

echo "=== INSTALLING DOCKER ==="
# Install Docker for Ubuntu 22.04
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

echo "=== INSTALLING DOCKER COMPOSE ==="
# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "=== INSTALLING NGINX ==="
# Install and configure nginx
apt-get install -y nginx

# Create nginx config directory
mkdir -p /etc/nginx/conf.d

# Create basic nginx configuration for ALB health checks
cat > /etc/nginx/conf.d/aeims-health.conf << 'EOF'
server {
    listen 8080;
    server_name _;

    location /health {
        access_log off;
        return 200 '{"status":"healthy","service":"aeims-production","timestamp":"$msec","host":"$hostname"}';
        add_header Content-Type application/json;
    }

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}

# Default server for port 80
server {
    listen 80 default_server;
    server_name _;

    location /health {
        access_log off;
        return 200 '{"status":"healthy","service":"aeims-production","timestamp":"$msec","host":"$hostname"}';
        add_header Content-Type application/json;
    }

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Test nginx configuration
nginx -t

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

echo "=== INSTALLING AWS SSM AGENT ==="
# Install SSM agent for Ubuntu (different from Amazon Linux)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

echo "=== SETTING UP ECR LOGIN ==="
# Create ECR login script
cat > /home/ubuntu/ecr-login.sh << 'EOF'
#!/bin/bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 515966511618.dkr.ecr.us-east-1.amazonaws.com
EOF
chmod +x /home/ubuntu/ecr-login.sh
chown ubuntu:ubuntu /home/ubuntu/ecr-login.sh

echo "=== PULLING APPLICATION CONTAINERS ==="
# Login to ECR and pull containers
/home/ubuntu/ecr-login.sh

# Pull the latest application container
docker pull 515966511618.dkr.ecr.us-east-1.amazonaws.com/aeims-lib-dev:latest || echo "Failed to pull aeims-lib-dev"
docker pull 515966511618.dkr.ecr.us-east-1.amazonaws.com/aeims-lib-simple:latest || echo "Failed to pull aeims-lib-simple"

echo "=== STARTING APPLICATION SERVICES ==="
# Start the application container with correct port mapping
# aeimsLib runs on port 8080 inside container, map to host port 3000
docker run -d \
    --name aeims-lib \
    --restart=unless-stopped \
    -p 3000:8080 \
    -e NODE_ENV=production \
    -e WEBSOCKET_PORT=8080 \
    -e LOG_LEVEL=info \
    515966511618.dkr.ecr.us-east-1.amazonaws.com/aeims-lib-dev:latest || echo "Failed to start aeims-lib"

echo "=== WAITING FOR SERVICES TO START ==="
sleep 30

echo "=== TESTING SERVICES ==="
# Test application health
curl -f http://localhost:3000/health || echo "Application health check failed"
curl -f http://localhost:8080/health || echo "Nginx health check failed"

# Show running containers
docker ps -a

# Show nginx status
systemctl status nginx --no-pager

# Show what's listening on ports
netstat -tulpn | grep -E ":(3000|8080)" || echo "No listeners on 3000 or 8080"

# Create startup script for application
cat > /home/ubuntu/start-aeims.sh << 'EOF'
#!/bin/bash
echo "Starting AEIMS application services..."

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 515966511618.dkr.ecr.us-east-1.amazonaws.com

# Stop existing containers
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Pull latest containers
docker pull 515966511618.dkr.ecr.us-east-1.amazonaws.com/aeims-lib-dev:latest

# Start application with correct port mapping (container:8080 -> host:3000)
docker run -d \
    --name aeims-lib \
    --restart=unless-stopped \
    -p 3000:8080 \
    -e NODE_ENV=production \
    -e WEBSOCKET_PORT=8080 \
    -e LOG_LEVEL=info \
    515966511618.dkr.ecr.us-east-1.amazonaws.com/aeims-lib-dev:latest

sleep 15
echo "AEIMS application started. Testing health..."
curl -f http://localhost:3000/health || echo "Health check failed"
curl -f http://localhost:8080/health || echo "Nginx proxy health check failed"
docker ps
EOF

chmod +x /home/ubuntu/start-aeims.sh
chown ubuntu:ubuntu /home/ubuntu/start-aeims.sh

# Create systemd service for auto-start
cat > /etc/systemd/system/aeims-app.service << 'EOF'
[Unit]
Description=AEIMS Application Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/home/ubuntu/start-aeims.sh
RemainAfterExit=yes
StandardOutput=journal
User=ubuntu
Group=docker

[Install]
WantedBy=multi-user.target
EOF

systemctl enable aeims-app.service

echo "=== UBUNTU BOOTSTRAP COMPLETE ==="
echo "Completed at $(date)"
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Nginx version: $(nginx -v 2>&1)"
echo "Running containers:"
docker ps
echo "=== BOOTSTRAP LOG END ==="