

resource "aws_ecr_repository" "this" {
  for_each = {
    for k, v in var.ecr_repos : k => jsondecode(v) if !tobool(var.check_ecr_exists[k].exists)
  }

  name                 = each.key
  image_tag_mutability = each.value.ecr_immutable_tag ? "IMMUTABLE" : "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = each.value.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value.ecr_encryption_type
    kms_key         = each.value.ecr_encryption_type == "KMS" ? each.value.ecr_kms_key : null
  }

  tags = var.ecr_tags
}

# Push images from public source to ECR repos
resource "skopeo_copy" "this" {
  for_each = var.ecr_repos

  source_image = "docker://${jsondecode(each.value).src_reigstry}/${split(".", each.key)[1]}:${jsondecode(each.value).parsed_tag}"
  # If a ECR repo is not in Terraform state (becaue of known idempotency problems), make skopeo using repo URL discovered by the existence check
  destination_image = "docker://${try(aws_ecr_repository.this[each.key].repository_url, var.check_ecr_exists[each.key].repository_url)}:${jsondecode(each.value).parsed_tag}"
  keep_image        = true

  depends_on = [
    aws_ecr_repository.this
  ]
}
