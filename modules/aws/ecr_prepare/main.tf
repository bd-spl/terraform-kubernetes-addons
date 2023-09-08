locals {
  default_tag = {
    tag = "latest"
  }

  images_data = {
    for _, item in yamldecode(file("${path.module}/helm-dependencies.yaml"))["dependencies"] :
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
            lookup(v, "source", "") == "" ? v.name[keys(v.name)[0]] : replace(
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
          helm_managed        = lookup(item, "repository", "") != ""
          source_provided     = lookup(v, "source", "") != ""
          src                 = try(v.name.repository, "")
          manager             = lookup(v, "manager", "helm")
          rewrite_values = {
            # tag overrides - only set helm values for explicit tags, not the 'latest' fallback for unset tags
            tag = length(lookup(v, "ver", {})) == 0 ? {} : {
              name  = "${k}.${keys(v.ver)[0]}"
              value = v.ver[keys(v.ver)[0]]
            }
            # NOTE: empty value means cannot rewrite registry/name's URI-source, until the prepared ECR repo url and name become known
            image = {
              name = "${k}.${keys(v.name)[0]}"
              # when prepared a ECR repo, the name value always needs a rewrite
              value = lookup(v, "ecr_prepare_images", true) ? "" : v.name[keys(v.name)[0]]
              tail = length(
                split(
                  ":", lookup(v, "source", "") == "" ? v.name[keys(v.name)[0]] : replace(
                  v.name[keys(v.name)[0]], "${v.source}/", "")
                )
              ) == 1 ? "" : ":${split(":", v.name[keys(v.name)[0]])[length(v.name[keys(v.name)[0]]) - 1]}"
            }
            registry = length(lookup(v, "registry", {})) == 0 ? {} : {
              name  = "${k}.${keys(v.registry)[0]}"
              value = lookup(v, "ecr_prepare_images", true) ? "" : v.registry[keys(v.registry)[0]]
            }
          }
          } if(
          lookup(v, "name", "") != "" &&
          (length(lookup(v, "registry", {})) > 0 || lookup(v, "source", "") != "")
        )
      }
    } if(length(lookup(item, "containers", {})) > 0)
  }

  ecr_names       = { for k, v in values(local.images_data)[*]["containers"] : k => keys(v) }
  ecr_raw_data    = { for k, v in values(local.images_data)[*]["containers"] : k => values(v) }
  ecr_map         = zipmap(flatten(values(local.ecr_names)), flatten(values(local.ecr_raw_data)))
  ecr_map_reduced = { for k, v in local.ecr_map : k => v... if try(v.ecr_prepare_images, false) }
  # FIXME: Serialize ecr_repos output to omit a complex type spec for its input var of the ecr_upload module
  ecr_repos = {
    for c, v in local.ecr_map_reduced :
    # omit the middle part (e.g. in helm values) off the generated ECR repo names for brevity reasons
    # this also deduplicates repo names, if the same repo is required in multiple places (different Helm values, for example)
    "${split(".", c)[0]}.${split(".", c)[2]}" => jsonencode(v[0])...
  }
}

resource "local_file" "ecr_repos_names" {
  count    = length(local.ecr_repos) > 0 ? 1 : 0
  content  = format("%s\n", join("\n", keys(local.ecr_repos)))
  filename = "${path.module}/ecr_repos_names.txt"
}

data "external" "check_ecr_exists" {
  count = length(local.ecr_repos) > 0 ? 1 : 0
  program = [
    "${path.module}/check_ecr_exists.sh",
    data.aws_region.current.name,
    "${path.module}/ecr_repos_names.txt",
    var.shared_ecr_kms_key
  ]

  depends_on = [
    local_file.ecr_repos_names
  ]
}
