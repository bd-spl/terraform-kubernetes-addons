output "images_data" {
  description = "The addons' containers images data prepared for the deploy module instances"
  value       = local.images_data
}

output "ecr_repos" {
  description = "Data required by the upload module to deploy AWS ECR repos and populate conainers images layers"
  # NOTE: we only need a 1st item as the other ones contain the same repo info for other places, where this same ECR repo is used
  value = { for k, v in local.ecr_repos : k => v[0] }
}

output "check_ecr_exists" {
  description = "Existance/shared check results for ECR repos prepared for the ECR upload module"
  value       = jsondecode(data.external.check_ecr_exists[0].result.result)
}
