locals {
  aws-load-balancer-controller = merge(
    local.helm_defaults,
    {
      name                      = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].name
      chart                     = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].name
      repository                = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].repository
      chart_version             = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].version
      containers                = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].containers, {})
      namespace                 = "aws-load-balancer-controller"
      service_account_name      = "aws-load-balancer-controller"
      create_iam_resources_irsa = true
      enabled                   = false
      iam_policy_override       = null
      default_network_policy    = true
      allowed_cidrs             = ["0.0.0.0/0"]
      name_prefix               = "${var.cluster-name}-awslbc"
      ecr_prepare_images        = false
      ecr_scan_on_push          = false
      ecr_immutable_tag         = false
      ecr_encryption_type       = "AES256"
      #ecr_kms_key - optional
    },
    var.aws-load-balancer-controller
  )

  values_aws-load-balancer-controller = <<VALUES
clusterName: ${var.cluster-name}
region: ${data.aws_region.current.name}
serviceAccount:
  name: "${local.aws-load-balancer-controller["service_account_name"]}"
  annotations:
    eks.amazonaws.com/role-arn: "${local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? module.iam_assumable_role_aws-load-balancer-controller.iam_role_arn : ""}"
VALUES
}

module "iam_assumable_role_aws-load-balancer-controller" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> 5.0"
  create_role                   = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"]
  role_name                     = local.aws-load-balancer-controller["name_prefix"]
  provider_url                  = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns              = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? [aws_iam_policy.aws-load-balancer-controller[0].arn] : []
  number_of_role_policy_arns    = 1
  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.aws-load-balancer-controller["namespace"]}:${local.aws-load-balancer-controller["service_account_name"]}"]
  tags                          = local.tags
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
  count  = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? 1 : 0
  name   = local.aws-load-balancer-controller["name_prefix"]
  policy = local.aws-load-balancer-controller["iam_policy_override"] == null ? templatefile("${path.module}/iam/aws-load-balancer-controller.json", { arn-partition = local.arn-partition }) : local.aws-load-balancer-controller["iam_policy_override"]
  tags   = local.tags
}

resource "kubernetes_namespace" "aws-load-balancer-controller" {
  count = local.aws-load-balancer-controller["enabled"] ? 1 : 0

  metadata {
    labels = {
      name = local.aws-load-balancer-controller["namespace"]
    }

    name = local.aws-load-balancer-controller["namespace"]
  }
}

resource "helm_release" "aws-load-balancer-controller" {
  count                 = local.aws-load-balancer-controller["enabled"] ? 1 : 0
  repository            = local.aws-load-balancer-controller["repository"]
  name                  = local.aws-load-balancer-controller["name"]
  chart                 = local.aws-load-balancer-controller["chart"]
  version               = local.aws-load-balancer-controller["chart_version"]
  timeout               = local.aws-load-balancer-controller["timeout"]
  force_update          = local.aws-load-balancer-controller["force_update"]
  recreate_pods         = local.aws-load-balancer-controller["recreate_pods"]
  wait                  = local.aws-load-balancer-controller["wait"]
  atomic                = local.aws-load-balancer-controller["atomic"]
  cleanup_on_fail       = local.aws-load-balancer-controller["cleanup_on_fail"]
  dependency_update     = local.aws-load-balancer-controller["dependency_update"]
  disable_crd_hooks     = local.aws-load-balancer-controller["disable_crd_hooks"]
  disable_webhooks      = local.aws-load-balancer-controller["disable_webhooks"]
  render_subchart_notes = local.aws-load-balancer-controller["render_subchart_notes"]
  replace               = local.aws-load-balancer-controller["replace"]
  reset_values          = local.aws-load-balancer-controller["reset_values"]
  reuse_values          = local.aws-load-balancer-controller["reuse_values"]
  skip_crds             = local.aws-load-balancer-controller["skip_crds"]
  verify                = local.aws-load-balancer-controller["verify"]
  values = [
    local.values_aws-load-balancer-controller,
    local.aws-load-balancer-controller["extra_values"]
  ]

  # TODO: make this a snippet or template to use it for all addons in the repo
  # tag overrides
  dynamic "set" {
    for_each = {
      for c, v in local.aws-load-balancer-controller["containers"] :
      c => v if(
        lookup(v, "ver", null) != null
      ) # ? true : false
    }
    content {
      name  = "${set.key}.${keys(set.value["ver"])[0]}"
      value = set.value["ver"][keys(set.value["ver"])[0]]
    }
  }
  # simple image overrides, no source data provided, i.e.
  # names in containers data refer shortnames only
  dynamic "set" {
    for_each = {
      for c, v in local.aws-load-balancer-controller["containers"] :
      c => v if(
        lookup(v, "source", null) == null && lookup(v, "name", null) != null
      ) # ? true : false
    }
    content {
      name  = "${set.key}.${keys(set.value["name"])[0]}"
      value = set.value["name"][keys(set.value["name"])[0]]
    }
  }
  # registry overrides, based on prepare images was requested or not
  dynamic "set" {
    for_each = {
      # returns a dict of {c => [v, image_shortname]}
      for c, v in local.aws-load-balancer-controller["containers"] :
      c => [
        # convert possible full image names into shortnames
        # tag is optional, fallback to latest
        v, replace(replace(v["name"][keys(v["name"])[0]],
          "${v["source"]}/", ""),
        ":${lookup(v, "ver", { "tag" : "latest" })[keys(lookup(v, "ver", ["tag"]))[0]]}", "")
        ] if(
        lookup(v, "registry", null) != null && lookup(v, "name", null) != null
      ) # ? true : false
    }
    content {
      name = "${set.key}.${keys(set.value[0]["registry"])[0]}"
      value = local.aws-load-balancer-controller["ecr_prepare_images"] ? split(
        "/", aws_ecr_repository.this["aws-load-balancer-controller.${set.value[1]}"].repository_url
      )[0] : set.value[0]["registry"][keys(set.value[0]["registry"])[0]]
    }
  }
  # image overrides when preparing it, with rewriting possible registry path included
  # in the image name, based on 'source' pattern
  dynamic "set" {
    for_each = {
      # returns a dict of {c => [v, prepared_image_shortname]}
      for c, v in local.aws-load-balancer-controller["containers"] :
      c => [
        v, replace(replace(v["name"][keys(v["name"])[0]],
          "${v["source"]}/", ""),
        ":${lookup(v, "ver", { "tag" : "latest" })[keys(lookup(v, "ver", ["tag"]))[0]]}", "")
        ] if(
        lookup(v, "source", null) != null &&
        lookup(v, "name", null) != null &&
        local.aws-load-balancer-controller["ecr_prepare_images"]
      ) # ? true : false
    }
    content {
      name = "${set.key}.${keys(set.value[0]["name"])[0]}"
      value = replace(
        set.value[0]["name"][keys(set.value[0]["name"])[0]],
        set.value[0]["source"],
      split("/", aws_ecr_repository.this["aws-load-balancer-controller.${set.value[1]}"].repository_url)[0])
    }
  }

  namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]

  depends_on = [
    skopeo_copy.this
  ]
}

resource "kubernetes_network_policy" "aws-load-balancer-controller_default_deny" {
  count = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "aws-load-balancer-controller_allow_namespace" {
  count = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "aws-load-balancer-controller_allow_control_plane" {
  count = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]}-allow-control-plane"
    namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["aws-load-balancer-controller"]
      }
    }

    ingress {
      ports {
        port     = "9443"
        protocol = "TCP"
      }

      dynamic "from" {
        for_each = local.aws-load-balancer-controller["allowed_cidrs"]
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

/*
# Prepare ECR repos for images, strip registry/tag off the images names
# image data can inlcude registry and/or tag, which will be handled properly
# TODO: make this a snippet to use it for all addons in the repo
resource "aws_ecr_repository" "this" {
  for_each = {
    for _, v in local.aws-load-balancer-controller["containers"] :
    # returns a dict of {shortname => null]}
    replace(replace(v["name"][keys(v["name"])[0]],
      "${lookup(v, "registry", v["source"])}/", ""),
      ":${lookup(v, "ver", { "tag" : "latest" })[keys(lookup(v, "ver", ["tag"]))[0]]}", "") => null if(
      lookup(v, "name", null) != null &&
      local.aws-load-balancer-controller["ecr_prepare_images"] &&
      (lookup(v, "registry", null) != null || lookup(v, "source", null) != null)
    ) # ? true : false
  }
  name                 = each.key
  image_tag_mutability = local.aws-load-balancer-controller["ecr_immutable_tag"] ? "IMMUTABLE" : "MUTABLE"

  image_scanning_configuration {
    scan_on_push = local.aws-load-balancer-controller["ecr_scan_on_push"]
  }

  encryption_configuration {
    encryption_type = local.aws-load-balancer-controller["ecr_encryption_type"]
    kms_key         = local.aws-load-balancer-controller["ecr_encryption_type"] == "KMS" ? local.aws-load-balancer-controller["ecr_kms_key"] : null
  }
}

resource "skopeo_copy" "this" {
  for_each = {
    for _, v in local.aws-load-balancer-controller["containers"] :
    # returns a dict of {shortname => [src_reigstry, parsed_tag]}
    replace(replace(v["name"][keys(v["name"])[0]],
      "${lookup(v, "registry", v["source"])}/", ""),
      ":${lookup(v, "ver", { "tag" : "latest" })[keys(lookup(v, "ver", ["tag"]))[0]]}", "") => [
      lookup(v, "source", null) != null ? v["source"] : v["registry"][keys(v["registry"])[0]],
      lookup(v, "ver", { "tag" : "latest" })[keys(lookup(v, "ver", ["tag"]))[0]]
      ] if(
      lookup(v, "name", null) != null &&
      local.aws-load-balancer-controller["ecr_prepare_images"] &&
      (lookup(v, "registry", null) != null || lookup(v, "source", null) != null)
    ) # ? true : false
  }
  source_image      = "docker://${each.value[0]}/${each.key}:${each.value[1]}"
  destination_image = "docker://${aws_ecr_repository.this[each.key].repository_url}:${each.value[1]}"
  keep_image        = true

  depends_on = [
    aws_ecr_repository.this
  ]
} */
