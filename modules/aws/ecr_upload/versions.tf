terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.20"
    }
    skopeo = {
      source  = "abergmeier/skopeo"
      version = "0.0.4"
    }
  }
}
