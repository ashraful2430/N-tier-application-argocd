output "public_ip" {
  description = "Public IP of the app server"
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL to open in the browser"
  value       = "http://${aws_instance.app.public_ip}"
}

output "ssh_command" {
  description = "Command to SSH into the app server"
  value       = "ssh -i YOUR_KEY.pem ubuntu@${aws_instance.app.public_ip}"
}
