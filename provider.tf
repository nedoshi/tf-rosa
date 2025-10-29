terraform {
  required_providers {
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
    validation = {
      source  = "tlkamp/validation"
      version = "1.1.1"
    }
  }
}

provider "rhcs" {
  # token        = var.token
  client_id    = var.client_id
  client_secret =  var.client_secret
}

provider "aws" {
  region = var.region
}