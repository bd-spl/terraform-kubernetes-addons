locals {
  vpa = merge(
    local.helm_defaults,
    {
      name_vpa                 = local.helm_dependencies[index(local.helm_dependencies.*.name, "vpa")].name
      chart_vpa                = local.helm_dependencies[index(local.helm_dependencies.*.name, "vpa")].name
      repository_vpa           = local.helm_dependencies[index(local.helm_dependencies.*.name, "vpa")].repository
      chart_version_vpa        = local.helm_dependencies[index(local.helm_dependencies.*.name, "vpa")].version
      name_goldilocks          = local.helm_dependencies[index(local.helm_dependencies.*.name, "goldilocks")].name
      chart_goldilocks         = local.helm_dependencies[index(local.helm_dependencies.*.name, "goldilocks")].name
      repository_goldilocks    = local.helm_dependencies[index(local.helm_dependencies.*.name, "goldilocks")].repository
      chart_version_goldilocks = local.helm_dependencies[index(local.helm_dependencies.*.name, "goldilocks")].version
      namespace                = "vpa"
      enabled                  = false
      default_network_policy   = true
      skip_crds                = false
      name_prefix              = "${var.cluster-name}-vpa"
      ingress_class            = "nginx"
      ingress_annotaions       = {}
      goldilocks_fqdn          = "goldilocks.example.org"
      resources                = {}
    },
    var.vpa
  )

  values_goldilocks = <<VALUES
nameOverride: "${local.vpa["name_vpa"]}"
controller:
  resources: ${jsonencode(local.vpa["resources"])}
dashboard:
  resources: ${jsonencode(local.vpa["resources"])}
  replicaCount: 1
ingress:
  enabled: true
  className: ${local.vpa["ingress_class"]}
  annotations: ${jsonencode(local.vpa["ingress_annotaions"])}
  hosts:
    - host: ${local.vpa["goldilocks_fqdn"]}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: goldilocks-tls
      hosts:
        - ${local.vpa["goldilocks_fqdn"]}
VALUES

  values_vpa = <<VALUES
nameOverride: "${local.vpa["name_goldilocks"]}"
priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
admissionController:
  enabled: false
updater:
  resources: ${jsonencode(local.vpa["resources"])}
  podMonitor:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
recommender:
  resources: ${jsonencode(local.vpa["resources"])}
  podMonitor:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
VALUES
}

resource "kubernetes_namespace" "vpa" {
  count = local.vpa["enabled"] ? 1 : 0

  metadata {
    labels = {
      name = local.vpa["namespace"]
    }

    name = local.vpa["namespace"]
  }
}

module "helm_release_ecr_prepare_vpa" {
  source                = "./helm_release_ecr_prepare"
  helm_dependencies     = [for _, d in local.helm_dependencies : d if d.name == "vpa"]
  containers_versions   = local.vpa["containers_versions"]
  count                 = local.vpa["enabled"] ? 1 : 0
  repository            = local.vpa["repository_vpa"]
  name                  = local.vpa["name_vpa"]
  chart                 = local.vpa["chart_vpa"]
  chart_version         = local.vpa["chart_version_vpa"]
  timeout               = local.vpa["timeout"]
  force_update          = local.vpa["force_update"]
  recreate_pods         = local.vpa["recreate_pods"]
  wait                  = local.vpa["wait"]
  atomic                = local.vpa["atomic"]
  cleanup_on_fail       = local.vpa["cleanup_on_fail"]
  dependency_update     = local.vpa["dependency_update"]
  disable_crd_hooks     = local.vpa["disable_crd_hooks"]
  disable_webhooks      = local.vpa["disable_webhooks"]
  render_subchart_notes = local.vpa["render_subchart_notes"]
  replace               = local.vpa["replace"]
  reset_values          = local.vpa["reset_values"]
  reuse_values          = local.vpa["reuse_values"]
  skip_crds             = local.vpa["skip_crds"]
  verify                = local.vpa["verify"]
  values = [
    local.values_vpa,
    local.vpa["extra_values"]["vpa"]
  ]

  namespace = kubernetes_namespace.vpa.*.metadata.0.name[count.index]

  depends_on = [
    module.helm_release_ecr_prepare_ingress-nginx,
  ]
}

module "helm_release_ecr_prepare_goldilocks" {
  source                = "./helm_release_ecr_prepare"
  helm_dependencies     = [for _, d in local.helm_dependencies : d if d.name == "goldilocks"]
  containers_versions   = local.vpa["containers_versions"]
  count                 = local.vpa["enabled"] ? 1 : 0
  repository            = local.vpa["repository_goldilocks"]
  name                  = local.vpa["name_goldilocks"]
  chart                 = local.vpa["chart_goldilocks"]
  chart_version         = local.vpa["chart_version_goldilocks"]
  timeout               = local.vpa["timeout"]
  force_update          = local.vpa["force_update"]
  recreate_pods         = local.vpa["recreate_pods"]
  wait                  = local.vpa["wait"]
  atomic                = local.vpa["atomic"]
  cleanup_on_fail       = local.vpa["cleanup_on_fail"]
  dependency_update     = local.vpa["dependency_update"]
  disable_crd_hooks     = local.vpa["disable_crd_hooks"]
  disable_webhooks      = local.vpa["disable_webhooks"]
  render_subchart_notes = local.vpa["render_subchart_notes"]
  replace               = local.vpa["replace"]
  reset_values          = local.vpa["reset_values"]
  reuse_values          = local.vpa["reuse_values"]
  skip_crds             = local.vpa["skip_crds"]
  verify                = local.vpa["verify"]
  values = [
    local.values_goldilocks,
    local.vpa["extra_values"]["goldilocks"]
  ]

  namespace = kubernetes_namespace.vpa.*.metadata.0.name[count.index]

  depends_on = [
    module.helm_release_ecr_prepare_vpa
  ]
}

resource "kubernetes_network_policy" "vpa_default_deny" {
  count = local.vpa["enabled"] && local.vpa["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.vpa.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.vpa.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "vpa_allow_namespace" {
  count = local.vpa["enabled"] && local.vpa["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.vpa.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.vpa.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.vpa.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "vpa_allow_monitoring" {
  count = local.vpa["enabled"] && local.vpa["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.vpa.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.vpa.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "8942"
        protocol = "TCP"
      }
      ports {
        port     = "8943"
        protocol = "TCP"
      }
      ports {
        port     = "8080"
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
