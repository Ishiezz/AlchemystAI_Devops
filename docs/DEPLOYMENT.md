# Deployment Guide

Deploy and verify the AlchemystAI stack on AWS.

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] AWS Account created (https://aws.amazon.com)
- [ ] AWS Free Tier eligible (for cost optimization)
- [ ] AWS CLI installed and configured
- [ ] Terraform installed (>= 1.0)
- [ ] Git access to the repository
- [ ] SSH key pair for EC2 access
- [ ] Outbound internet access (for downloads)

### Install Dependencies

**macOS**:
```bash
# Install Terraform
brew install terraform

# Install AWS CLI
brew install awscli

# Install other tools
brew install git curl wget
```

**Ubuntu/Debian**:
```bash
# Install Terraform
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install AWS CLI
sudo apt-get update
sudo apt-get install -y awscli

# Install other tools
sudo apt-get install -y git curl wget
```

---

## Step 1: Configure AWS Credentials

### Option 1: Interactive Configuration

```bash
aws configure

# Follow prompts:
# AWS Access Key ID: [your access key]
# AWS Secret Access Key: [your secret key]
# Default region: us-east-1
# Default output format: json
```

### Option 2: Environment Variables

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### Option 3: AWS Credentials File

```bash
# ~/.aws/credentials
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY

# ~/.aws/config
[default]
region = us-east-1
output = json
```

### Verify Configuration

```bash
aws sts get-caller-identity

# Should output:
# {
#   "UserId": "...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/..."
# }
```

---

## Step 2: Clone Repository

```bash
git clone https://github.com/Ishiezz/AlchemystAI_Devops.git
cd AlchemystAI_Devops
```

---

## Step 3: Prepare Terraform Variables

### Copy example config

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
```

### Edit terraform.tfvars

```bash
# Edit the file with your settings
nano terraform.tfvars
```

**Key settings to adjust**:

```hcl
# Set your AWS region
aws_region = "us-east-1"

# IMPORTANT: Restrict SSH access to your IP
# Replace 0.0.0.0/0 with your_ip/32
ssh_cidr = "YOUR.IP.ADDRESS/32"

# Instance types (keep defaults for free tier)
api_instance_type    = "t3.small"
worker_instance_type = "t3.small"
```

### Find your public IP

```bash
curl https://ifconfig.me
# or
curl http://whatismyipaddress.com
```

---

## Step 4: Initialize Terraform

```bash
cd infrastructure

# Download provider plugins
terraform init

# Verify initialization
terraform version
ls -la .terraform/
```

---

## Step 5: Plan Deployment

### Validate configuration

```bash
# Check for syntax errors
terraform validate

# Format code (optional but recommended)
terraform fmt
```

### Review planned changes

```bash
# See what Terraform will create
terraform plan -out=tfplan

# Review output carefully:
# - VPC, subnets
# - Security groups
# - EC2 instances
# - IAM roles
```

### Save plan for safety

```bash
# Plan file created: tfplan
# This allows you to review before applying
ls -lh tfplan
```

---

## Step 6: Apply Terraform Configuration

### Apply the plan

```bash
# Create all infrastructure
terraform apply tfplan

# This will:
# 1. Create VPC and subnets
# 2. Create security groups
# 3. Create EC2 instances
# 4. Run initialization scripts
# Takes 3-5 minutes typically
```

### Verify creation

```bash
# Get instance IPs
terraform output

# Example output:
# api_endpoint = "http://35.192.0.100:3111"
# api_gateway_public_ip = "35.192.0.100"
# inference_worker_private_ip = "10.0.2.4"
```

---

## Step 7: Wait for Services to Start

Services initialize via cloud-init scripts. This takes **2-3 minutes**.

### Monitor initialization

```bash
# SSH to API gateway
API_IP=$(terraform output -raw api_gateway_public_ip)
ssh -i <your-key.pem> ubuntu@$API_IP

# Check cloud-init progress
tail -f /var/log/cloud-init-output.log

# Watch service status
watch -n 5 sudo systemctl status caller-worker
```

### Initialization steps (in order)

1. Update system packages (30 sec)
2. Install Node.js/Bun or Python (60 sec)
3. Clone repository (30 sec)
4. Install dependencies (60 sec)
5. Create systemd service (10 sec)
6. Start service (5 sec)

---

## Step 8: Verify Deployment

### Test API endpoint

```bash
# Get the API endpoint
API_ENDPOINT=$(terraform output -raw api_endpoint)

# Send test request
curl -X POST "$API_ENDPOINT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'

# Expected: HTTP 200 with JSON containing result.content and result.success
```

Example from a live deployment:

![Deployment verification](images/deployment-verification.png)

### Check service status

```bash
# SSH to API gateway
ssh -i <key.pem> ubuntu@$API_IP

# Check services are running
sudo systemctl status caller-worker
sudo systemctl status inference-worker

# View logs
sudo journalctl -u caller-worker -n 20
sudo journalctl -u inference-worker -n 20
```

### Verify network connectivity

```bash
# From API gateway, test connection to inference worker
ssh -i <key.pem> ubuntu@$API_IP

# Inside API gateway instance:
curl -v http://10.0.2.4:3111/

# Check port is listening
sudo netstat -tlnp | grep 3000
```

---

## Step 9: Test Full Inference

### Simple test

```bash
API_IP=$(terraform output -raw api_gateway_public_ip)

curl -X POST "http://$API_IP:3111/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Tell me a short joke"
      }
    ]
  }' | jq .
```

### Benchmark test

```bash
# Test multiple requests
for i in {1..5}; do
  echo "Request $i:"
  time curl -X POST "http://$API_IP:3111/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"messages": [{"role": "user", "content": "Hello"}]}' \
    -s | jq '.choices[0].message.content'
done
```

### Load test (caution: may timeout)

```bash
# Install apache bench
sudo apt-get install -y apache2-utils

# Run load test
ab -n 10 -c 2 -p request.json \
  -T "application/json" \
  "http://$API_IP:3111/v1/chat/completions"

# Note: Expect timeouts due to inference latency
```

---

## Step 10: Monitor and Debug

### View real-time logs

```bash
# SSH to instance
ssh -i <key.pem> ubuntu@$API_IP

# Stream caller-worker logs
sudo journalctl -u caller-worker -f

# In another terminal, stream inference-worker logs
ssh -i <key.pem> ubuntu@$INFERENCE_IP
sudo journalctl -u inference-worker -f
```

### Monitor resource usage

```bash
# SSH to instance
ssh -i <key.pem> ubuntu@$API_IP

# CPU and memory
top

# Disk usage
df -h
du -h /opt/alchemyst

# Network
netstat -s
```

### Check AWS metrics

```bash
# CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Network traffic
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkIn \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## Step 11: Document and Export

### Save outputs

```bash
# Export all outputs
terraform output > deployment-outputs.txt

# Export as JSON
terraform output -json > deployment-outputs.json

# Save for records
mkdir -p deployment-records
cp deployment-outputs.txt deployment-records/$(date +%Y-%m-%d_%H-%M-%S).txt
```

### Document API endpoint

```bash
# Save for your records
API_IP=$(terraform output -raw api_gateway_public_ip)
echo "API Endpoint: http://$API_IP:3111" > API_ENDPOINT.txt

# Example curl command
cat > test-api.sh << 'EOF'
#!/bin/bash
API_ENDPOINT="http://35.192.0.100:3111"
curl -X POST "$API_ENDPOINT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }' | jq .
EOF

chmod +x test-api.sh
```

---

## Step 12: Cleanup (When Done)

### Destroy infrastructure

**WARNING**: This will delete all resources and cannot be undone.

```bash
cd infrastructure

# Review what will be deleted
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm: type "yes"

# Verify deletion
aws ec2 describe-instances --filters "Name=tag:Project,Values=AlchemystAI"
aws ec2 describe-security-groups | grep alchemyst
aws ec2 describe-vpcs | grep alchemyst
```

### Clean up locally

```bash
# Remove terraform state
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl

# Remove sensitive data
rm -f .env
rm -f *.pem
rm -f terraform.tfvars

# Remove caches
rm -rf .terraform/
```

---

## Troubleshooting Common Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed debugging steps.

### Service not starting

```bash
ssh -i <key.pem> ubuntu@$API_IP
sudo journalctl -u caller-worker -n 50
sudo systemctl status caller-worker
```

### Network not working

```bash
# Check security groups
aws ec2 describe-security-groups --query 'SecurityGroups[?Tags[?Key==`Name`]].{Name:GroupName,ID:GroupId}' --output table

# Test connectivity
curl -v http://$API_IP:3111/
```

### Terraform errors

```bash
# Validate configuration
terraform validate

# Check state
terraform state list
terraform state show aws_instance.api_gateway
```

---

## Success Criteria

Your deployment is successful when:

- [ ] `terraform apply` completes without errors
- [ ] All instances are running: `aws ec2 describe-instances`
- [ ] API endpoint responds: `curl http://$API_IP:3111/`
- [ ] Inference returns results (not 500 error)
- [ ] Services are enabled: `sudo systemctl is-enabled <service>`
- [ ] Logs show successful operations: `journalctl -n 20`

---

## Next Steps

1. Test with more complex prompts
2. Monitor performance and costs
3. Implement production hardening (see README.md)
4. Set up monitoring and alerts
5. Plan for scaling
