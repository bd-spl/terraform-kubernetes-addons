locals {

  reloader = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].version
      namespace              = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "reloader")].namespace, "reloader")
      service_account_name   = "reloader"
      default_network_policy = true
      enabled                = false
      vpa_enable             = false
      vpa_only_recommend     = false
      images_data            = { containers = {} }
      images_repos           = { repos = {} }
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
  count                 = local.reloader["enabled"] ? 1 : 0
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
  helm_upgrade          = local.reloader["helm_upgrade"]
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
        port     = "9090"
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
