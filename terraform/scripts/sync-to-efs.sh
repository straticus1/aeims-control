#!/bin/bash
# Script to sync local AEIMS sites and configurations to EFS
# Run this after terraform creates the EFS file systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AEIMS EFS Sync Script${NC}"
echo "This script will sync your local AEIMS sites and configurations to EFS"
echo ""

# Check if terraform output exists
if ! terraform output -json > /dev/null 2>&1; then
    echo -e "${RED}Error: Unable to read terraform output. Run terraform apply first.${NC}"
    exit 1
fi

# Get EFS file system IDs from terraform output
SITES_EFS_ID=$(terraform output -json efs_file_system_ids | jq -r '.sites')
DATA_EFS_ID=$(terraform output -json efs_file_system_ids | jq -r '.data')
NGINX_EFS_ID=$(terraform output -json efs_file_system_ids | jq -r '.nginx')

echo "EFS File Systems:"
echo "  Sites: $SITES_EFS_ID"
echo "  Data:  $DATA_EFS_ID"
echo "  Nginx: $NGINX_EFS_ID"
echo ""

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region || echo "us-east-1")

# Check if EFS is available
echo -e "${YELLOW}Checking EFS availability...${NC}"
for efs_id in "$SITES_EFS_ID" "$DATA_EFS_ID" "$NGINX_EFS_ID"; do
    if ! aws efs describe-file-systems --file-system-id "$efs_id" --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${RED}Error: EFS $efs_id not found or not accessible${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ All EFS file systems are available${NC}"
echo ""

# Create temporary mount points
TEMP_MOUNT_BASE="/tmp/aeims-efs-sync"
SITES_MOUNT="$TEMP_MOUNT_BASE/sites"
DATA_MOUNT="$TEMP_MOUNT_BASE/data"
NGINX_MOUNT="$TEMP_MOUNT_BASE/nginx"

mkdir -p "$SITES_MOUNT" "$DATA_MOUNT" "$NGINX_MOUNT"

# Function to mount EFS
mount_efs() {
    local efs_id=$1
    local mount_point=$2
    local region=$3
    
    echo -e "${YELLOW}Mounting $efs_id to $mount_point...${NC}"
    
    # Check if already mounted
    if mount | grep -q "$mount_point"; then
        echo -e "${GREEN}✓ Already mounted${NC}"
        return 0
    fi
    
    # Mount using EFS mount helper
    sudo mount -t efs -o tls "$efs_id:/" "$mount_point"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Mounted successfully${NC}"
    else
        echo -e "${RED}✗ Mount failed${NC}"
        return 1
    fi
}

# Function to unmount EFS
unmount_efs() {
    local mount_point=$1
    if mount | grep -q "$mount_point"; then
        echo -e "${YELLOW}Unmounting $mount_point...${NC}"
        sudo umount "$mount_point"
    fi
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    unmount_efs "$SITES_MOUNT"
    unmount_efs "$DATA_MOUNT"
    unmount_efs "$NGINX_MOUNT"
    rm -rf "$TEMP_MOUNT_BASE"
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Register cleanup on exit
trap cleanup EXIT

# Mount all EFS file systems
echo -e "${YELLOW}Mounting EFS file systems...${NC}"
mount_efs "$SITES_EFS_ID" "$SITES_MOUNT" "$AWS_REGION" || exit 1
mount_efs "$DATA_EFS_ID" "$DATA_MOUNT" "$AWS_REGION" || exit 1
mount_efs "$NGINX_EFS_ID" "$NGINX_MOUNT" "$AWS_REGION" || exit 1
echo ""

# Sync sites directory
echo -e "${GREEN}Syncing AEIMS sites...${NC}"
SITES_SOURCE="/Users/ryan/development/aeims/sites/"
if [ -d "$SITES_SOURCE" ]; then
    sudo rsync -av --exclude='_archived' "$SITES_SOURCE" "$SITES_MOUNT/sites/"
    echo -e "${GREEN}✓ Sites synced successfully${NC}"
else
    echo -e "${YELLOW}⚠ Sites directory not found at $SITES_SOURCE${NC}"
fi
echo ""

# Sync data directory
echo -e "${GREEN}Syncing AEIMS data (sites.json)...${NC}"
DATA_SOURCE="/Users/ryan/development/aeims/data/"
if [ -d "$DATA_SOURCE" ]; then
    sudo rsync -av "$DATA_SOURCE" "$DATA_MOUNT/data/"
    echo -e "${GREEN}✓ Data synced successfully${NC}"
else
    echo -e "${YELLOW}⚠ Data directory not found at $DATA_SOURCE${NC}"
fi
echo ""

# Sync nginx configurations
echo -e "${GREEN}Syncing nginx configurations...${NC}"
NGINX_SOURCE="/Users/ryan/development/aeims/telephony-platform/nginx/sites-enabled/"
if [ -d "$NGINX_SOURCE" ]; then
    sudo rsync -av "$NGINX_SOURCE" "$NGINX_MOUNT/nginx/"
    echo -e "${GREEN}✓ Nginx configs synced successfully${NC}"
else
    echo -e "${YELLOW}⚠ Nginx directory not found at $NGINX_SOURCE${NC}"
fi
echo ""

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
sudo chown -R 1000:1000 "$SITES_MOUNT/sites" "$DATA_MOUNT/data" "$NGINX_MOUNT/nginx"
sudo chmod -R 755 "$SITES_MOUNT/sites" "$DATA_MOUNT/data" "$NGINX_MOUNT/nginx"
echo -e "${GREEN}✓ Permissions set${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EFS Sync Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Update your ECS task definition to mount these EFS volumes"
echo "2. Deploy the updated task definition"
echo "3. Your sites will now persist across container restarts!"
echo ""
