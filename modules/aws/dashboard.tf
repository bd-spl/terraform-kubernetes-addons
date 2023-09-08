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
    labels = {
      name = local.dashboard["namespace"]
    }

    name = local.dashboard["namespace"]
  }
}

module "helm_release_ecr_prepare_dashboard" {
  source                = "./helm_release_ecr_prepare"
  helm_dependencies     = [for _, d in local.helm_dependencies : d if d.name == "kubernetes-dashboard"]
  containers_versions   = local.dashboard["containers_versions"]
  count                 = local.dashboard["enabled"] ? 1 : 0
  repository            = local.dashboard["repository"]
  name                  = local.dashboard["name"]
  chart                 = local.dashboard["chart"]
  chart_version         = local.dashboard["chart_version"]
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

  namespace = kubernetes_namespace.dashboard.*.metadata.0.name[count.index]

  depends_on = [
    module.helm_release_ecr_prepare_ingress-nginx
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
