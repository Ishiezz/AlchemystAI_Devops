output "api_gateway_public_ip" {
  description = "Public IP of API gateway instance"
  value       = aws_instance.api_gateway.public_ip
}

output "api_gateway_private_ip" {
  description = "Private IP of API gateway instance"
  value       = aws_instance.api_gateway.private_ip
}

output "inference_worker_private_ip" {
  description = "Private IP of inference worker instance"
  value       = aws_instance.inference_worker.private_ip
}

output "caller_worker_private_ip" {
  description = "Private IP of caller worker instance"
  value       = aws_instance.caller_worker.private_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP"
  value       = aws_eip.nat.public_ip
}

output "api_endpoint" {
  description = "Public JSON HTTP API (iii-http)"
  value       = "http://${aws_instance.api_gateway.public_ip}:3111/v1/chat/completions"
}

output "iii_engine_url" {
  description = "WebSocket URL for remote workers (private subnet only)"
  value       = "ws://${aws_instance.api_gateway.private_ip}:49134"
}
