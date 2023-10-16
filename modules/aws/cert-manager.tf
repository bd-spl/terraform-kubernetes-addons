locals {
  cert-manager_manifests_version = try(
    var.cert-manager.manifests_version, ""
  ) != "" ? var.cert-manager.manifests_version : local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].manifests_version
  cert-manager = merge(
    local.helm_defaults,
    {
      name                      = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].name
      chart                     = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].name
      repository                = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].repository
      chart_version             = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].version
      namespace                 = "cert-manager"
      service_account_name      = "cert-manager"
      create_iam_resources_irsa = true
      enabled                   = false
      iam_policy_override       = null
      default_network_policy    = true
      acme_providers = [
        {
          name          = "letsencrypt-staging"
          email         = "contact@acme.com"
          server        = "https://acme-staging-v02.api.letsencrypt.org/directory"
          ingress_class = "nginx"
        },
        {
          name          = "letsencrypt"
          email         = "contact@acme.com"
          server        = "https://acme-v02.api.letsencrypt.org/directory"
          ingress_class = "nginx"
        }
      ]
      acme_use_egress_proxy     = false
      whitelist_source_range    = ""
      acme_egress_proxy_secret  = ""
      acme_http01_enabled       = true
      acme_http01_ingress_class = "nginx"
      acme_dns01_enabled        = true
      acme_skip_tls_verify      = false
      allowed_cidrs             = ["0.0.0.0/0"]
      csi_driver                = false
      name_prefix               = "${var.cluster-name}-cert-manager"
      extra_tpl                 = {}
      extra_values              = ""
      kustomizations            = {}
      kustomizations_images_map = {}
      # Kustomize resources
      resources = [
        "https://github.com/kubernetes-sigs/gateway-api/releases/download/${local.cert-manager_manifests_version}/standard-install.yaml"
      ]
      vpa_enable          = false
      use_deploy_module   = true
      images_data         = { containers = {} }
      images_repos        = { repos = {} }
      containers_versions = {}
    },
    var.cert-manager
  )

  values_cert-manager = <<VALUES
global:
  priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
serviceAccount:
  name: ${local.cert-manager["service_account_name"]}
  annotations:
    eks.amazonaws.com/role-arn: "${local.cert-manager["enabled"] && local.cert-manager["create_iam_resources_irsa"] ? module.iam_assumable_role_cert-manager.iam_role_arn : ""}"
prometheus:
  servicemonitor:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
securityContext:
  fsGroup: 1001
installCRDs: true
VALUES

  # FIXME
  #TODO(bogdando): create a shared template, or a module, and refer it in addons managed by kustomize (copy-pasta until then)
  cert-manager_containers_data = {
    for k, v in local.cert-manager["images_data"].containers :
    v.rewrite_values.image.name => {
      tag = try(
        local.cert-manager["containers_versions"][v.rewrite_values.tag.name],
        v.rewrite_values.tag.value,
        v.rewrite_values.image.tail
      )
      repo = v.ecr_prepare_images && v.source_provided ? try(
        local.cert-manager["images_repos"].repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].repository_url, "") : v.ecr_prepare_images ? try(
        local.cert-manager["images_repos"].repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].name, ""
      ) : v.rewrite_values.image.value
      src = v.src
    } if v.manager == "kustomize" || v.manager == "extra"
  }

  ## Extra values prepare images manager

  # Get variables names and values to template them in
  cert-manager_extra_tpl_vars = {
    for k, v in local.cert-manager_containers_data :
    k => {
      params = {
        "${split(".", k)[1]}-repo" = v.repo
        "${split(".", k)[1]}-tag"  = v.tag
      }
      } if lookup(
      local.cert-manager.extra_tpl, split(".", k)[0], null
    ) != null
  }
  cert-manager_extra_tpl_data = [for v in values(local.cert-manager_extra_tpl_vars) : v.params]

  # FIXME: workaround limitation to pass templates with vars in it (even if escaped) via the module input var.cert-manager
  cert-manager_extra_tpl = [
    for i in [
      for k, v in local.cert-manager_extra_tpl_vars :
      { "${k}" = yamldecode(replace( # tflint-ignore: terraform_deprecated_interpolation
        replace(
          yamlencode(local.cert-manager.extra_tpl),
          format("$%s", keys(v.params)[0]), "$${${keys(v.params)[0]}}"
        ),
        format("$%s", keys(v.params)[1]), "$${${keys(v.params)[1]}}"
      )) }
    ] : { for k, v in i : split(".", k)[0] => v[split(".", k)[0]] }
  ]

  ## Kuztomize prepare images manager

  # Update kustomizations with the prepared containers images data
  cert-manager_kustomizations_patched = flatten([
    for k, data in local.cert-manager.kustomizations :
    [for v in compact(split("---", data)) :
      replace(
        yamlencode(merge(
          try(yamldecode(v), {}),
          {
            resources = lookup(
              try(yamldecode(v), {}),
              "resources",
              local.cert-manager.resources
            )
          },
          length(lookup(try(yamldecode(v), {}), "images", {})) == 0 ? {} : {
            images = [
              for c in try(yamldecode(v).images, []) :
              {
                # Remove unique identifiers distinguishing same images used for different containers
                name = split("::", c.name)[0]
                newName = local.cert-manager_containers_data[
                  format(
                    "%s.%s.repository",
                    k,
                    split("::", local.cert-manager.kustomizations_images_map[k][c.name])[0]
                  )
                ].repo
                newTag = try(c.newTag, "") != "" ? c.newTag : local.cert-manager_containers_data[
                  format(
                    "%s.%s.repository",
                    k,
                    split("::", local.cert-manager.kustomizations_images_map[k][c.name])[0]
                  )
                ].tag
              }
            ]
          }
          )
        ),
      "$manifest_version", local.cert-manager_manifests_version)
    ]
  ])
  # FIXME END
}

# NOTE: Gateway admission jobs need to be removed, before kustomize can rebuild them with new ECR containers images data rewritted for it
# That is because kustomize uses patching, which cannot update Jobs' spec immutable container images data
resource "null_resource" "cert-manager-kustomize-prepare" {
  count = length(local.cert-manager.kustomizations) > 0 && local.cert-manager["use_deploy_module"] ? 1 : 0

  triggers = {
    filemd5 = filemd5("cert-manager.tf")
    filemd5 = filemd5("../../helm-dependencies.yaml")
  }

  provisioner "local-exec" {
    command = <<-EOT
    kubectl delete job gateway-api-admission -n gateway-system --ignore-not-found
    kubectl delete job gateway-api-admission-patch -n gateway-system --ignore-not-found
  EOT
  }
}

module "iam_assumable_role_cert-manager" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> 5.0"
  create_role                   = local.cert-manager["enabled"] && local.cert-manager["create_iam_resources_irsa"]
  role_name                     = local.cert-manager["name_prefix"]
  provider_url                  = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns              = local.cert-manager["enabled"] && local.cert-manager["create_iam_resources_irsa"] ? [aws_iam_policy.cert-manager[0].arn] : []
  number_of_role_policy_arns    = 1
  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.cert-manager["namespace"]}:${local.cert-manager["service_account_name"]}"]
  tags                          = local.tags
}

resource "aws_iam_policy" "cert-manager" {
  count  = local.cert-manager["enabled"] && local.cert-manager["create_iam_resources_irsa"] ? 1 : 0
  name   = local.cert-manager["name_prefix"]
  policy = local.cert-manager["iam_policy_override"] == null ? data.aws_iam_policy_document.cert-manager.json : local.cert-manager["iam_policy_override"]
  tags   = local.tags
}

data "aws_iam_policy_document" "cert-manager" {
  statement {
    effect = "Allow"

    actions = [
      "route53:GetChange"
    ]

    resources = ["arn:${local.arn-partition}:route53:::change/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]

    resources = ["arn:${local.arn-partition}:route53:::hostedzone/*"]

  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZonesByName"
    ]

    resources = ["*"]

  }
}

resource "kubernetes_namespace" "cert-manager" {
  count = local.cert-manager["enabled"] ? 1 : 0

  metadata {
    annotations = {
      "certmanager.k8s.io/disable-validation" = "true"
    }

    labels = merge({
      name = local.cert-manager["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.cert-manager["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.cert-manager["namespace"]
  }
}

module "deploy_cert-manager" {
  count  = local.cert-manager["enabled"] && local.cert-manager["use_deploy_module"] ? 1 : 0
  source = "./deploy"
  # Kustomize manager data
  kustomizations                        = local.cert-manager.kustomizations
  kustomizations_images_map             = local.cert-manager.kustomizations_images_map
  kustomize_resources                   = local.cert-manager.resources
  kustomize_resources_manifests_version = local.cert-manager_manifests_version
  # Delete immutable jobs, before applying changes to its containers images with kustomize
  kustomize_workarounds = <<-EOT
    kubectl delete job gateway-api-admission -n gateway-system --ignore-not-found
    kubectl delete job gateway-api-admission-patch -n gateway-system --ignore-not-found
  EOT
  # Extra manager data
  extra_tpl           = local.cert-manager.extra_tpl
  images_data         = local.cert-manager["images_data"]
  images_repos        = local.cert-manager["images_repos"]
  containers_versions = local.cert-manager["containers_versions"]
  # Helm manager data
  repository            = local.cert-manager["repository"]
  name                  = local.cert-manager["name"]
  chart                 = local.cert-manager["chart"]
  chart_version         = local.cert-manager["chart_version"]
  timeout               = local.cert-manager["timeout"]
  force_update          = local.cert-manager["force_update"]
  recreate_pods         = local.cert-manager["recreate_pods"]
  wait                  = local.cert-manager["wait"]
  atomic                = local.cert-manager["atomic"]
  cleanup_on_fail       = local.cert-manager["cleanup_on_fail"]
  dependency_update     = local.cert-manager["dependency_update"]
  disable_crd_hooks     = local.cert-manager["disable_crd_hooks"]
  disable_webhooks      = local.cert-manager["disable_webhooks"]
  render_subchart_notes = local.cert-manager["render_subchart_notes"]
  replace               = local.cert-manager["replace"]
  reset_values          = local.cert-manager["reset_values"]
  reuse_values          = local.cert-manager["reuse_values"]
  skip_crds             = local.cert-manager["skip_crds"]
  verify                = local.cert-manager["verify"]
  values = [
    local.values_cert-manager,
    local.cert-manager["extra_values"]
  ]

  namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds,
    resource.null_resource.cert-manager-kustomize-prepare # reguires gateway API CRD installed firstly
  ]
}

data "kubectl_path_documents" "cert-manager_cluster_issuers" {
  for_each = { for i in local.cert-manager["acme_providers"] : i.name => i }
  pattern  = "${path.module}/templates/cert-manager-cluster-issuers.yaml.tpl"
  vars = {
    aws_region                = data.aws_region.current.name
    acme_server               = each.value.server
    acme_email                = each.value.email
    acme_provider             = each.value.name
    acme_http01_ingress_class = lookup(each.value, "ingress_class", local.cert-manager["acme_http01_ingress_class"])
    acme_http01_enabled       = lookup(each.value, "http01_enabled", local.cert-manager["acme_http01_enabled"])
    acme_skip_tls_verify      = lookup(each.value, "skip_tls_verify", local.cert-manager["acme_skip_tls_verify"])
    acme_dns01_enabled        = lookup(each.value, "dns01_enabled", local.cert-manager["acme_dns01_enabled"])
    acme_use_egress_proxy     = lookup(each.value, "use_egress_proxy", local.cert-manager["acme_use_egress_proxy"])
    whitelist_source_range    = lookup(each.value, "whitelist_source_range", local.cert-manager["whitelist_source_range"])
    acme_egress_proxy_secret  = local.cert-manager["acme_egress_proxy_secret"]
  }
}

resource "time_sleep" "cert-manager_sleep" {
  count = local.cert-manager["enabled"] && (local.cert-manager["acme_http01_enabled"] || local.cert-manager["acme_dns01_enabled"]) ? 1 : 0
  depends_on = [
    module.deploy_cert-manager,
    # FIXME
    helm_release.cert-manager
  ]
  create_duration = "120s"
}

resource "kubectl_manifest" "cert-manager_cluster_issuers" {
  for_each = local.cert-manager["enabled"] && (
    local.cert-manager["acme_http01_enabled"] || local.cert-manager["acme_dns01_enabled"]
    ) ? {
    for ind, d in [
      for i in values(data.kubectl_path_documents.cert-manager_cluster_issuers) : i.documents
    ] : ind => d
  } : {}
  yaml_body = join("\n---\n", each.value)
  depends_on = [
    module.deploy_cert-manager,
    kubernetes_namespace.cert-manager,
    time_sleep.cert-manager_sleep,
    # FIXME
    helm_release.cert-manager
  ]
}

resource "kubernetes_network_policy" "cert-manager_default_deny" {
  count = local.cert-manager["enabled"] && local.cert-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "cert-manager_allow_namespace" {
  count = local.cert-manager["enabled"] && local.cert-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "cert-manager_allow_monitoring" {
  count = local.cert-manager["enabled"] && local.cert-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "9402"
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

resource "kubernetes_network_policy" "cert-manager_allow_control_plane" {
  count = local.cert-manager["enabled"] && local.cert-manager["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]}-allow-control-plane"
    namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["webhook"]
      }
    }

    ingress {
      ports {
        port     = "10250"
        protocol = "TCP"
      }

      dynamic "from" {
        for_each = local.cert-manager["allowed_cidrs"]
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

# FIXME
data "template_file" "cert-manager_extra_values_patched" {
  count    = local.cert-manager.extra_tpl != {} && length(local.cert-manager_extra_tpl_vars) > 0 && !local.cert-manager["use_deploy_module"] ? 1 : 0
  template = yamlencode(merge(local.cert-manager_extra_tpl...))
  vars     = merge(local.cert-manager_extra_tpl_data...)
}

# FIXME: local_sensitive_file maybe?
resource "local_file" "cert-manager-kustomization" {
  for_each = local.cert-manager["enabled"] && !local.cert-manager["use_deploy_module"] ? zipmap(
    [for c in local.cert-manager_kustomizations_patched : md5(c)],
    local.cert-manager_kustomizations_patched
  ) : {}
  content  = each.value
  filename = "./kustomization-${each.key}/kustomization/kustomization.yaml"
}

resource "null_resource" "cert-manager-kustomize" {
  for_each = local.cert-manager["enabled"] && !local.cert-manager["use_deploy_module"] ? zipmap(
    [for c in local.cert-manager_kustomizations_patched : md5(c)],
    local.cert-manager_kustomizations_patched
  ) : {}

  triggers = {
    kustomization = each.key
    filemd5       = filemd5("cert-manager.tf")
    filemd5       = filemd5("../../helm-dependencies.yaml")
  }

  # NOTE: cannot update Jobs' spec immutable container images data
  provisioner "local-exec" {
    command = <<-EOT
    kubectl delete job gateway-api-admission -n gateway-system --ignore-not-found
    kubectl delete job gateway-api-admission-patch -n gateway-system --ignore-not-found
    ${local.cert-manager.kustomize_external ? "kustomize build ./kustomization-${each.key}/kustomization | kubectl apply -f -" : "kubectl apply -k ./kustomization-${each.key}/kustomization"}
  EOT
  }

  depends_on = [
    local_file.cert-manager-kustomization,
  ]
}

resource "helm_release" "cert-manager" {
  count                 = local.cert-manager["enabled"] && !local.cert-manager["use_deploy_module"] ? 1 : 0
  repository            = local.cert-manager["repository"]
  name                  = local.cert-manager["name"]
  chart                 = local.cert-manager["chart"]
  version               = local.cert-manager["chart_version"]
  timeout               = local.cert-manager["timeout"]
  force_update          = local.cert-manager["force_update"]
  recreate_pods         = local.cert-manager["recreate_pods"]
  wait                  = local.cert-manager["wait"]
  atomic                = local.cert-manager["atomic"]
  cleanup_on_fail       = local.cert-manager["cleanup_on_fail"]
  dependency_update     = local.cert-manager["dependency_update"]
  disable_crd_hooks     = local.cert-manager["disable_crd_hooks"]
  disable_webhooks      = local.cert-manager["disable_webhooks"]
  render_subchart_notes = local.cert-manager["render_subchart_notes"]
  replace               = local.cert-manager["replace"]
  reset_values          = local.cert-manager["reset_values"]
  reuse_values          = local.cert-manager["reuse_values"]
  skip_crds             = local.cert-manager["skip_crds"]
  verify                = local.cert-manager["verify"]
  values = [
    local.values_cert-manager,
    yamlencode(
      merge(
        yamldecode(local.cert-manager["extra_values"]),
        try(yamldecode(data.template_file.cert-manager_extra_values_patched.0.rendered), {})
      )
    )
  ]

  dynamic "set" {
    for_each = {
      for c, v in local.cert-manager["images_data"].containers :
      c => v if length(v.rewrite_values.tag) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name  = set.value.rewrite_values.tag.name
      value = try(local.cert-manager["containers_versions"][set.value.rewrite_values.tag.name], set.value.rewrite_values.tag.value)
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.cert-manager["images_data"].containers :
      c => v if try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.image.name
      value = set.value.ecr_prepare_images && set.value.source_provided ? "${
        try(local.cert-manager["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")}${set.value.rewrite_values.image.tail
        }" : set.value.ecr_prepare_images ? try(
        local.cert-manager["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].name, ""
      ) : set.value.rewrite_values.image.value
    }
  }
  dynamic "set" {
    for_each = {
      for c, v in local.cert-manager["images_data"].containers :
      c => v if length(v.rewrite_values.registry) > 0 && try(v.manager, "helm") == "helm"
    }
    content {
      name = set.value.rewrite_values.registry.name
      # when unset, it should be replaced with the one prepared on ECR
      value = set.value.rewrite_values.registry.value != "" ? set.value.rewrite_values.registry.value : split(
        "/", try(local.cert-manager["images_repos"].repos[
          format("%s.%s", split(".", set.key)[0], split(".", set.key)[2])
        ].repository_url, "")
      )[0]
    }
  }

  namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]

  depends_on = [
    kubectl_manifest.prometheus-operator_crds,
    data.template_file.cert-manager_extra_values_patched,
    resource.null_resource.cert-manager-kustomize # reguires gateway API CRD installed firstly
  ]
}
