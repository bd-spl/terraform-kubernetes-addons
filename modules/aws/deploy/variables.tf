variable "helm_deploy" {
  description = "Whether to deploy with Helm manager"
  type        = bool
  default     = true
}

variable "images_data" {
  description = "Containers images data from ECR prepare module for the target addon"
  type        = map(any)
  default     = {}
}

variable "images_repos" {
  description = "Containers repos data from ECR upload module for the target addon"
  type        = map(any)
  default     = {}
}

variable "containers_versions" {
  description = "Containers images versions to use with the target addon deployment"
  type        = map(any)
  default     = {}
}

## Arguments for Kustomize manager
variable "kustomizations" {
  description = "kustomizations for the target addon"
  type        = map(any)
  default     = {}
}

variable "kustomize_external" {
  description = "Apply with Kustomize or kubectl -k"
  type        = bool
  default     = false
}

variable "kustomize_resources" {
  description = "kustomization resources for the target addon"
  type        = list(any)
  default     = []
}

variable "kustomize_resources_manifests_version" {
  description = "the target addon's manifests versions to be used as kustomize resources"
  type        = string
  default     = null
}

variable "kustomizations_images_map" {
  description = "containers images mappings for the target addon to kustomize it after the paths get rewritten for ECR"
  type        = map(any)
  default     = {}
}

## Arguments for Extra manager
variable "extra_tpl" {
  description = "the target addon's extra values template to override containers images after the paths get rewritten for ECR"
  type        = map(any)
  default     = {}
}

variable "extra_values" {
  description = "extra values (YAML as text) to merge it with the given Helm values"
  type        = string
  default     = ""
}

## Arguments for Helm manager

# Those below are the standard arguments of helm_release, look for details at the source, and keep them synced here
variable "repository" {
  type    = string
  default = null
}

variable "name" {
  type    = string
  default = null
}

variable "namespace" {
  type    = string
  default = null
}

variable "chart" {
  type    = string
  default = null
}

variable "chart_version" {
  type    = string
  default = null
}

variable "timeout" {
  type    = number
  default = null
}

variable "force_update" {
  type    = bool
  default = null
}

variable "recreate_pods" {
  type    = bool
  default = null
}

variable "wait" {
  type    = bool
  default = null
}

variable "atomic" {
  type    = bool
  default = null
}

variable "cleanup_on_fail" {
  type    = bool
  default = null
}

variable "dependency_update" {
  type    = bool
  default = null
}

variable "disable_crd_hooks" {
  type    = bool
  default = null
}

variable "disable_webhooks" {
  type    = bool
  default = null
}

variable "render_subchart_notes" {
  type    = bool
  default = null
}

variable "replace" {
  type    = bool
  default = null
}

variable "reset_values" {
  type    = bool
  default = null
}

variable "reuse_values" {
  type    = bool
  default = null
}

variable "skip_crds" {
  type    = bool
  default = null
}

variable "verify" {
  type    = bool
  default = null
}

variable "values" {
  type    = list(any)
  default = null
}

variable "set_sensitive" {
  type    = list(any)
  default = []
}
