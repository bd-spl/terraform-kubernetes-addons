terraform {
  required_version = ">= 0.15"
  required_providers {
    aws        = ">= 4.22.0"
    azurerm    = "~> 3.0"
    helm       = "~> 2.0"
    kubernetes = "~> 2.0, != 2.12"
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 0.25"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    skopeo = {
      source  = "abergmeier/skopeo"
      version = "0.0.4"
    }
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3"
    }
  }
}
