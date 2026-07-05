data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "read_db_password" {
  name = "${var.project_name}-read-db-password"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = var.db_password_ssm_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = var.instance_type

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
    aws_region           = var.aws_region
    ecr_registry         = var.ecr_registry
    backend_image        = var.backend_image
    frontend_image       = var.frontend_image
    db_endpoint          = var.db_endpoint
    db_name              = var.db_name
    db_username          = var.db_username
    db_password_ssm_name = var.db_password_ssm_name
    alb_dns_name         = var.alb_dns_name
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-app"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.target_group_arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}
