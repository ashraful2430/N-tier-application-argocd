variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "launchboard-phase-14"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for app servers (pull-only, no builds)"
  type        = string
  default     = "t3.small"
}

variable "asg_desired_capacity" {
  description = "Number of app servers to run"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum number of app servers"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of app servers"
  type        = number
  default     = 4
}

variable "image_tag" {
  description = "Tag of the app images in ECR"
  type        = string
  default     = "phase-14"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "launchboard"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "launchboard_user"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}
