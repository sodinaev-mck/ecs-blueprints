terraform {
  backend "s3" {
    encrypt        = true
    region         = "us-east-1"
    bucket         = "terraform-state-us-east-1-380377549567"
    key            = "ecs-blueprints/backstage/terraform.tfstate"
    dynamodb_table = "terraform-state-locks"
  }
}