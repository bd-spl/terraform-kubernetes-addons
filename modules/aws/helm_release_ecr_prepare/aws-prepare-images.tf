# FIXME: make it the addon specific instead of global.
# That should remove the need in custom terraform -target skopeo.this calls, whenever adding a new addon.
locals {
  helm_dependencies = var.helm_dependencies
  default_tag = {
    tag = "latest"
  }
  # NOTE: image data can inlcude registry and/or tag, which will be handled properly
  # FIXME: make it containing the addon specific containers images data instead of global data for all addons defined in helm_dependencies.yaml
  images_data = {
    for _, item in local.helm_dependencies :
    item.name => {
      # contains a list of {uniq_config_path => {src_reigstry:..., parsed_tag:..., ...}} entries
      containers = {
        # NOTE: becaue we cannot use uuid func (https://github.com/hashicorp/terraform/issues/30838),
        # compose uniq keys with logical fields: <addon>.<helm_value>.<shortreponame>, like:
        # ingress-nginx.controller_admissionWebhooks_patch_image_image.ingress-nginx/kube-webhook-certgen
        # for images requested to be prepared in ECR, the last field goes into repo url as a repo name
        for k, v in item.containers :
        format("%s.%s.%s",
          # we use "." as a logical field name separator, do not confuse it with dots in logical data fields
          replace(item.name, ".", "_"),
          replace("${k}_${keys(v.name)[0]}", ".", "_"),
          # strip source-URI/tag off the images names
          replace(
            lookup(v, "source", null) == null ? v.name[keys(v.name)[0]] : replace(
              v.name[keys(v.name)[0]], "${v.source}/", ""
            ),
            ":${try(v.ver, local.default_tag)[keys(try(v.ver, local.default_tag))[0]]}", ""
          )
          ) => {
          ecr_prepare_images  = try(v.ecr_prepare_images, var.ecr_prepare_images)
          src_reigstry        = try(v.source, v.registry[keys(v.registry)[0]])
          parsed_tag          = try(v.ver, local.default_tag)[keys(try(v.ver, local.default_tag))[0]]
          ecr_kms_key         = try(v.ecr_kms_key, var.ecr_kms_key)
          ecr_encryption_type = try(v.ecr_encryption_type, var.ecr_encryption_type)
          ecr_scan_on_push    = try(v.ecr_scan_on_push, var.ecr_scan_on_push)
          ecr_immutable_tag   = try(v.ecr_immutable_tag, var.ecr_immutable_tag)
          helm_managed        = lookup(item, "repository", null) != null
          source_provided     = lookup(v, "source", null) != null
          src                 = try(v.name.repository, null)
          manager             = lookup(v, "manager", "helm")
          rewrite_values = {
            # tag overrides - only set helm values for explicit tags, not the 'latest' fallback for unset tags
            tag = lookup(v, "ver", null) == null ? null : {
              name  = "${k}.${keys(v.ver)[0]}"
              value = v.ver[keys(v.ver)[0]]
            }
            # NOTE: value=null when cannot rewrite registry/name's URI-source, until the prepared ECR repo url and name become known
            image = {
              name = "${k}.${keys(v.name)[0]}"
              # when prepared a ECR repo, the name value always needs a rewrite
              value = lookup(v, "ecr_prepare_images", true) ? null : v.name[keys(v.name)[0]]
              tail = length(
                split(
                  ":", lookup(v, "source", null) == null ? v.name[keys(v.name)[0]] : replace(
                  v.name[keys(v.name)[0]], "${v.source}/", "")
                )
              ) == 1 ? "" : ":${split(":", v.name[keys(v.name)[0]])[length(v.name[keys(v.name)[0]]) - 1]}"
            }
            registry = lookup(v, "registry", null) == null ? null : {
              name  = "${k}.${keys(v.registry)[0]}"
              value = lookup(v, "ecr_prepare_images", true) ? null : v.registry[keys(v.registry)[0]]
            }
          }
          } if(
          lookup(v, "name", null) != null &&
          (lookup(v, "registry", null) != null || lookup(v, "source", null) != null)
        )
      }
    } if(lookup(item, "containers", null) != null)
  }

  ecr_names = { for k, v in values(local.images_data)[*]["containers"] : k => keys(v) }
  ecr_data  = { for k, v in values(local.images_data)[*]["containers"] : k => values(v) }
  ecr_map   = zipmap(flatten(values(local.ecr_names)), flatten(values(local.ecr_data)))
}

# Prepare ECR repos for dependencies' images
resource "aws_ecr_repository" "this" {
  for_each = {
    for c, v in local.ecr_map :
    # omit the middle part (helm value path) off repo names for brevity reasons
    "${split(".", c)[0]}.${split(".", c)[2]}" => v... if v.ecr_prepare_images
  }
  name                 = each.key
  image_tag_mutability = each.value[0].ecr_immutable_tag ? "IMMUTABLE" : "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = each.value[0].ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value[0].ecr_encryption_type
    kms_key         = each.value[0].ecr_encryption_type == "KMS" ? each.value[0].ecr_kms_key : null
  }

  tags = var.ecr_tags
}

# Push images from public source to ECR repos
resource "skopeo_copy" "this" {
  for_each = {
    for c, v in local.ecr_map :
    "${split(".", c)[0]}.${split(".", c)[2]}" => v... if v.ecr_prepare_images
  }
  source_image      = "docker://${each.value[0].src_reigstry}/${split(".", each.key)[1]}:${each.value[0].parsed_tag}"
  destination_image = "docker://${try(aws_ecr_repository.this[each.key].repository_url, "UNKNOWN")}:${each.value[0].parsed_tag}"
  keep_image        = true

  depends_on = [
    aws_ecr_repository.this
  ]
}
