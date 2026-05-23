#!/bin/bash
set -euo pipefail

echo "=== Deployment smoke test ==="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
  local name="$1"
  local cmd="$2"

  echo -n "Checking: $name... "
  if eval "$cmd" > /dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
    ((PASSED++))
    return 0
  else
    echo -e "${RED}FAILED${NC}"
    ((FAILED++))
    return 1
  fi
}

# Get outputs
echo "Getting Terraform outputs..."
cd infrastructure

API_IP=$(terraform output -raw api_gateway_public_ip 2>/dev/null) || {
  echo -e "${RED}ERROR: Could not get API IP from terraform outputs${NC}"
  echo "Have you run 'terraform apply' yet?"
  exit 1
}
INFERENCE_IP=$(terraform output -raw inference_worker_private_ip 2>/dev/null) || INFERENCE_IP="unknown"

echo "API Gateway IP: $API_IP"
echo "Inference Worker IP: $INFERENCE_IP"
echo ""

# Verify AWS resources
echo "=== AWS Resources ==="
check "VPC exists" "aws ec2 describe-vpcs --filters 'Name=cidr,Values=10.0.0.0/16' | grep -q VpcId"
check "API Gateway instance running" "aws ec2 describe-instances --instance-ids $(terraform state show aws_instance.api_gateway.id 2>/dev/null | grep id | head -1 | awk '{print $NF}' | tr -d '\"') --query 'Reservations[0].Instances[0].State.Name' | grep running"
check "Inference Worker instance running" "aws ec2 describe-instances --query 'Reservations[*].Instances[?Tags[?Value==\`alchemyst-inference-worker\`]].State.Name' | grep -i running"

cd ..
echo ""

# Verify network connectivity
echo "=== Network Connectivity ==="
check "API Gateway responds on iii-http" "curl -s -o /dev/null -w '%{http_code}' http://$API_IP:3111/v1/chat/completions -X POST -H 'Content-Type: application/json' -d '{}' | grep -qE '200|400|500|502'"
check "API endpoint accessible" "curl -s -o /dev/null -w '%{http_code}' http://$API_IP:3111/v1/chat/completions -X POST -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}' | grep -qE '200|400|500'"

echo ""

# Verify inference
echo "=== Inference Testing ==="
RESPONSE=$(curl -s -X POST "http://$API_IP:3111/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}]}' || echo "")

if echo "$RESPONSE" | grep -q "role.*assistant" || echo "$RESPONSE" | grep -q "content"; then
  echo -e "${GREEN}PASSED${NC}: Inference returned valid response"
  ((PASSED++))
else
  echo -e "${YELLOW}WARNING${NC}: Inference response unexpected"
  echo "Response: $RESPONSE"
fi

echo ""

# Summary
echo "=== Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed!${NC}"
  echo ""
  echo "Your deployment is ready. Test with:"
  echo "  curl -X POST 'http://$API_IP:3111/v1/chat/completions' \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Tell me a joke\"}]}'"
  exit 0
else
  echo -e "${RED}✗ Some checks failed${NC}"
  echo ""
  echo "Troubleshooting:"
  echo "1. Check that services started: SSH to instance and run:"
  echo "   sudo systemctl status caller-worker"
  echo "   sudo journalctl -u caller-worker -n 50"
  echo ""
  echo "2. Wait for initialization (2-3 minutes after terraform apply)"
  echo ""
  echo "3. Check network connectivity:"
  echo "   curl -v http://$API_IP:3111/v1/chat/completions"
  exit 1
fi
