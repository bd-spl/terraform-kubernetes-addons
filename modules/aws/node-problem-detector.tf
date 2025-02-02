locals {
  npd = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "node-problem-detector")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "node-problem-detector")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "node-problem-detector")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "node-problem-detector")].version
      namespace              = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "node-problem-detector")].namespace, "node-problem-detector")
      enabled                = false
      default_network_policy = true
      vpa_enable             = false
      images_data            = { containers = {} }
      images_repos           = { repos = {} }
      containers_versions    = {}
    },
    var.npd
  )

  values_npd = <<VALUES
priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
VALUES

}

resource "kubernetes_namespace" "node-problem-detector" {
  count = local.npd["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.npd["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.npd["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.npd["namespace"]
  }
}

module "deploy_node-problem-detector" {
  count                 = local.npd["enabled"] ? 1 : 0
  source                = "./deploy"
  images_data           = local.npd["images_data"]
  images_repos          = local.npd["images_repos"]
  containers_versions   = local.npd["containers_versions"]
  repository            = local.npd["repository"]
  name                  = local.npd["name"]
  chart                 = local.npd["chart"]
  chart_version         = local.npd["chart_version"]
  timeout               = local.npd["timeout"]
  force_update          = local.npd["force_update"]
  recreate_pods         = local.npd["recreate_pods"]
  wait                  = local.npd["wait"]
  atomic                = local.npd["atomic"]
  cleanup_on_fail       = local.npd["cleanup_on_fail"]
  dependency_update     = local.npd["dependency_update"]
  disable_crd_hooks     = local.npd["disable_crd_hooks"]
  disable_webhooks      = local.npd["disable_webhooks"]
  render_subchart_notes = local.npd["render_subchart_notes"]
  replace               = local.npd["replace"]
  reset_values          = local.npd["reset_values"]
  reuse_values          = local.npd["reuse_values"]
  helm_upgrade          = local.npd["helm_upgrade"]
  skip_crds             = local.npd["skip_crds"]
  verify                = local.npd["verify"]
  values = [
    local.values_npd,
    local.npd["extra_values"]
  ]

  namespace = kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]
}

resource "kubernetes_network_policy" "npd_default_deny" {
  count = local.npd["enabled"] && local.npd["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "npd_allow_namespace" {
  count = local.npd["enabled"] && local.npd["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.node-problem-detector.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
