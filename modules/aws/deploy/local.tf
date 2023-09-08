locals {
  # NOTE: declare vars via locals to simplify debugging the module with substituted values from tEKS modules
  containers_versions                   = var.containers_versions
  kustomize_resources_manifests_version = var.kustomize_resources_manifests_version
  kustomizations                        = var.kustomizations
  kustomizations_images_map             = var.kustomizations_images_map
  images_data                           = var.images_data
  images_repos                          = var.images_repos
  extra_tpl                             = var.extra_tpl
  extra_values                          = var.extra_values

  ## prepare data for Extra manager of the target addon
  containers_data = {
    for k, v in local.images_data.containers :
    v.rewrite_values.image.name => {
      tag = try(
        local.containers_versions[v.rewrite_values.tag.name],
        v.rewrite_values.tag.value,
        v.rewrite_values.image.tail
      )
      repo = v.ecr_prepare_images && v.source_provided ? try(
        local.images_repos.repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].repository_url, "") : v.ecr_prepare_images ? try(
        local.images_repos.repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].name, ""
      ) : v.rewrite_values.image.value
      src = v.src
    } if v.manager == "kustomize" || v.manager == "extra"
  }

  # Get variables names and values to template them in
  extra_tpl_vars = {
    for k, v in local.containers_data :
    k => {
      params = {
        "${split(".", k)[1]}-repo" = v.repo
        "${split(".", k)[1]}-tag"  = v.tag
      }
      } if lookup(
      local.extra_tpl, split(".", k)[0], null
    ) != null
  }
  extra_tpl_data = [for v in values(local.extra_tpl_vars) : v.params]

  # FIXME: workaround limitation to pass templates with vars in it (even if escaped) via the module input
  extra_tpl_fixed = [
    for i in [
      for k, v in local.extra_tpl_vars :
      { "${k}" = yamldecode(replace( # tflint-ignore: terraform_deprecated_interpolation
        replace(
          yamlencode(local.extra_tpl),
          format("$%s", keys(v.params)[0]), "$${${keys(v.params)[0]}}"
        ),
        format("$%s", keys(v.params)[1]), "$${${keys(v.params)[1]}}"
      )) }
    ] : { for k, v in i : split(".", k)[0] => v[split(".", k)[0]] }
  ]

  ## prepare data for the Kustomize manager of the target addon

  # Update kustomizations with the prepared containers images data
  kustomizations_patched = flatten([
    for k, data in local.kustomizations :
    [for v in compact(split("---", data)) :
      replace(
        yamlencode(merge(
          try(yamldecode(v), {}),
          {
            resources = lookup(
              try(yamldecode(v), {}),
              "resources",
              local.kustomize_resources_manifests_version
            )
          },
          length(lookup(try(yamldecode(v), {}), "images", {})) == 0 ? {} : {
            images = [
              for c in try(yamldecode(v).images, []) :
              {
                # Remove unique identifiers distinguishing same images used for different containers
                name = split("::", c.name)[0]
                newName = local.containers_data[
                  format(
                    "%s.%s.repository",
                    k,
                    split("::", local.kustomizations_images_map[k][c.name])[0]
                  )
                ].repo
                newTag = try(c.newTag, "") != "" ? c.newTag : local.containers_data[
                  format(
                    "%s.%s.repository",
                    k,
                    split("::", local.kustomizations_images_map[k][c.name])[0]
                  )
                ].tag
              }
            ]
          }
          )
        ),
      "$manifest_version", local.kustomize_resources_manifests_version)
    ]
  ])
}
