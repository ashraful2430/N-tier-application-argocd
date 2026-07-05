module "network" {
  source = "./modules/network"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
}

module "database" {
  source = "./modules/database"

  project_name       = var.project_name
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.security.db_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
}

module "loadbalancer" {
  source = "./modules/loadbalancer"

  project_name      = var.project_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  aws_region           = var.aws_region
  instance_type        = var.instance_type
  private_subnet_ids   = module.network.private_subnet_ids
  app_sg_id            = module.security.app_sg_id
  target_group_arn     = module.loadbalancer.target_group_arn
  alb_dns_name         = module.loadbalancer.alb_dns_name
  ecr_registry         = local.ecr_registry
  backend_image        = local.backend_image
  frontend_image       = local.frontend_image
  db_endpoint          = module.database.db_endpoint
  db_name              = var.db_name
  db_username          = var.db_username
  db_password_ssm_name = aws_ssm_parameter.db_password.name
  db_password_ssm_arn  = aws_ssm_parameter.db_password.arn
  asg_desired_capacity = var.asg_desired_capacity
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
}
