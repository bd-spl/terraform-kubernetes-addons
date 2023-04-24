variable "arn-partition" {
  description = "ARN partition"
  default     = ""
  type        = string
}

variable "aws" {
  description = "AWS provider customization"
  type        = any
  default     = {}
}

variable "aws-ebs-csi-driver" {
  description = "Customize aws-ebs-csi-driver helm chart, see `aws-ebs-csi-driver.tf`"
  type        = any
  default     = {}
}

variable "aws-efs-csi-driver" {
  description = "Customize aws-efs-csi-driver helm chart, see `aws-efs-csi-driver.tf`"
  type        = any
  default     = {}
}

variable "aws-for-fluent-bit" {
  description = "Customize aws-for-fluent-bit helm chart, see `aws-fluent-bit.tf`"
  type        = any
  default     = {}
}

variable "aws-load-balancer-controller" {
  description = "Customize aws-load-balancer-controller chart, see `aws-load-balancer-controller.tf` for supported values"
  type        = any
  default     = {}
}

variable "aws-node-termination-handler" {
  description = "Customize aws-node-termination-handler chart, see `aws-node-termination-handler.tf`"
  type        = any
  default     = {}
}

variable "calico" {
  description = "Customize calico helm chart, see `calico.tf`"
  type        = any
  default     = {}
}

variable "cni-metrics-helper" {
  description = "Customize cni-metrics-helper deployment, see `cni-metrics-helper.tf` for supported values"
  type        = any
  default     = {}
}

variable "eks" {
  description = "EKS cluster inputs"
  type        = any
  default     = {}
}

variable "prometheus-cloudwatch-exporter" {
  description = "Customize prometheus-cloudwatch-exporter chart, see `prometheus-cloudwatch-exporter.tf` for supported values"
  type        = any
  default     = {}
}

variable "secrets-store-csi-driver-provider-aws" {
  description = "Enable secrets-store-csi-driver-provider-aws"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Map of tags for AWS resources"
  type        = map(any)
  default     = {}
}

variable "velero" {
  description = "Customize velero chart, see `velero.tf` for supported values"
  type        = any
  default     = {}
}

variable "dex" {
  description = "Customize dex charts, see `dex.tf` for supported values"
  type        = any
  default     = {}
}

variable "cluster_client_secret" {
  description = "OAUTH login secret for Dex (staticClient) IDP OIDC provider. Must match dex[cluster_secret], if pre-created"
  default     = ""
  sensitive   = true
}

variable "ldap_user_dn" {
  description = "FreeIPA reader user DN for Dex IDP LDAP connector. Must match dex[ldap_acc_secret], if pre-created"
  default     = ""
}

variable "ldap_user_password" {
  description = "FreeIPA reader user password for Dex IDP LDAP connector. Must match dex[ldap_acc_secret], if pre-created"
  default     = ""
  sensitive   = true
}

variable "create_secrets" {
  description = "Create k8s secrets from the provided sensitive inputs, or pick already existing ones"
  default     = false
}
