locals {

  dashboard = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "kubernetes-dashboard")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "kubernetes-dashboard")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "kubernetes-dashboard")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "kubernetes-dashboard")].version
      namespace              = "dashboard"
      service_account_name   = "dashboard"
      enabled                = false
      default_network_policy = true
      allow_cluster_view     = false
      vpa_enable             = false
    },
    var.dashboard
  )

  # NOTE: whith the Skip button (deprecated upstream), the service account RBAC permissions will be used to get a cluster view anonimously
  extra_args = !local.dashboard["allow_cluster_view"] ? "" : <<EOT
extraArgs:
  - --enable-skip-login
EOT

  values_dashboard = <<VALUES
${local.extra_args}
clusterReadOnlyRole: ${local.dashboard["allow_cluster_view"]}
#clusterReadOnlyRoleAdditionalRules: [{apiGroups: ..., resources: ..., verbs: ...}, ... ]

rbac:
  create: true

metricsScraper:
  enabled: ${local.metrics-server["enabled"]}

metrics-server:
  enabled: ${local.metrics-server["enabled"]}
  args:
    - --kubelet-preferred-address-types=Hostname
    #- --kubelet-insecure-tls
    #- --requestheader-client-ca-file=

serviceMonitor:
  enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  namespace: ${local.dashboard["namespace"]}

priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
VALUES
}

resource "kubernetes_namespace" "dashboard" {
  count = local.dashboard["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.dashboard["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.dashboard["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.dashboard["namespace"]
  }
}

resource "helm_release" "dashboard" {
  count                 = local.dashboard["enabled"] ? 1 : 0
  repository            = local.dashboard["repository"]
  name                  = local.dashboard["name"]
  chart                 = local.dashboard["chart"]
  version               = local.dashboard["chart_version"]
  timeout               = local.dashboard["timeout"]
  force_update          = local.dashboard["force_update"]
  recreate_pods         = local.dashboard["recreate_pods"]
  wait                  = local.dashboard["wait"]
  atomic                = local.dashboard["atomic"]
  cleanup_on_fail       = local.dashboard["cleanup_on_fail"]
  dependency_update     = local.dashboard["dependency_update"]
  disable_crd_hooks     = local.dashboard["disable_crd_hooks"]
  disable_webhooks      = local.dashboard["disable_webhooks"]
  render_subchart_notes = local.dashboard["render_subchart_notes"]
  replace               = local.dashboard["replace"]
  reset_values          = local.dashboard["reset_values"]
  reuse_values          = local.dashboard["reuse_values"]
  skip_crds             = local.dashboard["skip_crds"]
  verify                = local.dashboard["verify"]
  values = [
    local.values_dashboard,
    local.dashboard["extra_values"]
  ]

  #TODO(bogdando): create a shared template and refer it in addons (copy-pasta until then)
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.kubernetes-dashboard.containers :
      c => v if v.rewrite_values.tag != null
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.dashboard["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = local.images_data.kubernetes-dashboard.containers
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
      for c, v in local.images_data.kubernetes-dashboard.containers :
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

  namespace = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]

  depends_on = [
    skopeo_copy.this,
    helm_release.ingress-nginx
  ]
}

resource "kubernetes_network_policy" "dashboard_default_deny" {
  count = local.dashboard["enabled"] && local.dashboard["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dashboard.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "dashboard_allow_namespace" {
  count = local.dashboard["enabled"] && local.dashboard["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dashboard.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "dashboard_allow_monitoring" {
  count = local.dashboard["enabled"] && local.dashboard["default_network_policy"] && local.kube-prometheus-stack["enabled"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dashboard.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "8000"
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
