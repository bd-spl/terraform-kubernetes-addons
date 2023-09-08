variable "enabled" {
  description = "Whether to deploy the requested Helm release name, or not"
  type        = bool
  default     = true
}

# Standard arguments of helm_release, look for details at the source
variable "repository" {
  type = string
}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "chart" {
  type = string
}

variable "chart_version" {
  type = string
}

variable "timeout" {
  type = number
}

variable "force_update" {
  type = bool
}

variable "recreate_pods" {
  type = bool
}

variable "wait" {
  type = bool
}

variable "atomic" {
  type = bool
}

variable "cleanup_on_fail" {
  type = bool
}

variable "dependency_update" {
  type = bool
}

variable "disable_crd_hooks" {
  type = bool
}

variable "disable_webhooks" {
  type = bool
}

variable "render_subchart_notes" {
  type = bool
}

variable "replace" {
  type = bool
}

variable "reset_values" {
  type = bool
}

variable "reuse_values" {
  type = bool
}

variable "skip_crds" {
  type = bool
}

variable "verify" {
  type = bool
}

variable "values" {
  type = list(any)
}

variable "set_sensitive" {
  type    = list(any)
  default = []
}

# Variables that control the AWS ECR prepare images process
variable "helm_dependencies" {
  description = "Containers data for the helm resource to prepare ECR images for"
  type        = map(any)
  default     = {}
}
variable "containers_versions" {
  type        = map(any)
  description = "Containers images versions override it in `helm_dependencies`"
  default     = {}
}

variable "ecr_prepare_images" {
  description = "Prepare containers images for addons and store it in ECR"
  type        = bool
  default     = false
}

variable "ecr_immutable_tag" {
  description = "Use immutable tags for ECR images"
  type        = bool
  default     = false
}

variable "ecr_scan_on_push" {
  description = "Scan prepared ECR images on push"
  type        = bool
  default     = false
}

variable "ecr_encryption_type" {
  description = "Encryption type for ECR images"
  type        = string
  default     = "AES256"
}

variable "ecr_kms_key" {
  description = "Preconfigured KMS key arn to encrypt ECR images"
  type        = string
  default     = null
}
variable "ecr_tags" {
  description = "Tags to apply for ECR registry resources (overwrites default provider tags)"
  type        = any
  default     = {}
}
