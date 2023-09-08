terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    skopeo = {
      source  = "abergmeier/skopeo"
      version = "0.0.4"
    }
  }
}
