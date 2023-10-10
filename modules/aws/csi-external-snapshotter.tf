locals {
  csi-external-snapshotter_manifests_version = try(
    var.csi-external-snapshotter.manifests_version, ""
  ) != "" ? var.csi-external-snapshotter.manifests_version : local.helm_dependencies[index(local.helm_dependencies.*.name, "csi-external-snapshotter")].manifests_version
  csi-external-snapshotter = merge(
    {
      create_ns                 = false
      namespace                 = "csi-snapshotter"
      enabled                   = false
      extra_values              = ""
      extra_tpl                 = {}
      kustomizations            = {}
      kustomizations_images_map = {}
      kustomize_external        = false
      # Kustomize resources
      resources = [
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/deploy/kubernetes/csi-snapshotter/setup-csi-snapshotter.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter_manifests_version}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
      ]
      vpa_enable          = false
      images_data         = {}
      images_repos        = {}
      containers_versions = {}
    },
    var.csi-external-snapshotter
  )
}

resource "kubernetes_namespace" "csi-external-snapshotter" {
  count = local.csi-external-snapshotter.enabled && local.csi-external-snapshotter.create_ns ? 1 : 0

  metadata {
    labels = merge({
      name = local.csi-external-snapshotter.namespace
      }, local.vpa["vpa_only_recommend"] && local.csi-external-snapshotter["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.csi-external-snapshotter.namespace
  }
}

module "deploy_csi-external-snapshotter" {
  count  = local.csi-external-snapshotter["enabled"] ? 1 : 0
  source = "./deploy"
  # Kustomize manager data
  kustomizations                        = local.csi-external-snapshotter.kustomizations
  kustomizations_images_map             = local.csi-external-snapshotter.kustomizations_images_map
  kustomize_resources                   = local.csi-external-snapshotter.resources
  kustomize_resources_manifests_version = local.csi-external-snapshotter_manifests_version
  # Extra manager data
  extra_tpl           = local.csi-external-snapshotter.extra_tpl
  values              = [local.csi-external-snapshotter.extra_values]
  images_data         = local.csi-external-snapshotter["images_data"]
  images_repos        = local.csi-external-snapshotter["images_repos"]
  containers_versions = local.csi-external-snapshotter.containers_versions
  # not using helm for this addon
  helm_deploy = false

  depends_on = [kubernetes_namespace.csi-external-snapshotter]
}
