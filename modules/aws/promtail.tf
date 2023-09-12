locals {

  promtail = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "promtail")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "promtail")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "promtail")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "promtail")].version
      namespace              = "monitoring"
      create_ns              = false
      enabled                = false
      loki_address           = "http://${local.loki-stack["name"]}-write:3100/loki/api/v1/push"
      use_tls                = false
      tls_crt                = null
      tls_key                = null
      default_network_policy = false
      vpa_enable             = false
    },
    var.promtail
  )

  values_promtail = <<-VALUES
    priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
    extraArgs:
      - -client.external-labels=cluster=${var.cluster-name}
    serviceMonitor:
      enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
    config:
      clients:
        - url: ${local.promtail["loki_address"]}
    tolerations:
      - effect: NoSchedule
        operator: Exists
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoExecute
        operator: Exists
    VALUES

  values_promtail_tls = <<-VALUES
    defaultVolumes:
      - name: run
        hostPath:
          path: /run/promtail
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
      - name: pods
        hostPath:
          path: /var/log/pods
      - name: tls
        secret:
          secretName: ${local.promtail["name"]}-tls
    defaultVolumeMounts:
      - name: run
        mountPath: /run/promtail
      - name: containers
        mountPath: /var/lib/docker/containers
        readOnly: true
      - name: pods
        mountPath: /var/log/pods
        readOnly: true
      - name: tls
        mountPath: /tls
        readOnly: true
    config:
      clients:
        - url: ${local.promtail["loki_address"]}
          tls_config:
            cert_file: /tls/tls.crt
            key_file: /tls/tls.key
    VALUES
}

resource "kubernetes_namespace" "promtail" {
  count = local.promtail["enabled"] && local.promtail["create_ns"] ? 1 : 0

  metadata {
    labels = merge({
      name                               = local.promtail["namespace"]
      "${local.labels_prefix}/component" = "monitoring"
      }, local.vpa["vpa_only_recommend"] && local.promtail["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.promtail["namespace"]
  }
}

resource "helm_release" "promtail" {
  count                 = local.promtail["enabled"] ? 1 : 0
  repository            = local.promtail["repository"]
  name                  = local.promtail["name"]
  chart                 = local.promtail["chart"]
  version               = local.promtail["chart_version"]
  timeout               = local.promtail["timeout"]
  force_update          = local.promtail["force_update"]
  recreate_pods         = local.promtail["recreate_pods"]
  wait                  = local.promtail["wait"]
  atomic                = local.promtail["atomic"]
  cleanup_on_fail       = local.promtail["cleanup_on_fail"]
  dependency_update     = local.promtail["dependency_update"]
  disable_crd_hooks     = local.promtail["disable_crd_hooks"]
  disable_webhooks      = local.promtail["disable_webhooks"]
  render_subchart_notes = local.promtail["render_subchart_notes"]
  replace               = local.promtail["replace"]
  reset_values          = local.promtail["reset_values"]
  reuse_values          = local.promtail["reuse_values"]
  skip_crds             = local.promtail["skip_crds"]
  verify                = local.promtail["verify"]
  values = compact([
    local.values_promtail,
    local.promtail["use_tls"] ? local.values_promtail_tls : "",
    local.promtail["extra_values"]
  ])

  #TODO(bogdando): create a shared template and refer it in addons (copy-pasta until then)
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.promtail.containers :
      c => v if v.rewrite_values.tag != null
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.promtail["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = local.images_data.promtail.containers
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
      for c, v in local.images_data.promtail.containers :
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


  namespace = local.promtail["namespace"]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds,
    helm_release.loki-stack,
    kubernetes_secret.loki-stack-ca,
    kubernetes_secret.promtail-tls
  ]
}

resource "kubernetes_secret" "promtail-tls" {
  count = local.promtail["enabled"] && local.promtail["use_tls"] ? 1 : 0
  metadata {
    name      = "${local.promtail["name"]}-tls"
    namespace = local.promtail["namespace"]
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = local.promtail["tls_crt"]
    "tls.key" = local.promtail["tls_key"]
  }
}

resource "kubernetes_network_policy" "promtail_default_deny" {
  count = local.promtail["create_ns"] && local.promtail["enabled"] && local.promtail["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.promtail.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.promtail.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "promtail_allow_namespace" {
  count = local.promtail["create_ns"] && local.promtail["enabled"] && local.promtail["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.promtail.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.promtail.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.promtail.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "promtail_allow_ingress" {
  count = local.promtail["create_ns"] && local.promtail["enabled"] && local.promtail["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.promtail.*.metadata.0.name[count.index]}-allow-ingress"
    namespace = kubernetes_namespace.promtail.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "${local.labels_prefix}/component" = "ingress"
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
