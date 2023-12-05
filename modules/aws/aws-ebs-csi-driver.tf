locals {
  aws-ebs-csi-driver = merge(
    local.helm_defaults,
    {
      name          = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-ebs-csi-driver")].name
      chart         = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-ebs-csi-driver")].name
      repository    = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-ebs-csi-driver")].repository
      chart_version = local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-ebs-csi-driver")].version
      namespace     = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "aws-ebs-csi-driver")].namespace, "kube-system")
      create_ns     = false
      service_account_names = {
        controller = "ebs-csi-controller-sa"
        node       = "ebs-csi-node-sa"
      }
      create_iam_resources_irsa = true
      create_storage_class      = true
      storage_class_name        = "ebs-sc"
      is_default_class          = false
      enabled                   = false
      iam_policy_override       = null
      default_network_policy    = true
      create_kms_key            = true
      existing_kms_key_arn      = null
      override_kms_alias        = null
      use_kms                   = false
      use_encryption            = false
      extra_sc_parameters       = {}
      kms_enable_key_rotation   = true
      volume_snapshot_class     = <<-VOLUME_SNAPSHOT_CLASS
          apiVersion: snapshot.storage.k8s.io/v1
          kind: VolumeSnapshotClass
          metadata:
            name: csi-aws-vsc
            labels:
              velero.io/csi-volumesnapshot-class: "true"
              snapshot.storage.kubernetes.io/is-default-class: "false"
          driver: ebs.csi.aws.com
        VOLUME_SNAPSHOT_CLASS
      reclaim_policy            = "Delete"
      name_prefix               = "${var.cluster-name}-aws-ebs-csi-driver"
      vpa_enable                = false
      images_data               = { containers = {} }
      images_repos              = { repos = {} }
      containers_versions       = {}
    },
    var.aws-ebs-csi-driver
  )

  values_aws-ebs-csi-driver = <<VALUES
controller:
  k8sTagClusterId: ${var.cluster-name}
  extraCreateMetadata: true
  priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
  serviceAccount:
    name: ${local.aws-ebs-csi-driver["service_account_names"]["controller"]}
    annotations:
      eks.amazonaws.com/role-arn: "${local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_iam_resources_irsa"] ? module.iam_assumable_role_aws-ebs-csi-driver.iam_role_arn : ""}"
node:
  tolerateAllTaints: true
  priorityClassName: ${local.priority-class-ds["create"] ? kubernetes_priority_class.kubernetes_addons_ds[0].metadata[0].name : ""}
VALUES
}

module "iam_assumable_role_aws-ebs-csi-driver" {
  source                     = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                    = "~> 5.0"
  create_role                = local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_iam_resources_irsa"]
  role_name                  = local.aws-ebs-csi-driver["name_prefix"]
  provider_url               = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns           = local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_iam_resources_irsa"] ? [aws_iam_policy.aws-ebs-csi-driver[0].arn] : []
  number_of_role_policy_arns = 1
  oidc_fully_qualified_subjects = [
    "system:serviceaccount:${local.aws-ebs-csi-driver["namespace"]}:${local.aws-ebs-csi-driver["service_account_names"]["controller"]}",
  ]
  tags = local.tags
}

data "aws_iam_policy_document" "aws-ebs-csi-driver" {
  count = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.create_iam_resources_irsa ? 1 : 0
  source_policy_documents = [
    data.aws_iam_policy_document.aws-ebs-csi-driver_default.0.json,
    local.aws-ebs-csi-driver.use_kms && local.aws-ebs-csi-driver.use_encryption ? data.aws_iam_policy_document.aws-ebs-csi-driver_kms.0.json : jsonencode({})
  ]
}

data "aws_iam_policy_document" "aws-ebs-csi-driver_kms" {
  count = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.use_kms && local.aws-ebs-csi-driver.use_encryption ? 1 : 0
  source_policy_documents = [
    templatefile("${path.module}/iam/aws-ebs-csi-driver_kms.json", { kmsKeyId = local.aws-ebs-csi-driver.create_kms_key ? aws_kms_key.aws-ebs-csi-driver.0.arn : local.aws-ebs-csi-driver.existing_kms_key_arn }),
  ]
}

data "aws_iam_policy_document" "aws-ebs-csi-driver_default" {
  count = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.create_iam_resources_irsa ? 1 : 0
  source_policy_documents = [
    templatefile("${path.module}/iam/aws-ebs-csi-driver.json", { arn-partition = local.arn-partition }),
  ]
}

resource "aws_iam_policy" "aws-ebs-csi-driver" {
  count  = local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_iam_resources_irsa"] ? 1 : 0
  name   = local.aws-ebs-csi-driver["name_prefix"]
  policy = local.aws-ebs-csi-driver["iam_policy_override"] == null ? data.aws_iam_policy_document.aws-ebs-csi-driver.0.json : local.aws-ebs-csi-driver["iam_policy_override"]
  tags   = local.tags
}

resource "kubernetes_namespace" "aws-ebs-csi-driver" {
  count = local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_ns"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.aws-ebs-csi-driver["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.aws-ebs-csi-driver["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.aws-ebs-csi-driver["namespace"]
  }
}

module "deploy_aws-ebs-csi-driver" {
  count  = local.aws-ebs-csi-driver["enabled"] ? 1 : 0
  source = "./deploy"
  # NOTE: must also process containers data for csi-external-snapshotter
  #dependencies          = [for _, d in local.helm_dependencies : d if d.name == "aws-ebs-csi-driver" || d.name == "csi-external-snapshotter"]
  images_data           = local.aws-ebs-csi-driver["images_data"]
  images_repos          = local.aws-ebs-csi-driver["images_repos"]
  containers_versions   = local.aws-ebs-csi-driver["containers_versions"]
  repository            = local.aws-ebs-csi-driver["repository"]
  name                  = local.aws-ebs-csi-driver["name"]
  chart                 = local.aws-ebs-csi-driver["chart"]
  chart_version         = local.aws-ebs-csi-driver["chart_version"]
  timeout               = local.aws-ebs-csi-driver["timeout"]
  force_update          = local.aws-ebs-csi-driver["force_update"]
  recreate_pods         = local.aws-ebs-csi-driver["recreate_pods"]
  wait                  = local.aws-ebs-csi-driver["wait"]
  atomic                = local.aws-ebs-csi-driver["atomic"]
  cleanup_on_fail       = local.aws-ebs-csi-driver["cleanup_on_fail"]
  dependency_update     = local.aws-ebs-csi-driver["dependency_update"]
  disable_crd_hooks     = local.aws-ebs-csi-driver["disable_crd_hooks"]
  disable_webhooks      = local.aws-ebs-csi-driver["disable_webhooks"]
  render_subchart_notes = local.aws-ebs-csi-driver["render_subchart_notes"]
  replace               = local.aws-ebs-csi-driver["replace"]
  reset_values          = local.aws-ebs-csi-driver["reset_values"]
  reuse_values          = local.aws-ebs-csi-driver["reuse_values"]
  helm_upgrade          = local.aws-ebs-csi-driver["helm_upgrade"]
  skip_crds             = local.aws-ebs-csi-driver["skip_crds"]
  verify                = local.aws-ebs-csi-driver["verify"]
  values = [
    local.values_aws-ebs-csi-driver,
    local.aws-ebs-csi-driver["extra_values"]
  ]

  namespace = local.aws-ebs-csi-driver["create_ns"] ? kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index] : local.aws-ebs-csi-driver["namespace"]
}

resource "kubernetes_storage_class" "aws-ebs-csi-driver" {
  count = local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["create_storage_class"] ? 1 : 0
  metadata {
    name = local.aws-ebs-csi-driver["storage_class_name"]
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = tostring(local.aws-ebs-csi-driver["is_default_class"])
    }
  }
  reclaim_policy         = local.aws-ebs-csi-driver.reclaim_policy
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = merge(
    {
      encrypted = local.aws-ebs-csi-driver.use_encryption
      kmsKeyId  = local.aws-ebs-csi-driver.use_encryption ? local.aws-ebs-csi-driver.use_kms ? local.aws-ebs-csi-driver.create_kms_key ? aws_kms_key.aws-ebs-csi-driver.0.arn : local.aws-ebs-csi-driver.existing_kms_key_arn : "" : ""
    },
    local.aws-ebs-csi-driver.extra_sc_parameters
  )
}

resource "kubernetes_network_policy" "aws-ebs-csi-driver_default_deny" {
  count = local.aws-ebs-csi-driver["create_ns"] && local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "aws-ebs-csi-driver_allow_namespace" {
  count = local.aws-ebs-csi-driver["create_ns"] && local.aws-ebs-csi-driver["enabled"] && local.aws-ebs-csi-driver["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.aws-ebs-csi-driver.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "aws_kms_key" "aws-ebs-csi-driver" {
  count               = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.use_kms && local.aws-ebs-csi-driver.create_kms_key ? 1 : 0
  tags                = local.tags
  enable_key_rotation = local.aws-ebs-csi-driver.kms_enable_key_rotation
}

resource "aws_kms_alias" "aws-ebs-csi-driver" {
  count         = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.use_kms && local.aws-ebs-csi-driver.create_kms_key ? 1 : 0
  name          = "alias/aws-ebs-csi-driver-${local.aws-ebs-csi-driver.override_kms_alias != null ? local.aws-ebs-csi-driver.override_kms_alias : var.cluster-name}"
  target_key_id = aws_kms_key.aws-ebs-csi-driver.0.id
}

resource "kubectl_manifest" "aws-ebs-csi-driver_vsc" {
  count = local.aws-ebs-csi-driver.enabled && local.aws-ebs-csi-driver.volume_snapshot_class != null ? 1 : 0
  yaml_body = yamlencode(merge(
    yamldecode(local.aws-ebs-csi-driver.volume_snapshot_class),
    { deletionPolicy = local.aws-ebs-csi-driver.reclaim_policy })
  )

  depends_on = [
    module.deploy_aws-ebs-csi-driver
  ]
  server_side_apply = true
}
