# AEIMS Terraform Variables
environment = "dev"
aws_region = "us-east-1"
project_name = "aeims"
domain_name = "aeims.app"
certificate_arn = "arn:aws:acm:us-east-1:515966511618:certificate/3cd022c3-2e56-4ba3-931a-9821ad316ef4"
enable_service_mesh = false
enable_disaster_recovery = false

# NOTE: VPC consolidation complete - all AEIMS resources now in afterdarksys-vpc (vpc-0c1b813880b3982a5)
# AEIMS subnets: subnet-06bae1d43ca2a0b28 (10.0.30.0/24, us-east-1a), subnet-032726d3ea98dc979 (10.0.31.0/24, us-east-1b)
# AEIMS security group: sg-07d6a1e80388e45da
