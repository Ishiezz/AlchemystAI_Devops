# Quick Reference

Command reference for deploy, debug, and teardown.

## Setup

```bash
# 1. Configure AWS credentials
aws configure
# or export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY

# 2. Clone repository
git clone https://github.com/Ishiezz/AlchemystAI_Devops.git
cd AlchemystAI_Devops

# 3. Prepare Terraform
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Edit with your settings
```

## Terraform Commands

```bash
# Initialize (first time only)
terraform init

# Check syntax
terraform validate

# Format code
terraform fmt

# Preview changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# View outputs
terraform output
terraform output api_gateway_public_ip

# Destroy (WARNING: removes everything)
terraform destroy
terraform destroy -auto-approve

# Check state
terraform state list
terraform state show aws_instance.api_gateway
```

## Deployment

```bash
# Get IP addresses
API_IP=$(terraform output -raw api_gateway_public_ip)
INFERENCE_IP=$(terraform output -raw inference_worker_private_ip)

# Wait 2-3 minutes for services to start
sleep 180

# Validate deployment
../validate-deployment.sh
```

## Testing

```bash
# Simple test
curl -X POST "http://$API_IP:3111/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}]}'

# Pretty print response
curl -X POST "http://$API_IP:3111/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Tell me a joke"}]}' \
  | jq .

# Test with timeout (model loading takes time)
curl --max-time 30 \
  -X POST "http://$API_IP:3111/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is AI?"}]}'
```

## SSH Access

```bash
# SSH to API gateway (public)
ssh -i <your-key.pem> ubuntu@$API_IP

# SSH to inference worker (via bastion)
ssh -i <your-key.pem> -J ubuntu@$API_IP ubuntu@10.0.2.4

# Or add to ~/.ssh/config
# Host api-gateway
#   HostName <api-ip>
#   User ubuntu
#   IdentityFile ~/.ssh/alchemyst.pem
# Host inference-worker
#   HostName 10.0.2.4
#   User ubuntu
#   ProxyJump api-gateway
#   IdentityFile ~/.ssh/alchemyst.pem
```

## Service Management

```bash
# SSH to instance first
ssh -i <key.pem> ubuntu@$API_IP

# View service status
sudo systemctl status caller-worker
sudo systemctl status inference-worker

# View logs (real-time)
sudo journalctl -u caller-worker -f
sudo journalctl -u inference-worker -f

# View recent logs
sudo journalctl -u caller-worker -n 50
sudo journalctl -u inference-worker -n 100

# Restart service
sudo systemctl restart caller-worker
sudo systemctl restart inference-worker

# Enable on boot
sudo systemctl enable caller-worker
sudo systemctl enable inference-worker

# Check if listening
sudo netstat -tlnp | grep -E '3111|49134'
sudo ss -tlnp | grep -E '3111|49134'
```

## Debugging

```bash
# Check instance status
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=AlchemystAI" \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType,IP:PublicIpAddress}'

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=alchemyst*"

# Check VPC
aws ec2 describe-vpcs \
  --filters "Name=cidr,Values=10.0.0.0/16"

# Check route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-id>"

# Check NAT Gateway
aws ec2 describe-nat-gateways
```

## System Information

```bash
# SSH to instance, then:

# System info
uname -a
lsb_release -a

# Check running services
systemctl list-units --type=service --state=running

# Check ports
netstat -tlnp
ss -tlnp

# Check resources
free -h          # Memory
df -h             # Disk space
top -n 1          # CPU
du -h /opt        # Directory sizes

# Check logs
tail -f /var/log/cloud-init-output.log
tail -f /var/log/syslog
```

## AWS CLI Commands

```bash
# Get all instances with tags
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=AlchemystAI" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],ID:InstanceId,IP:PrivateIpAddress}'

# Get instance details
aws ec2 describe-instances --instance-ids <instance-id>

# Get logs from CloudWatch (after agent setup)
aws logs tail /aws/ec2/inference-worker --follow

# Monitor NAT Gateway
aws cloudwatch get-metric-statistics \
  --namespace AWS/NatGateway \
  --metric-name BytesOutToDestination \
  --dimensions Name=NatGatewayId,Value=<nat-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Monitor EC2 CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Cost Monitoring

```bash
# Estimate costs for current resources
aws ce estimate-monthly-cost \
  --services ec2 nat

# Check for unused resources
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name==`stopped`]'

# View AWS billing (requires billing API access)
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-23 \
  --granularity DAILY \
  --metrics BlendedCost
```

## Troubleshooting Quick Steps

```bash
# 1. Check instance running
aws ec2 describe-instances | grep -i "state\|running"

# 2. Check service status
ssh -i <key.pem> ubuntu@$API_IP
sudo systemctl status caller-worker
sudo journalctl -u caller-worker -n 50

# 3. Test connectivity
curl -v http://$API_IP:3111/

# 4. Check security groups
aws ec2 describe-security-groups | grep -i "alchemyst\|3000"

# 5. Test RPC from API gateway
ssh -i <key.pem> ubuntu@$API_IP
curl -v http://10.0.2.4:3111/
```

## Cleanup

```bash
# Remove plan file
rm -f tfplan

# Destroy infrastructure
cd infrastructure
terraform destroy

# Remove state files
rm -f terraform.tfstate*

# Remove credentials
rm -f .env terraform.tfvars

# Remove cached data
rm -rf .terraform/
rm -f .terraform.lock.hcl
```

## Common Errors & Fixes

| Error | Fix |
|-------|-----|
| `Error: Access Denied` | Run `aws configure` |
| `Error: name_description is not expected` | Use `description` not `name_description` |
| `Failed to connect to API` | Wait 2-3 minutes for service to start |
| `Connection refused (port 3000)` | Check `sudo systemctl status caller-worker` |
| `Module not found (Python)` | SSH and run `pip install -r requirements.txt` |
| `ERESOLVE unable to resolve` | Run `npm install --legacy-peer-deps` |
| `Permission denied` | Run `sudo chown -R root /opt/alchemyst` |

## URLs & Resources

- **AWS Console**: https://console.aws.amazon.com
- **AWS EC2**: https://console.aws.amazon.com/ec2
- **AWS VPC**: https://console.aws.amazon.com/vpc
- **Terraform Docs**: https://www.terraform.io/docs
- **AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws

## Files to Review

| File | Purpose |
|------|---------|
| README.md | Start here - overview and quick start |
| infrastructure/main.tf | VPC, subnets, instances, security groups |
| infrastructure/variables.tf | Customizable variables |
| infrastructure/outputs.tf | Output values (IPs, endpoints) |
| deploy/*.sh | Instance initialization scripts |
| docs/ARCHITECTURE.md | Detailed network and system design |
| docs/DEPLOYMENT.md | Step-by-step deployment guide |
| docs/TROUBLESHOOTING.md | Debugging and issues |
| validate-deployment.sh | Verification script |

## Essential Information

- **Deployment Time**: 3-5 minutes
- **Service Init**: 2-3 minutes
- **Total Setup**: ~15 minutes
- **First Inference**: 30-60 seconds (model loading)
- **Inference Latency**: 2-5 seconds
- **Estimated Cost**: $30-45/month (within AWS free tier)
- **API Endpoint**: `http://<public-ip>:3111/v1/chat/completions`
- **SSH CIDR**: Restrict to your IP in production
