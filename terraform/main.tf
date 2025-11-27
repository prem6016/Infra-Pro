terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

# Optionally find latest Amazon Linux 2 AMI if user did not set ami_id
data "aws_ami" "amazon_linux_2" {
  count = var.ami_id == "" ? 1 : 0

  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

# Key pair: upload the public key from repo
resource "aws_key_pair" "dev_key" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# Networking
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "${var.instance_name}-vpc" }
}

resource "aws_subnet" "dev_subnet" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.instance_name}-subnet" }
}

resource "aws_internet_gateway" "dev_gw" {
  vpc_id = aws_vpc.dev_vpc.id
  tags   = { Name = "${var.instance_name}-igw" }
}

resource "aws_route_table" "dev_rt" {
  vpc_id = aws_vpc.dev_vpc.id
  tags   = { Name = "${var.instance_name}-rt" }
}

resource "aws_route" "internet_route" {
  route_table_id         = aws_route_table.dev_rt.id
  gateway_id             = aws_internet_gateway.dev_gw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "dev_rt_assoc" {
  subnet_id      = aws_subnet.dev_subnet.id
  route_table_id = aws_route_table.dev_rt.id
}

# Security Group: allow SSH (restrict via variable)
resource "aws_security_group" "dev_sg" {
  name        = "${var.instance_name}-sg"
  description = "Security group for developer VM"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # allow common egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.instance_name}-sg" }
}

# EC2 instance
resource "aws_instance" "dev_vm" {
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2[0].id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.dev_subnet.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.dev_key.key_name
  vpc_security_group_ids      = [aws_security_group.dev_sg.id]

  tags = {
    Name        = var.instance_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  # Ensure networking resources are created first
  depends_on = [
    aws_route_table_association.dev_rt_assoc
  ]

  # NOTE: Do not use local-exec provisioners for long-running config; Jenkins will run Ansible.
}

