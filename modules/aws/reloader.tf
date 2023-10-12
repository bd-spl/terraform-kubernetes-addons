locals {

  reloader = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].version
      namespace              = "reloader"
      service_account_name   = "reloader"
      default_network_policy = true
      enabled                = false
      vpa_enable             = false
      vpa_only_recommend     = false
      use_deploy_module      = true
      images_data            = {}
      images_repos           = {}
      containers_versions    = {}
    },
    var.reloader
  )

  values_reloader = <<VALUES
VALUES
}

resource "kubernetes_namespace" "reloader" {
  count = local.reloader["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.reloader["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.reloader["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.reloader["namespace"]
  }
}

module "deploy_reloader" {
  count                 = local.reloader["enabled"] && local.reloader["use_deploy_module"] ? 1 : 0
  source                = "./deploy"
  images_data           = local.reloader["images_data"]
  images_repos          = local.reloader["images_repos"]
  containers_versions   = local.reloader["containers_versions"]
  repository            = local.reloader["repository"]
  name                  = local.reloader["name"]
  chart                 = local.reloader["chart"]
  chart_version         = local.reloader["chart_version"]
  timeout               = local.reloader["timeout"]
  force_update          = local.reloader["force_update"]
  recreate_pods         = local.reloader["recreate_pods"]
  wait                  = local.reloader["wait"]
  atomic                = local.reloader["atomic"]
  cleanup_on_fail       = local.reloader["cleanup_on_fail"]
  dependency_update     = local.reloader["dependency_update"]
  disable_crd_hooks     = local.reloader["disable_crd_hooks"]
  disable_webhooks      = local.reloader["disable_webhooks"]
  render_subchart_notes = local.reloader["render_subchart_notes"]
  replace               = local.reloader["replace"]
  reset_values          = local.reloader["reset_values"]
  reuse_values          = local.reloader["reuse_values"]
  skip_crds             = local.reloader["skip_crds"]
  verify                = local.reloader["verify"]
  values = [
    local.values_reloader,
    local.reloader["extra_values"]
  ]

  namespace = kubernetes_namespace.reloader.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds
  ]
}

resource "kubernetes_network_policy" "reloader_default_deny" {
  count = local.reloader["enabled"] && local.reloader["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.reloader.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.reloader.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "reloader_allow_namespace" {
  count = local.reloader["enabled"] && local.reloader["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.reloader.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.reloader.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.reloader.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "reloader_allow_monitoring" {
  count = local.reloader["enabled"] && local.reloader["default_network_policy"] && local.kube-prometheus-stack["enabled"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.reloader.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.reloader.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "8042"
        protocol = "TCP"
      }

      from {
        namespace_selector {
          match_labels = {
            "${local.labels_prefix}/component" = "monitoring"
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

# FIXME
resource "helm_release" "reloader" {
  count                 = local.reloader["enabled"] && !local.reloader["use_deploy_module"] ? 1 : 0
  repository            = local.reloader["repository"]
  name                  = local.reloader["name"]
  chart                 = local.reloader["chart"]
  version               = local.reloader["chart_version"]
  timeout               = local.reloader["timeout"]
  force_update          = local.reloader["force_update"]
  recreate_pods         = local.reloader["recreate_pods"]
  wait                  = local.reloader["wait"]
  atomic                = local.reloader["atomic"]
  cleanup_on_fail       = local.reloader["cleanup_on_fail"]
  dependency_update     = local.reloader["dependency_update"]
  disable_crd_hooks     = local.reloader["disable_crd_hooks"]
  disable_webhooks      = local.reloader["disable_webhooks"]
  render_subchart_notes = local.reloader["render_subchart_notes"]
  replace               = local.reloader["replace"]
  reset_values          = local.reloader["reset_values"]
  reuse_values          = local.reloader["reuse_values"]
  skip_crds             = local.reloader["skip_crds"]
  verify                = local.reloader["verify"]
  values = [
    local.values_reloader,
    local.reloader["extra_values"]
  ]

  dynamic "set" {
    for_each = {
      for c, v in local.reloader["images_data"].containers :
      c => v if length(v.rewrite_values.tag) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.reloader["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.reloader["images_data"].containers :
      c => v if try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.image.name
      value = set.value.ecr_prepare_images && set.value.source_provided ? "${
        try(local.reloader["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")}${set.value.rewrite_values.image.tail
        }" : set.value.ecr_prepare_images ? try(
        local.reloader["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].name, ""
      ) : set.value.rewrite_values.image.value
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.reloader["images_data"].containers :
      c => v if length(v.rewrite_values.registry) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.registry.name
      # when unset, it should be replaced with the one prepared on ECR
      value = set.value.rewrite_values.registry.value != "" ? set.value.rewrite_values.registry.value : split(
        "/", try(local.reloader["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")
      )[0]
    }
  }

  namespace = kubernetes_namespace.reloader.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds
  ]
}
