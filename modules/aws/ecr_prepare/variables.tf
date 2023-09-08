variable "ecr_prepare_images" {
  description = "Prepare containers images for addons and store it in ECR. This global flag can be overriden for specific containers"
  type        = bool
  default     = true
}

variable "ecr_immutable_tag" {
  description = "Use immutable tags for ECR images. This global flag can be overriden for specific containers"
  type        = bool
  default     = false
}

variable "ecr_scan_on_push" {
  description = "Scan prepared ECR images on push. This global flag can be overriden for specific containers"
  type        = bool
  default     = false
}

variable "ecr_encryption_type" {
  description = "Encryption type for ECR images. This global flag can be overriden for specific containers"
  type        = string
  default     = "AES256"
}

variable "ecr_kms_key" {
  description = "Preconfigured KMS key arn to encrypt ECR images. This global flag can be overriden for specific containers. Shared repos must use the same KMS key ARN"
  type        = string
  default     = null
}

variable "shared_ecr_kms_key" {
  description = "A KMS key ARN to identify already existing ECR repos as shared, if those match this key ARN"
  type        = string
  default     = ""
}
