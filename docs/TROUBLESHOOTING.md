# Troubleshooting Guide

## Pre-Deployment

### Terraform Issues

#### Error: "Access Denied" when running terraform apply

**Cause**: AWS credentials not configured properly

**Solution**:
```bash
# Configure AWS CLI
aws configure

# Check credentials
aws sts get-caller-identity

# Verify credentials work
aws ec2 describe-regions
```

#### Error: "name_description is not expected"

**Cause**: Typo in security group argument

**Solution**: Security groups use `description`, not `name_description`

#### Error: "Could not read password policy"

**Cause**: IAM permissions insufficient

**Solution**: Ensure your IAM user has at least these permissions:
- `ec2:*`
- `iam:CreateRole`, `iam:GetRole`, `iam:GetInstanceProfile`
- `iam:CreateInstanceProfile`, `iam:AddRoleToInstanceProfile`

---

## Deployment

### EC2 Instances

#### Instances not launching

**Check**:
1. AMI is available in region: `aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"`
2. Instance type available: `aws ec2 describe-instance-types --instance-types t3.small`
3. Subnet has available IPs: Check VPC in AWS console

**Solution**:
```bash
# Verify instances are running
aws ec2 describe-instances --filters "Name=tag:Project,Values=AlchemystAI"

# Get instance details
terraform state show aws_instance.api_gateway
```

#### Instances in "pending" state for >5 minutes

**Cause**: Usually indicates an issue with the user data script

**Solution**:
```bash
# SSH into instance
ssh -i key.pem ec2-user@<public-ip>

# Check system logs
curl http://169.254.169.254/latest/log

# Check cloud-init logs
cat /var/log/cloud-init-output.log
cat /var/log/cloud-init.log

# Check system journal
journalctl -n 50
```

---

## Post-Deployment

### Services Not Running

#### Service failed to start

**Check service status**:
```bash
# SSH to instance
ssh -i key.pem ubuntu@<instance-ip>

# Check service status
sudo systemctl status caller-worker
sudo systemctl status inference-worker

# View detailed logs
sudo journalctl -u caller-worker -n 100
sudo journalctl -u inference-worker -n 100

# Try starting manually
sudo systemctl restart caller-worker
sudo systemctl restart inference-worker
```

#### Common service errors

**Error: "No such file or directory"**
- Working directory doesn't exist
- Check: `ls -la /opt/alchemyst/`
- Fix: Create directory or fix path in systemd unit

**Error: "Module not found" (Python)**
- Dependencies not installed
- Check: `pip list` in venv
- Fix: Reinstall: `source /opt/alchemyst/venv/bin/activate && pip install -r requirements.txt`

**Error: "npm ERR! ERESOLVE unable to resolve dependency tree"**
- Node dependency conflict
- Check: Package.json versions
- Fix: `npm install --legacy-peer-deps`

**Error: Permission denied**
- File permissions incorrect
- Fix: `sudo chown -R root:root /opt/alchemyst && sudo chmod -R 755 /opt/alchemyst`

### Network Connectivity

#### API endpoint not responding

**Check**:
1. Instance is running and has public IP
2. Security group allows port 3111 (HTTP) or 49134 (iii engine)
3. Service is listening on port 3111 (HTTP) or 49134 (iii engine)

**Troubleshoot**:
```bash
# Get public IP
API_IP=$(terraform output -raw api_gateway_public_ip)

# Test connectivity (from local machine)
curl -v http://$API_IP:3111/

# If no response, SSH to instance
ssh -i key.pem ubuntu@$API_IP

# Check if service is listening
sudo netstat -tlnp | grep -E '3111|49134'
sudo ss -tlnp | grep -E '3111|49134'

# Check firewall rules
sudo ufw status

# Test service locally
curl -v http://localhost:3111/

# Check security groups
aws ec2 describe-security-groups --group-ids <sg-id>
```

#### Workers can't reach inference worker

**Check**:
1. Security groups allow traffic between subnets
2. Route tables have correct routes
3. Services are running

**Troubleshoot**:
```bash
# SSH to API gateway
ssh -i key.pem ubuntu@<api-gateway-ip>

# Test connectivity to inference worker (10.0.2.4)
curl -v http://10.0.2.4:3111/

# Check routes from within API gateway
ip route
route -n

# Check security groups
aws ec2 describe-security-groups

# Test DNS resolution
nslookup 10.0.2.4
```

#### Instances can't reach internet

**Check**:
1. NAT Gateway is running
2. Route tables have NAT routes
3. Elastic IP is associated

**Troubleshoot**:
```bash
# SSH to private instance
ssh -i key.pem -J ubuntu@<api-gateway> ubuntu@<private-ip>

# Test internet connectivity
curl -v http://google.com

# Check NAT gateway status
aws ec2 describe-nat-gateways

# Check routes
ip route
route -n

# Monitor NAT gateway traffic
aws cloudwatch get-metric-statistics --namespace AWS/NatGateway \
  --metric-name BytesOutToDestination \
  --dimensions Name=NatGatewayId,Value=<nat-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### API Requests

#### curl: (7) Failed to connect

**Cause**: Can't reach API endpoint

**Solution**:
1. Verify public IP: `terraform output api_gateway_public_ip`
2. Check security group allows port 3111 (HTTP) or 49134 (iii engine) from your IP
3. Try with verbose output: `curl -v http://<ip>:3111/`

#### curl: (52) Empty reply from server

**Cause**: Service crashed or not responding

**Solution**:
```bash
# SSH to instance
ssh -i key.pem ubuntu@<api-ip>

# Check service status
sudo systemctl status caller-worker

# Restart service
sudo systemctl restart caller-worker

# View recent logs
sudo journalctl -u caller-worker -n 50
```

#### HTTP 500 Error

**Cause**: Internal server error in the service

**Check**:
```bash
# SSH to API gateway
ssh -i key.pem ubuntu@<api-ip>

# View detailed logs
sudo journalctl -u caller-worker -f

# Check if inference worker is reachable
curl -v http://10.0.2.4:3111/

# Check memory/CPU
free -h
top -n 1
```

#### Inference timeout (>30 seconds)

**Cause**: Model loading or inference is slow

**Solution**:
1. First inference is slower (model loading)
2. Check instance type has enough CPU
3. Monitor logs: `sudo journalctl -u inference-worker -f`
4. Consider upgrading instance type

### Resource Cleanup

#### Cannot destroy infrastructure

**Error**: "resource is in use"

**Solution**:
```bash
# Force destroy (WARNING: will delete everything)
terraform destroy -auto-approve

# Check if instances were created outside Terraform
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# Delete manually if needed
aws ec2 terminate-instances --instance-ids <id>
aws ec2 delete-security-group --group-id <sg-id>
aws ec2 release-address --allocation-id <eip-id>
```

---

## Performance Tuning

### Slow Inference

**Causes**:
1. First request takes longer (model loading)
2. Instance type too small
3. Multiple concurrent requests

**Solutions**:
```bash
# Monitor inference latency
sudo journalctl -u inference-worker | grep "inference time"

# Upgrade instance type
variable "worker_instance_type" {
  default = "t3.medium"  # From t3.small
}

# Implement request batching (in application code)
# Implement caching for repeated queries
# Add Redis: resources/aws_elasticache_cluster.tf
```

### High Memory Usage

**Check**:
```bash
# SSH to instance
ssh -i key.pem ubuntu@<ip>

# Monitor memory
free -h
vmstat 1 5

# Check memory-intensive processes
ps aux --sort=-%mem | head -5
```

**Solutions**:
1. Increase instance type (more RAM)
2. Add swap space: `sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile`
3. Optimize application code
4. Reduce model precision (quantization)

### High CPU Usage

**Check**:
```bash
top -n 1
mpstat 1 5

# Check which processes consume CPU
ps aux --sort=-%cpu | head -5
```

**Solutions**:
1. Increase instance CPU: t3.medium → t3.large
2. Implement request queuing
3. Reduce concurrent requests
4. Optimize model/code

---

## Debugging Techniques

### Enable verbose logging

**For Python (inference-worker)**:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)
logger.debug("Starting inference...")
```

**For Node.js (caller-worker)**:
```bash
# In systemd unit
Environment="DEBUG=*"
```

### Capture full request/response

```bash
# Enable tcpdump on instance
sudo tcpdump -i any -n port 3111 (HTTP) or 49134 (iii engine) -w /tmp/capture.pcap

# Download and analyze
scp ubuntu@<ip>:/tmp/capture.pcap .
wireshark capture.pcap
```

### Monitor system metrics

```bash
# Real-time monitoring
htop

# System info
uname -a
lsb_release -a
df -h
mount

# Network info
ip addr
ip route
netstat -s
```

---

## Common Issues Checklist

- [ ] AWS credentials configured: `aws sts get-caller-identity`
- [ ] Region set correctly: `terraform output | grep region`
- [ ] Instances running: `aws ec2 describe-instances`
- [ ] Security groups created: `aws ec2 describe-security-groups`
- [ ] Services started: `sudo systemctl status <service>`
- [ ] Logs checked: `sudo journalctl -n 50`
- [ ] Ports listening: `sudo netstat -tlnp | grep -E '3111|49134'`
- [ ] Network accessible: `curl -v http://<ip>:3111/`
- [ ] Dependencies installed: `pip list`, `npm list`
- [ ] Disk space available: `df -h`
- [ ] Memory available: `free -h`
- [ ] CPU not maxed: `top`
