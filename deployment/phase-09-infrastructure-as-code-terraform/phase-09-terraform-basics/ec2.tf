resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    db_password    = var.db_password
    backend_image  = "${var.dockerhub_user}/launchboard-backend:${var.image_tag}"
    frontend_image = "${var.dockerhub_user}/launchboard-frontend:${var.image_tag}"
  })

  tags = {
    Name = "launchboard-phase-9-basics"
  }
}
