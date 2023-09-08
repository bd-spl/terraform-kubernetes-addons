variable "check_ecr_exists" {
  description = "Results of ECR repos existance check from ECR prepare module"
  type        = map(any)
  default     = {}
}

variable "ecr_repos" {
  description = "ECR repos data prepared by ECR module"
  type        = map(any)
  default     = {}
}

variable "ecr_force_delete" {
  description = "Force delete ECR repos (this doesn't work, and AWS provider cannot idempotently ensure it neither)"
  type        = bool
  default     = false
}

variable "ecr_tags" {
  description = "ECR repos tags to apply for newly created repos (cannot change tags for already existing repos)"
  type        = map(any)
  default     = {}
}
