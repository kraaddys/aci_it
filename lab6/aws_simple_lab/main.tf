terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "my-tf-state-simple-k18"    
    key     = "aws_simple_lab/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -------- EC2-инстанс --------
resource "aws_instance" "web" {
  ami           = "ami-0a6793a25df710b06"
  instance_type = "t3.micro"

  tags = {
    Name = "WebServer-${var.env}"
  }
}

# -------- S3-бакет --------
resource "aws_s3_bucket" "files" {
  bucket = "my-simple-bucket-${var.env}-k18"
}
