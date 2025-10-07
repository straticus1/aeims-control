# AEIMS Multi-Site Deployment Guide with EFS Persistence

## Overview
This guide will help you deploy the AEIMS multi-site architecture with persistent storage using AWS EFS. Your sites (nycflirts.com and flirts.nyc) will persist across ECS task restarts and redeployments.

## Architecture

### Domains & SSL Certificates
- **aeims.app** + *.aeims.app - Marketing/platform site (primary certificate)
- **nycflirts.com** + www.nycflirts.com - NYC Flirts dating site  
- **flirts.nyc** + www.flirts.nyc - Flirts NYC dating site
- **afterdarksys.com** + *.afterdarksys.com - Business/infrastructure site (PRESERVED)

### Persistent Storage (EFS)
- **Sites EFS**: `/var/www/html/sites/` - Site content (nycflirts.com, flirts.nyc)
- **Data EFS**: `/var/www/html/data/` - Configuration (sites.json)
- **Nginx EFS**: `/etc/nginx/sites-enabled/` - Nginx configurations

## Deployment Steps

### Step 1: Initialize Terraform
```bash
cd /Users/ryan/development/aeims-control/terraform
terraform init
```

### Step 2: Review the Plan
```bash
terraform plan
```

This will show:
- 3 new EFS file systems
- EFS mount targets (one per subnet)
- EFS access points
- EFS security group
- EFS backup policies

### Step 3: Apply Terraform Configuration
```bash
terraform apply
```

Type `yes` when prompted. This will create:
- Encrypted EFS file systems with KMS
- Mount targets in all private subnets
- Access points for proper permissions
- Security groups allowing NFS from ECS tasks
- Automatic backups enabled

**Expected time**: ~5-10 minutes

### Step 4: Sync Local Data to EFS
After terraform completes, sync your local AEIMS data:

```bash
cd /Users/ryan/development/aeims-control/terraform
./scripts/sync-to-efs.sh
```

This script will:
1. Mount all 3 EFS file systems temporarily
2. Sync `/Users/ryan/development/aeims/sites/` → EFS
3. Sync `/Users/ryan/development/aeims/data/` → EFS  
4. Sync nginx configs → EFS
5. Set proper permissions (uid/gid 1000)
6. Unmount and cleanup

### Step 5: Update ECS Task Definition

Your ECS task definition needs to mount the EFS volumes. Add these volume definitions:

```json
{
  "volumes": [
    {
      "name": "aeims-sites",
      "efsVolumeConfiguration": {
        "fileSystemId": "<SITES_EFS_ID>",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "<SITES_ACCESS_POINT_ID>",
          "iam": "ENABLED"
        }
      }
    },
    {
      "name": "aeims-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "<DATA_EFS_ID>",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "<DATA_ACCESS_POINT_ID>",
          "iam": "ENABLED"
        }
      }
    },
    {
      "name": "nginx-config",
      "efsVolumeConfiguration": {
        "fileSystemId": "<NGINX_EFS_ID>",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "<NGINX_ACCESS_POINT_ID>",
          "iam": "ENABLED"
        }
      }
    }
  ]
}
```

Get the IDs from terraform output:
```bash
terraform output efs_file_system_ids
terraform output efs_access_point_ids
```

### Step 6: Add Mount Points to Container Definitions

In your container definitions, add mount points:

**For PHP/Application Container:**
```json
{
  "mountPoints": [
    {
      "sourceVolume": "aeims-sites",
      "containerPath": "/var/www/html/sites",
      "readOnly": false
    },
    {
      "sourceVolume": "aeims-data",
      "containerPath": "/var/www/html/data",
      "readOnly": false
    }
  ]
}
```

**For Nginx Container:**
```json
{
  "mountPoints": [
    {
      "sourceVolume": "nginx-config",
      "containerPath": "/etc/nginx/sites-enabled",
      "readOnly": true
    }
  ]
}
```

### Step 7: Deploy Updated Task Definition

```bash
# Register new task definition
aws ecs register-task-definition --cli-input-json file://task-definition.json

# Update service to use new task definition
aws ecs update-service \
  --cluster aeims-cluster \
  --service aeims-service \
  --task-definition aeims-service:LATEST \
  --force-new-deployment
```

### Step 8: Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster aeims-cluster \
  --services aeims-service

# Check task health
aws ecs list-tasks --cluster aeims-cluster --service-name aeims-service

# Test the sites
curl -I https://nycflirts.com
curl -I https://flirts.nyc
```

## Site Testing Checklist

### NYC Flirts (nycflirts.com)
- [ ] Homepage loads with NYC Flirts branding
- [ ] SSL certificate valid
- [ ] Login/signup functional
- [ ] User profiles accessible
- [ ] Search works
- [ ] Chat/messaging functional
- [ ] Payment system operational

### Flirts NYC (flirts.nyc)
- [ ] Homepage loads with Flirts NYC branding
- [ ] SSL certificate valid
- [ ] Login/signup functional
- [ ] User profiles accessible
- [ ] Search works
- [ ] Chat/messaging functional
- [ ] Payment system operational

## Troubleshooting

### EFS Mount Issues
If containers can't mount EFS:
1. Check security group allows NFS (port 2049) from ECS tasks
2. Verify mount targets are in `available` state
3. Check ECS task IAM role has EFS permissions
4. Review CloudWatch logs for mount errors

### Site Not Loading
1. Check EFS sync completed successfully
2. Verify sites.json exists in data EFS
3. Check nginx configs are present in nginx EFS
4. Review application logs for SiteManager errors

### Permission Issues
If you see permission errors:
```bash
# Re-run permissions fix in sync script
sudo chown -R 1000:1000 /mnt/efs/sites
sudo chmod -R 755 /mnt/efs/sites
```

## Rollback Procedure

If you need to rollback:

```bash
# Revert to previous task definition
aws ecs update-service \
  --cluster aeims-cluster \
  --service aeims-service \
  --task-definition aeims-service:PREVIOUS_VERSION

# Or destroy EFS (WARNING: This deletes all data!)
terraform destroy -target=aws_efs_file_system.aeims_sites
```

## Cost Optimization

- EFS uses infrequent access (IA) after 30 days
- Backups enabled for production safety
- Consider EFS lifecycle policies for older data
- Monitor EFS metrics in CloudWatch

## Maintenance

### Update Sites
To update site content:
```bash
# Option 1: Update via the running container
aws ecs execute-command \
  --cluster aeims-cluster \
  --task TASK_ID \
  --container app \
  --command "/bin/bash" \
  --interactive

# Option 2: Mount EFS locally and update
# (Same process as sync-to-efs.sh but manual)
```

### Backup Sites
Backups are automatic via AWS Backup, but for manual backup:
```bash
aws backup start-backup-job \
  --backup-vault-name Default \
  --resource-arn arn:aws:elasticfilesystem:REGION:ACCOUNT:file-system/SITES_EFS_ID
```

## Next Steps

1. Set up monitoring dashboards for EFS metrics
2. Configure alerting for EFS throughput issues
3. Test disaster recovery procedures
4. Document site update workflows
5. Train team on EFS maintenance

## Support

For issues:
1. Check CloudWatch logs: `/aws/aeims/prod/`
2. Review ECS events in AWS Console
3. Check EFS mount target status
4. Verify security groups and IAM policies
