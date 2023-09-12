locals {

  rbac-manager = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "rbac-manager")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "rbac-manager")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "rbac-manager")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "rbac-manager")].version
      namespace              = "rbac-manager"
      service_account_name   = "rbac-manager"
      enabled                = false
      default_network_policy = true
      allow_cluster_view     = false
      vpa_enable             = false
    },
    var.rbac-manager
  )

  values_rbac-manager = <<VALUES
serviceMonitor:
  enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  namespace: ${local.rbac-manager["namespace"]}

priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
VALUES
}

resource "kubernetes_namespace" "rbac-manager" {
  count = local.rbac-manager["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.rbac-manager["namespace"]
      }, local.rbac-manager["vpa_only_recommend"] && local.rbac-manager["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.rbac-manager["namespace"]
  }
}

resource "helm_release" "rbac-manager" {
  count                 = local.rbac-manager["enabled"] ? 1 : 0
  repository            = local.rbac-manager["repository"]
  name                  = local.rbac-manager["name"]
  chart                 = local.rbac-manager["chart"]
  version               = local.rbac-manager["chart_version"]
  timeout               = local.rbac-manager["timeout"]
  force_update          = local.rbac-manager["force_update"]
  recreate_pods         = local.rbac-manager["recreate_pods"]
  wait                  = local.rbac-manager["wait"]
  atomic                = local.rbac-manager["atomic"]
  cleanup_on_fail       = local.rbac-manager["cleanup_on_fail"]
  dependency_update     = local.rbac-manager["dependency_update"]
  disable_crd_hooks     = local.rbac-manager["disable_crd_hooks"]
  disable_webhooks      = local.rbac-manager["disable_webhooks"]
  render_subchart_notes = local.rbac-manager["render_subchart_notes"]
  replace               = local.rbac-manager["replace"]
  reset_values          = local.rbac-manager["reset_values"]
  reuse_values          = local.rbac-manager["reuse_values"]
  skip_crds             = local.rbac-manager["skip_crds"]
  verify                = local.rbac-manager["verify"]
  values = [
    local.values_rbac-manager,
    local.rbac-manager["extra_values"]
  ]

  #TODO(bogdando): create a shared template and refer it in addons (copy-pasta until then)
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.rbac-manager.containers :
      c => v if v.rewrite_values.tag != null
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.rbac-manager["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = local.images_data.rbac-manager.containers
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
      for c, v in local.images_data.rbac-manager.containers :
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

  namespace = kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds, skopeo_copy.this
  ]
}

resource "kubernetes_network_policy" "rbac-manager_default_deny" {
  count = local.rbac-manager["enabled"] && local.rbac-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "rbac-manager_allow_namespace" {
  count = local.rbac-manager["enabled"] && local.rbac-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "rbac-manager_allow_monitoring" {
  count = local.rbac-manager["enabled"] && local.rbac-manager["default_network_policy"] && local.kube-prometheus-stack["enabled"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.rbac-manager.*.metadata.0.name[count.index]
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
