variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used by the instance to reach ECR and SSM)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for app servers"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs the ASG launches instances into"
  type        = list(string)
}

variable "app_sg_id" {
  description = "Security group ID for app servers"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the ASG registers instances with"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name, used as the CORS origin"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry hostname"
  type        = string
}

variable "backend_image" {
  description = "Full backend image URL including tag"
  type        = string
}

variable "frontend_image" {
  description = "Full frontend image URL including tag"
  type        = string
}

variable "db_endpoint" {
  description = "RDS endpoint in address:port form"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
}

variable "db_password_ssm_name" {
  description = "Name of the SSM parameter holding the DB password"
  type        = string
}

variable "db_password_ssm_arn" {
  description = "ARN of the SSM parameter holding the DB password"
  type        = string
}

variable "asg_desired_capacity" {
  description = "Number of app servers to run"
  type        = number
}

variable "asg_min_size" {
  description = "Minimum number of app servers"
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of app servers"
  type        = number
}
