output "aws_ecr_repository" {
  description = "Prepared AWS ECR repos"
  value       = aws_ecr_repository.this
}

# FIXME: kustomize manager relies on it, rework it later
output "images_data" {
  description = "internal state for images data"
  value       = local.images_data
}
