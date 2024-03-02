provider "aws" {
  region = var.region
  tags = {
    Environment = var.environment_id
  }
}

terraform {
  backend "s3" {
    region         = var.region
    bucket         = "state_bucket"
    key            = "case_study_6/terraform.tfstate"
    dynamodb_table = "case_study_6"
  }
}
