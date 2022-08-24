variable "ecr_immutable_tag" {
  default = false
}
variable "ecr_scan_on_push" {
  default = false
}
variable "ecr_encryption_type" {
  default = "AES256"
}
variable "ecr_kms_key" {
  default = null
}

locals {
  default_tag = {
    tag = "latest"
  }
  # image data can inlcude registry and/or tag, which will be handled properly
  images_data = {
    for _, item in local.helm_dependencies :
    item.name => {
      containers = {
        # returns a list of {dependency.shortname => {src_reigstry:..., parsed_tag:..., ...}}
        for k, v in item.containers :
        # strip registry/tag off the images names, avoid duplicate keys by adding uuid
        format("%s.%s%s", item.name, replace(replace(v.name[keys(v.name)[0]],
          "${try(v.registry[keys(v.registry)[0]], v.source)}/", ""),
          ":${try(v.ver, local.default_tag)[keys(try(v.ver, local.default_tag))[0]]}", ""),
          try(v.ecr_prepare_images, true) ? "" : "_${uuid()}"
          ) => {
          ecr_prepare_images  = try(v.ecr_prepare_images, true)
          src_reigstry        = try(v.source, v.registry[keys(v.registry)[0]])
          parsed_tag          = try(v.ver, local.default_tag)[keys(try(v.ver, local.default_tag))[0]]
          ecr_kms_key         = try(v.ecr_kms_key, var.ecr_kms_key)
          ecr_encryption_type = try(v.ecr_encryption_type, var.ecr_encryption_type)
          ecr_scan_on_push    = try(v.ecr_scan_on_push, var.ecr_scan_on_push)
          ecr_immutable_tag   = try(v.ecr_immutable_tag, var.ecr_immutable_tag)
          helm_values = {
            # tag overrides - only set helm values for explicit tags, not the 'latest' fallback for unset tags
            tag = lookup(v, "ver", null) == null ? {} : {
              name  = "${k}.${keys(v.ver)[0]}"
              value = v.ver[keys(v.ver)[0]]
            }
            # NOTE: cannot rewrite registry/URI-source, until the prepared ECR repo url is known
            image = {
              name  = "${k}.${keys(v.name)[0]}"
              value = lookup(v, "ecr_prepare_images", true) ? null : v.name[keys(v.name)[0]]
              tail = length(split(
                ":", v.name[keys(v.name)[0]])
              ) == 1 ? "" : ":${split(":", v.name[keys(v.name)[1]])}"
            }
            registry = lookup(v, "registry", {}) == {} ? {} : {
              name  = "${k}.${keys(v.registry)[0]}"
              value = lookup(v, "ecr_prepare_images", true) ? null : v.registry[keys(v.registry)[0]]
            }
          }
          } if(
          lookup(v, "name", null) != null &&
          (lookup(v, "registry", null) != null || lookup(v, "source", null) != null)
        )
      }
    } if(lookup(item, "containers", {}) != {})
  }

  ecr_names = { for k, v in values(local.images_data)[*]["containers"] : k => keys(v) }
  ecr_data  = { for k, v in values(local.images_data)[*]["containers"] : k => values(v) }
  ecr_map   = zipmap(flatten(values(local.ecr_names)), flatten(values(local.ecr_data)))
}

# Prepare ECR repos for dependencies' images
resource "aws_ecr_repository" "this" {
  for_each             = { for c, v in local.ecr_map : c => v if v.ecr_prepare_images }
  name                 = each.key
  image_tag_mutability = each.value.ecr_immutable_tag ? "IMMUTABLE" : "MUTABLE"

  image_scanning_configuration {
    scan_on_push = each.value.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value.ecr_encryption_type
    kms_key         = each.value.ecr_encryption_type == "KMS" ? each.value.ecr_kms_key : null
  }
}

# Push images from public source to ECR repos
resource "skopeo_copy" "this" {
  for_each          = { for c, v in local.ecr_map : c => v if v.ecr_prepare_images }
  source_image      = "docker://${each.value.src_reigstry}/${split(".", each.key)[1]}:${each.value.parsed_tag}"
  destination_image = "docker://${aws_ecr_repository.this[each.key].repository_url}:${each.value.parsed_tag}"
  keep_image        = true

  depends_on = [
    aws_ecr_repository.this
  ]
}
