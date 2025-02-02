locals {

  ingress-nginx-internal = merge(
    local.helm_defaults,
    {
      name                    = local.helm_dependencies[index(local.helm_dependencies.*.name, "ingress-nginx-internal")].name
      chart                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "ingress-nginx-internal")].chart
      repository              = local.helm_dependencies[index(local.helm_dependencies.*.name, "ingress-nginx-internal")].repository
      chart_version           = local.helm_dependencies[index(local.helm_dependencies.*.name, "ingress-nginx-internal")].version
      namespace               = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "ingress-nginx-internal")].namespace, "ingress-nginx-internal")
      use_nlb                 = false
      use_nlb_ip              = false
      use_l7                  = false
      enabled                 = false
      default_network_policy  = true
      albc_pod_readiness_gate = "disabled"
      ingress_cidrs           = ["0.0.0.0/0"]
      allowed_cidrs           = ["0.0.0.0/0"]
      nlb_listeners = {
        http : "TCP:80"
        https : "TCP:443"
      }
      vpa_enable          = false
      images_data         = { containers = {} }
      images_repos        = { repos = {} }
      containers_versions = {}
    },
    var.ingress-nginx-internal
  )

  ingress-nginx-internal_nlb_listeners = { for l, v in local.ingress-nginx-internal.nlb_listeners : l => [split(":", v)[0], split(":", v)[1]] }

  values_ingress-nginx-internal_l4 = <<VALUES
controller:
  metrics:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
    serviceMonitor:
      enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  updateStrategy:
    type: RollingUpdate
  kind: "DaemonSet"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
      service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
  publishService:
    enabled: true
  config:
    use-proxy-protocol: "true"
  priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
  admissionWebhooks:
    patch:
      podAnnotations:
        linkerd.io/inject: disabled
VALUES

  values_ingress-nginx-internal_nlb = <<VALUES
controller:
  metrics:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
    serviceMonitor:
      enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  updateStrategy:
    type: RollingUpdate
  kind: "DaemonSet"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: 'true'
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
    externalTrafficPolicy: "Local"
  publishService:
    enabled: true
  priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
  admissionWebhooks:
    patch:
      podAnnotations:
        linkerd.io/inject: disabled
VALUES

  # NOTE: service.beta.kubernetes.io/aws-load-balancer-nlb-target-type to use vcp_cni instead of nodePort
  #  - ip: route traffic directly to the pod IP (uses AWS vpc_cni plugin)
  #  - instance: route traffic to all EC2 instances within cluster on the NodePort
  values_ingress-nginx-internal_nlb_ip = <<VALUES
controller:
  metrics:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
    serviceMonitor:
      enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  updateStrategy:
    type: RollingUpdate
  kind: "DaemonSet"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: 'true'
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  publishService:
    enabled: true
  priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
  admissionWebhooks:
    patch:
      podAnnotations:
        linkerd.io/inject: disabled
VALUES

  values_ingress-nginx-internal_l7 = <<VALUES
controller:
  metrics:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
    serviceMonitor:
      enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  updateStrategy:
    type: RollingUpdate
  kind: "DaemonSet"
  service:
    targetPorts:
      http: http
      https: http
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
      service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https" # TODO: ssl ports for custom nlb_listeners as well
      service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
    externalTrafficPolicy: "Cluster"
  publishService:
    enabled: true
  config:
    use-proxy-protocol: "false"
    use-forwarded-headers: "true"
    proxy-real-ip-cidr: "0.0.0.0/0"
  priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
  admissionWebhooks:
    patch:
      podAnnotations:
        linkerd.io/inject: disabled
VALUES

}

resource "kubernetes_namespace" "ingress-nginx-internal" {
  count = local.ingress-nginx-internal["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name                               = local.ingress-nginx-internal["namespace"]
      "${local.labels_prefix}/component" = "ingress"
      # If nginx uses aws-load-balancer controller (albc) with svc=LoadBalancer to create NLB, then enable
      # pod-readiness gates. Next pod will not come up till previous pod becomes a Healthy NLB target. This is crucial
      # to prevent service outage. Acceptable values: enabled | disabled
      # More details - https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.5/deploy/pod_readiness_gate/
      "elbv2.k8s.aws/pod-readiness-gate-inject" = local.ingress-nginx-internal["albc_pod_readiness_gate"]
      }, local.vpa["vpa_only_recommend"] && local.ingress-nginx-internal["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.ingress-nginx-internal["namespace"]
  }
}

module "deploy_ingress-nginx-internal" {
  count                 = local.ingress-nginx-internal["enabled"] ? 1 : 0
  source                = "./deploy"
  images_data           = local.ingress-nginx-internal["images_data"]
  images_repos          = local.ingress-nginx-internal["images_repos"]
  containers_versions   = local.ingress-nginx-internal["containers_versions"]
  repository            = local.ingress-nginx-internal["repository"]
  name                  = local.ingress-nginx-internal["name"]
  chart                 = local.ingress-nginx-internal["chart"]
  chart_version         = local.ingress-nginx-internal["chart_version"]
  timeout               = local.ingress-nginx-internal["timeout"]
  force_update          = local.ingress-nginx-internal["force_update"]
  recreate_pods         = local.ingress-nginx-internal["recreate_pods"]
  wait                  = local.ingress-nginx-internal["wait"]
  atomic                = local.ingress-nginx-internal["atomic"]
  cleanup_on_fail       = local.ingress-nginx-internal["cleanup_on_fail"]
  dependency_update     = local.ingress-nginx-internal["dependency_update"]
  disable_crd_hooks     = local.ingress-nginx-internal["disable_crd_hooks"]
  disable_webhooks      = local.ingress-nginx-internal["disable_webhooks"]
  render_subchart_notes = local.ingress-nginx-internal["render_subchart_notes"]
  replace               = local.ingress-nginx-internal["replace"]
  reset_values          = local.ingress-nginx-internal["reset_values"]
  reuse_values          = local.ingress-nginx-internal["reuse_values"]
  helm_upgrade          = local.ingress-nginx-internal["helm_upgrade"]
  skip_crds             = local.ingress-nginx-internal["skip_crds"]
  verify                = local.ingress-nginx-internal["verify"]
  values = [
    local.ingress-nginx-internal["use_nlb_ip"] ? local.values_ingress-nginx-internal_nlb_ip : local.ingress-nginx-internal["use_nlb"] ? local.values_ingress-nginx-internal_nlb : local.ingress-nginx-internal["use_l7"] ? local.values_ingress-nginx-internal_l7 : local.values_ingress-nginx-internal_l4,
    local.ingress-nginx-internal["extra_values"],
  ]

  namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds
  ]
}

resource "kubernetes_network_policy" "ingress-nginx-internal_default_deny" {
  count = local.ingress-nginx-internal["enabled"] && local.ingress-nginx-internal["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "ingress-nginx-internal_allow_namespace" {
  count = local.ingress-nginx-internal["enabled"] && local.ingress-nginx-internal["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "ingress-nginx-internal_allow_ingress" {
  count = local.ingress-nginx-internal["enabled"] && local.ingress-nginx-internal["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]}-allow-ingress"
    namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["ingress-nginx-internal"]
      }
    }

    ingress {
      dynamic "ports" {
        for_each = local.ingress-nginx-internal_nlb_listeners
        content {
          protocol = ports.value[0]
          port     = ports.value[1]
        }
      }

      dynamic "from" {
        for_each = local.ingress-nginx-internal["ingress_cidrs"]
        content {
          ip_block {
            cidr = from.value
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "ingress-nginx-internal_allow_monitoring" {
  count = local.ingress-nginx-internal["enabled"] && local.ingress-nginx-internal["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "metrics"
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

resource "kubernetes_network_policy" "ingress-nginx-internal_allow_control_plane" {
  count = local.ingress-nginx-internal["enabled"] && local.ingress-nginx-internal["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]}-allow-control-plane"
    namespace = kubernetes_namespace.ingress-nginx-internal.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["ingress-nginx-internal"]
      }
    }

    ingress {
      ports {
        port     = "8443"
        protocol = "TCP"
      }

      dynamic "from" {
        for_each = local.ingress-nginx-internal["allowed_cidrs"]
        content {
          ip_block {
            cidr = from.value
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
