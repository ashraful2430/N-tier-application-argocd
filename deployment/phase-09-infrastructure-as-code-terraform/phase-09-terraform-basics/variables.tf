variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the app server"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form (x.x.x.x/32) for SSH access"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL password injected into the app .env file"
  type        = string
  sensitive   = true
}
