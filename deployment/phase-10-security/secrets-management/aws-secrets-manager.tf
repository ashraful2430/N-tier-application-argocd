variable "db_password" { description = "Database password stored in Secrets Manager." type = string sensitive = true }
resource "aws_secretsmanager_secret" "db_password" { name = "devops-launchboard/db-password" description = "PostgreSQL password for DevOps LaunchBoard" tags = var.tags }
resource "aws_secretsmanager_secret_version" "db_password" { secret_id = aws_secretsmanager_secret.db_password.id secret_string = var.db_password }
