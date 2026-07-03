output "app_url" {
  description = "URL to open in the browser"
  value       = "http://${module.loadbalancer.alb_dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.loadbalancer.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (address:port)"
  value       = module.database.db_endpoint
}

output "ecr_backend_repository_url" {
  description = "ECR repository URL for the backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "ECR repository URL for the frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}
