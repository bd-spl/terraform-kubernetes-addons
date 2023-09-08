resource "helm_release" "this" {
  count                 = var.enabled ? 1 : 0
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
  values                = var.values

  # NOTE: No data type resource for helm_release available yet. So wrapping the resource in-place
  dynamic "set" {
    for_each = {
      # FIXME: this var should be instead internally consumed from aws-prepare-images.tf locals, or other datasources
      for c, v in local.images_data :
      c => v if v.rewrite_values.tag != null
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(var.containers_versions[set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = local.images_data
    content {
      name = set.value.rewrite_values.image.name
      value = set.value.ecr_prepare_images && set.value.source_provided ? "${
        try(aws_ecr_repository.this[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")}${set.value.rewrite_values.image.tail
        }" : set.value.ecr_prepare_images ? try(
        aws_ecr_repository.this[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].name, ""
      ) : set.value.rewrite_values.image.value
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.images_data :
      c => v if v.rewrite_values.registry != null
    }
    content {
      name = set.value.rewrite_values.registry.name
      # when unset, it should be replaced with the one prepared on ECR
      value = set.value.rewrite_values.registry.value != null ? set.value.rewrite_values.registry.value : split(
        "/", try(aws_ecr_repository.this[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")
      )[0]
    }
  }

  dynamic "set_sensitive" {
    for_each = var.set_sensitive
    content {
      name  = set_sensitive.value.name
      value = set_sensitive.value.value
      type  = set_sensitive.value.type
    }
  }

  namespace = var.namespace
}
