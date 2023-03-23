locals {

  external-dns = { for k, v in var.external-dns : k => merge(
    local.helm_defaults,
    {
      chart                     = local.helm_dependencies[index(local.helm_dependencies.*.name, "external-dns")].name
      repository                = local.helm_dependencies[index(local.helm_dependencies.*.name, "external-dns")].repository
      chart_version             = local.helm_dependencies[index(local.helm_dependencies.*.name, "external-dns")].version
      name                      = k
      namespace                 = k
      service_account_name      = "external-dns"
      enabled                   = false
      create_iam_resources_irsa = true
      iam_policy_override       = null
      default_network_policy    = true
      name_prefix               = "${var.cluster-name}"
    },
    v,
  ) }

  # TODO: wire-in --aws-zone-type=public/private depending on a EKS private/public type? And dnsPolicy?
  # see https://aws.amazon.com/premiumsupport/knowledge-center/eks-set-up-externaldns/
  values_external-dns = { for k, v in local.external-dns : k => merge(
    {
      values = <<-VALUES
        provider: aws
        txtPrefix: "ext-dns-"
        txtOwnerId: ${var.cluster-name}
        logFormat: json
        policy: sync
        serviceAccount:
          name: ${v["service_account_name"]}
          annotations:
            eks.amazonaws.com/role-arn: "${v["create_iam_resources_irsa"] ? module.iam_assumable_role_external-dns[k].iam_role_arn : ""}"
        serviceMonitor:
          enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
        priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
        VALUES
    },
    v,
  ) }
}

module "iam_assumable_role_external-dns" {
  for_each                      = local.external-dns
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> 5.0"
  create_role                   = each.value["enabled"] && each.value["create_iam_resources_irsa"]
  role_name                     = "${each.value.name_prefix}-${each.key}"
  provider_url                  = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns              = each.value["enabled"] && each.value["create_iam_resources_irsa"] ? [aws_iam_policy.external-dns[each.key].arn] : []
  number_of_role_policy_arns    = 1
  oidc_fully_qualified_subjects = ["system:serviceaccount:${each.value["namespace"]}:${each.value["service_account_name"]}"]
  tags                          = local.tags
}

resource "aws_iam_policy" "external-dns" {
  for_each = { for k, v in local.external-dns : k => v if v["enabled"] && v["create_iam_resources_irsa"] }
  name     = "${each.value.name_prefix}-${each.key}"
  policy   = each.value["iam_policy_override"] == null ? data.aws_iam_policy_document.external-dns.json : each.value["iam_policy_override"]
  tags     = local.tags
}

data "aws_iam_policy_document" "external-dns" {
  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets"
    ]

    resources = ["arn:${local.arn-partition}:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]

    resources = ["*"]

  }
}

resource "kubernetes_namespace" "external-dns" {
  for_each = { for k, v in local.external-dns : k => v if v["enabled"] }

  metadata {
    labels = {
      name = each.value["namespace"]
    }

    name = each.value["namespace"]
  }
}

resource "helm_release" "external-dns" {
  for_each              = { for k, v in local.external-dns : k => v if v["enabled"] }
  repository            = each.value["repository"]
  name                  = each.value["name"]
  chart                 = each.value["chart"]
  version               = each.value["chart_version"]
  timeout               = each.value["timeout"]
  force_update          = each.value["force_update"]
  recreate_pods         = each.value["recreate_pods"]
  wait                  = each.value["wait"]
  atomic                = each.value["atomic"]
  cleanup_on_fail       = each.value["cleanup_on_fail"]
  dependency_update     = each.value["dependency_update"]
  disable_crd_hooks     = each.value["disable_crd_hooks"]
  disable_webhooks      = each.value["disable_webhooks"]
  render_subchart_notes = each.value["render_subchart_notes"]
  replace               = each.value["replace"]
  reset_values          = each.value["reset_values"]
  reuse_values          = each.value["reuse_values"]
  skip_crds             = each.value["skip_crds"]
  verify                = each.value["verify"]
  values = [
    local.values_external-dns[each.key]["values"],
    each.value["extra_values"]
  ]

  #TODO(bogdando): create a shared template and refer it in addons (copy-pasta until then)
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.external-dns.containers :
      c => v if v.rewrite_values.tag != null
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.external-dns["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = local.images_data.external-dns.containers
    content {
      name = set.value.rewrite_values.image.name
      value = set.value.ecr_prepare_images && set.value.source_provided ? "${
        try(aws_ecr_repository.this[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")}${set.value.rewrite_values.image.tail
        }" : set.value.ecr_prepare_images ? "${
        try(aws_ecr_repository.this[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].name, "")
      }" : set.value.rewrite_values.image.value
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.images_data.external-dns.containers :
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

  namespace = kubernetes_namespace.external-dns[each.key].metadata.0.name

  depends_on = [
    skopeo_copy.this,
    kubectl_manifest.prometheus-operator_crds
  ]
}

resource "kubernetes_network_policy" "external-dns_default_deny" {
  for_each = { for k, v in local.external-dns : k => v if v["enabled"] && v["default_network_policy"] }

  metadata {
    name      = "${kubernetes_namespace.external-dns[each.key].metadata.0.name}-default-deny"
    namespace = kubernetes_namespace.external-dns[each.key].metadata.0.name
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "external-dns_allow_namespace" {
  for_each = { for k, v in local.external-dns : k => v if v["enabled"] && v["default_network_policy"] }

  metadata {
    name      = "${kubernetes_namespace.external-dns[each.key].metadata.0.name}-allow-namespace"
    namespace = kubernetes_namespace.external-dns[each.key].metadata.0.name
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.external-dns[each.key].metadata.0.name
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "external-dns_allow_monitoring" {
  for_each = { for k, v in local.external-dns : k => v if v["enabled"] && v["default_network_policy"] }

  metadata {
    name      = "${kubernetes_namespace.external-dns[each.key].metadata.0.name}-allow-monitoring"
    namespace = kubernetes_namespace.external-dns[each.key].metadata.0.name
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "http"
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
