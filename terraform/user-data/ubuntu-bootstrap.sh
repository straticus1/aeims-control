#!/bin/bash
set -x
echo "=== AEIMS INSTANCE BOOTSTRAP - UBUNTU 22.04 + DOCKER ==="

# Update system
apt-get update -y

# Install essential tools
apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    nginx \
    awscli \
    nodejs \
    npm \
    htop \
    net-tools

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install Docker Compose v2
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install AWS CLI v2 (upgrade from v1)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install --update
rm -rf aws awscliv2.zip

# Configure nginx for health checks
cat > /etc/nginx/sites-available/aeims-health << 'NGINX_EOF'
server {
    listen 8080 default_server;
    server_name _;
    
    location /health {
        return 200 '{"status":"healthy","service":"aeims-production","timestamp":"TIMESTAMP_PLACEHOLDER","instance":"INSTANCE_ID_PLACEHOLDER"}';
        add_header Content-Type application/json;
    }
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
}
NGINX_EOF

# Enable the site
ln -sf /etc/nginx/sites-available/aeims-health /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable nginx && systemctl start nginx

# Create deployment directory
mkdir -p /opt/aeims
chown ubuntu:ubuntu /opt/aeims

# Install SSM agent (should be included but ensure it's running)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Create auto-deploy script
cat > /opt/aeims/auto-deploy.sh << 'DEPLOY_EOF'
#!/bin/bash
set -x
echo "=== AUTO DEPLOYMENT STARTING ==="

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Update nginx config with real instance ID
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /etc/nginx/sites-available/aeims-health
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date -Iseconds)/g" /etc/nginx/sites-available/aeims-health
systemctl reload nginx

# Wait for Docker to be ready
while ! docker version >/dev/null 2>&1; do
    echo "Waiting for Docker..."
    sleep 2
done

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin 515966511618.dkr.ecr.$REGION.amazonaws.com

# Pull and start application
docker pull 515966511618.dkr.ecr.$REGION.amazonaws.com/aeims-lib-dev:latest
docker stop aeims-lib || true
docker rm aeims-lib || true
docker run -d --name aeims-lib --restart=unless-stopped -p 3000:3000 515966511618.dkr.ecr.$REGION.amazonaws.com/aeims-lib-dev:latest

# Wait and test
sleep 15
curl -f http://localhost:3000/ && echo "✅ Application responding"
curl -f http://localhost:8080/health && echo "✅ Health endpoint responding"

echo "=== AUTO DEPLOYMENT COMPLETE ==="
DEPLOY_EOF

chmod +x /opt/aeims/auto-deploy.sh
chown ubuntu:ubuntu /opt/aeims/auto-deploy.sh

# Run auto-deploy in background (non-blocking)
nohup /opt/aeims/auto-deploy.sh > /var/log/auto-deploy.log 2>&1 &

echo "=== BOOTSTRAP COMPLETE ==="
