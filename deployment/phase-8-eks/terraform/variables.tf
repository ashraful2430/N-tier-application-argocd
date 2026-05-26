variable "aws_region" { description = "AWS Region." type = string default = "[REGION]" }
variable "project_name" { description = "Project slug." type = string default = "devops-launchboard" }
variable "vpc_id" { description = "Existing VPC ID." type = string }
variable "private_subnet_ids" { description = "Private subnet IDs." type = list(string) }
variable "public_subnet_ids" { description = "Public subnet IDs." type = list(string) }
variable "node_instance_types" { description = "Managed node instance types." type = list(string) default = ["t3.medium"] }
variable "desired_size" { description = "Desired worker count." type = number default = 2 }
variable "tags" { description = "Cost tags." type = map(string) default = { Project = "devops-launchboard", Environment = "training", Owner = "Ashraful Islam Ashik" } }
