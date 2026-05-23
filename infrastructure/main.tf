terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AlchemystAI"
      Environment = "development"
      ManagedBy   = "Terraform"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "alchemyst-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "alchemyst-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "alchemyst-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "alchemyst-private-subnet"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "alchemyst-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "alchemyst-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "alchemyst-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "alchemyst-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "api_gateway" {
  name        = "alchemyst-api-sg"
  description = "Security group for public API gateway (iii engine)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "iii-http inference API"
  }

  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
    description = "iii engine worker mesh"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
    description = "SSH debugging"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alchemyst-api-sg"
  }
}

resource "aws_security_group" "workers" {
  name        = "alchemyst-workers-sg"
  description = "Security group for private worker instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
    description     = "SSH from API gateway"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Outbound via NAT (packages, iii engine)"
  }

  tags = {
    Name = "alchemyst-workers-sg"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  bootstrap_common = file("${path.module}/../deploy/common.sh")
  iii_engine_port  = "49134"
}

resource "aws_instance" "api_gateway" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.api_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.api_gateway.id]
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/../deploy/api-gateway-init.sh.tpl", {
    common_sh = local.bootstrap_common
  }))

  tags = {
    Name = "alchemyst-api-gateway"
    Role = "api-gateway"
  }

  depends_on = [aws_nat_gateway.main]
}

resource "aws_instance" "inference_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.inference_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/../deploy/inference-worker-init.sh.tpl", {
    common_sh       = local.bootstrap_common
    iii_engine_host = aws_instance.api_gateway.private_ip
    iii_engine_port = local.iii_engine_port
  }))

  tags = {
    Name = "alchemyst-inference-worker"
    Role = "inference-worker"
  }

  depends_on = [aws_instance.api_gateway, aws_nat_gateway.main]
}

resource "aws_instance" "caller_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]

  user_data = base64encode(templatefile("${path.module}/../deploy/caller-worker-init.sh.tpl", {
    common_sh       = local.bootstrap_common
    iii_engine_host = aws_instance.api_gateway.private_ip
    iii_engine_port = local.iii_engine_port
  }))

  tags = {
    Name = "alchemyst-caller-worker"
    Role = "caller-worker"
  }

  depends_on = [aws_instance.api_gateway, aws_nat_gateway.main]
}

