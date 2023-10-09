## deploy the target addon with Kustomize, if requested
# FIXME: local_sensitive_file maybe?
resource "local_file" "kustomization" {
  for_each = length(local.kustomizations) > 0 ? zipmap(
    [for c in local.kustomizations_patched : md5(c)],
    local.kustomizations_patched
  ) : {}
  content  = each.value
  filename = "./kustomization-${each.key}/kustomization/kustomization.yaml"
}

resource "null_resource" "kustomize" {
  for_each = length(local.kustomizations) > 0 ? zipmap(
    [for c in local.kustomizations_patched : md5(c)],
    local.kustomizations_patched
  ) : {}

  triggers = {
    #kustomization = each.key
    always_run = timestamp()
  }

  # NOTE: cannot update Jobs' spec immutable container images data
  provisioner "local-exec" {
    command = <<-EOT
    ${var.kustomize_external ? "kustomize build ./kustomization-${each.key}/kustomization | kubectl apply -f -" : "kubectl apply -k ./kustomization-${each.key}/kustomization"}
  EOT
  }

  depends_on = [
    local_file.kustomization,
  ]
}

## render templates of Extra Values manager required for Helm manager
data "template_file" "extra_values_patched" {
  count    = length(local.extra_tpl_fixed) > 0 && length(local.extra_tpl_vars) > 0 ? 1 : 0
  template = yamlencode(merge(local.extra_tpl_fixed...))
  vars     = merge(local.extra_tpl_data...)
}

## deploy the target addon with Helm, merging the templated extra values
resource "helm_release" "this" {
  count                 = var.helm_deploy ? 1 : 0
  repository            = var.repository
  name                  = var.name
  chart                 = var.chart
  version               = var.chart_version
  timeout               = var.timeout
  force_update          = var.force_update
  recreate_pods         = var.recreate_pods
  wait                  = var.wait
  atomic                = var.atomic
  cleanup_on_fail       = var.cleanup_on_fail
  dependency_update     = var.dependency_update
  disable_crd_hooks     = var.disable_crd_hooks
  disable_webhooks      = var.disable_webhooks
  render_subchart_notes = var.render_subchart_notes
  replace               = var.replace
  reset_values          = var.reset_values
  reuse_values          = var.reuse_values
  skip_crds             = var.skip_crds
  verify                = var.verify
  values = [
    yamlencode(
      merge(
        try(yamldecode(local.extra_values), {}),
        try(yamldecode(data.template_file.extra_values_patched.0.rendered), {})
      )
    )
  ]

  # NOTE: No data type resource for helm_release available yet. So wrapping the resource in-place
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.containers :
      c => v if length(v.rewrite_values.tag) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.containers_versions[set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.containers :
      c => v if try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.image.name
      value = set.value.ecr_prepare_images && set.value.source_provided ? "${
        try(local.images_repos.repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")}${set.value.rewrite_values.image.tail
        }" : set.value.ecr_prepare_images ? try(
        local.images_repos.repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].name, ""
      ) : set.value.rewrite_values.image.value
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.containers :
      c => v if length(v.rewrite_values.registry) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.registry.name
      # when unset, it should be replaced with the one prepared on ECR
      value = set.value.rewrite_values.registry.value != "" ? set.value.rewrite_values.registry.value : split(
        "/", try(local.images_repos.repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")
      )[0]
    }
  }

  dynamic "set_sensitive" {
    for_each = length(var.set_sensitive) == 0 ? [] : var.set_sensitive
    content {
      name  = set_sensitive.value.name
      value = set_sensitive.value.value
      type  = try(set_sensitive.value.type, "auto") # auto or string
    }
  }

  namespace = var.namespace

  depends_on = [
    data.template_file.extra_values_patched,
    resource.null_resource.kustomize
  ]
}
