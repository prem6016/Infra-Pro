variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "key_name" {
  type        = string
  default     = "dev-ssh-key"
  description = "Name for the AWS key pair resource"
}

variable "public_key_path" {
  type        = string
  default     = "../ssh_keys/dev_key.pub"
  description = "Path to public key file (relative to terraform/)"
}

variable "instance_name" {
  type        = string
  default     = "developer-vm"
  description = "Name tag for EC2 instance"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "Optional override AMI ID. If empty, Terraform will select latest Amazon Linux 2 AMI."
}

variable "allowed_ssh_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to SSH to instance; set to Jenkins agent IP or office CIDR in production"
}
