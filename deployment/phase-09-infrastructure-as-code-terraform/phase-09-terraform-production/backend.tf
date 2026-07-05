terraform {
  backend "s3" {
    bucket       = "YOUR_STATE_BUCKET_NAME"
    key          = "phase-9/terraform-production.tfstate"
    region       = "YOUR_AWS_REGION"
    use_lockfile = true
    encrypt      = true
  }
}
