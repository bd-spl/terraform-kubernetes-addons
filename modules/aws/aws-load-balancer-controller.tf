locals {
  aws-load-balancer-controller = merge(
    local.helm_defaults,
    {
      name                      = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].name
      chart                     = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].name
      repository                = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].repository
      chart_version             = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].version
      registry                  = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-load-balancer-controller")].registry, {})
      namespace                 = "aws-load-balancer-controller"
      service_account_name      = "aws-load-balancer-controller"
      create_iam_resources_irsa = true
      enabled                   = false
      iam_policy_override       = null
      default_network_policy    = true
      allowed_cidrs             = ["0.0.0.0/0"]
      name_prefix               = "${var.cluster-name}-awslbc"
      rewrite                   = false
      prepare_images            = false
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
  # simple image or tag overrides, no src registry data provided
  dynamic "set" {
    for_each = { for c, v in local.aws-load-balancer-controller["containers"] : c => v if lookup(v, "registry", null) == null ? true : false }
    content {
      name = "${set.key}.${keys(set.value)[0]}"
      value = set.value[keys(set.value)[0]]
    }
  }
  # image overrides, with rewriting possible registry path included in the image URI, based on 'registry' pattern
  # FIXME: assumes postional args: key0 should be an image
  dynamic "set" {
    for_each = { for c, v in local.aws-load-balancer-controller["containers"] : c => v if lookup(v, "registry", null) != null ? true : false }
    content {
        name = "${set.key}.${keys(set.value)[0]}"
        value = (lookup(set.value, "registry", null) == null || lookup(local.aws-load-balancer-controller["registry"], {}) == {} || !lookup(local.aws-load-balancer-controller["rewrite"], false)) ? set.value[keys(set.value)[0]] : replace(
          set.value[keys(set.value)[0]],
          "${set.value["registry"]}/",
          "${values(local.aws-load-balancer-controller["registry"])[0]}/")
      }
  }
  # optional data (like tag) overrides, ignoring special source registry values
  # FIXME: assumes postional args: key1 should be a tag
  dynamic "set" {
    for_each = { for c, v in local.aws-load-balancer-controller["containers"] : c => v if (length(v) > 2 || length(v) == 2 && (lookup(v, "registry", null) == null ? true : false)) }
    content {
        name = keys(set.value)[1] == "registry" ? "${set.key}.${keys(set.value)[2]}" : "${set.key}.${keys(set.value)[1]}"
        value = keys(set.value)[1] == "registry" ? set.value[keys(set.value)[2]] : set.value[keys(set.value)[1]]
      }
  }
  # optional registry overrides
  dynamic "set" {
    for_each = (!lookup(local.aws-load-balancer-controller["rewrite"], false) || lookup(local.aws-load-balancer-controller["registry"], {}) == {}) ? {} : local.aws-load-balancer-controller["containers"]
    content {
        name = "${set.key}.${keys(local.aws-load-balancer-controller["registry"])[0]}"
        value = values(local.aws-load-balancer-controller["registry"])[0]
      }
  }

  namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
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

# TODO: make this a snippet to use it for all addons in the repo
# assumes positional arguments exist for containers data to have it prepared: image (key 0), tag (key 1), and source registry
# image data can inlcude registry and/or tag, which will be handled properly
# FIXME: unsorted dicts may confuse image with tag, so preparing commands will retry a reversed key1:key0 combination
resource "null_resource" "aws_lbc_prepare_images" {
  for_each = { for c, v in local.aws-load-balancer-controller["containers"] : c => v if length(v) > 2 && lookup(v, "registry", null) != null ? true : false }

  triggers = {
    registry     = jsonencode(lookup(var.aws-load-balancer-controller, "registry", null))
    containers   = jsonencode(lookup(var.aws-load-balancer-controller, "containers", null))
    filemd5      = filemd5("modules/aws/aws-load-balancer-controller.tf")
  }

  # NOTE: for private EKS cluster we need to pull, tag and push required images to private ECR
  # requires podman logged in for dst ECR registry, and image:tag destination should exist in that registry
  provisioner "local-exec" {
    command = lookup(local.aws-load-balancer-controller, "prepare_images") ? "echo skip prepare images for ${each.key}" : <<EOF
      IMG=${replace(each.value[keys(each.value)[0]], "${each.value["registry"]}/", "")}
      TAG=${each.value[keys(each.value)[1]]}
      SRC=${each.value["registry"]}/$\{IMG%:*\}:$TAG
      podman pull $SRC
      if [ $? -ne 0 ]; then
        IMG=${replace(each.value[keys(each.value)[1]], "${each.value["registry"]}/", "")}
        TAG=${each.value[keys(each.value)[0]]}
        SRC=${each.value["registry"]}/$\{IMG%:*\}:$TAG
        podman pull $SRC
      fi
      DST=${values(local.aws-load-balancer-controller["registry"])[0]}/$\{IMG%:*\}:$TAG
      podman tag $(podman inspect $SRC -f json --format={{.Id}} 2>/dev/null) $DST
      podman push $DST
  EOF
  }
}

