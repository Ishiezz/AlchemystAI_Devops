variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "api_instance_type" {
  description = "EC2 instance type for API gateway"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for the caller worker"
  type        = string
  default     = "t3.small"
}

variable "inference_instance_type" {
  description = "EC2 instance type for inference worker (needs RAM for gemma-3-270m)"
  type        = string
  default     = "t3.medium"
}

variable "ssh_cidr" {
  description = "CIDR block allowed for SSH (restrict to your IP for security)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "inference_worker_ip" {
  description = "Private IP for inference worker (optional)"
  type        = string
  default     = ""
}

variable "caller_worker_ip" {
  description = "Private IP for caller worker (optional)"
  type        = string
  default     = ""
}
