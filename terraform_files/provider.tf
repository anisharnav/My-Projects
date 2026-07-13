#STEP1: DEFINE AWS VERSION
terraform {
  backend "s3" {
    bucket = "practice0526statefile"
    key    = "dev/terraform.tfstate"
    encrypt = true
    use_lockfile = "true"
    region = "us-east-1"
  }


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.35.0"
    }
  }
}
#STEP2: DEFINE THE REGION (N. Virginia)
provider "aws" {
  region = "us-east-1"
}
