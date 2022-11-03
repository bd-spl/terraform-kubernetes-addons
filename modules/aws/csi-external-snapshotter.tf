locals {

  debug = true

  csi-external-snapshotter = merge(
    {
      create_ns    = false
      namespace    = "csi-snapshotter"
      enabled      = false
      version      = "v6.0.1"
      extra_values = {}
    },
    var.csi-external-snapshotter
  )

  csi-external-snapshotter_yaml_files = {
    crd-snapshot-classes      = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml",
    crd-snapshot-contents     = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml",
    crd-snapshots             = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml",
    setup-snapshot-controller = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml",
    setup-csi-snapshotter     = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/csi-snapshotter/setup-csi-snapshotter.yaml",
    rbac-snapshot-controller  = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
  }

  #TODO(bogdando): create a shared template and refer it in addons managed by kubectl_manifest (copy-pasta until then)
  csi-external-snapshotter-containers-data = {
    for k, v in local.images_data.csi-external-snapshotter.containers :
    v.rewrite_values.image.name => {
      tag = try(
        local.csi-external-snapshotter["containers_versions"][v.rewrite_values.tag.name],
        v.rewrite_values.tag.value,
        v.rewrite_values.image.tail
      )
      repo = v.ecr_prepare_images && v.source_provided ? "${
        aws_ecr_repository.this[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].repository_url}" : v.ecr_prepare_images ? "${
        aws_ecr_repository.this[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].name
      }" : v.rewrite_values.image.value
    }
  }

  # Rewrite patches templates in extra_values with the prepared containers images data
  # TODO(bogdando): find a better templating method (maybe use https://github.com/cloudposse/terraform-yaml-config)
  csi-external-snapshotter-extra-values_patched = {
    for k, v in local.csi-external-snapshotter-containers-data :
    split(".", k)[0] =>
    yamldecode(replace(replace(replace(
      yamlencode(
        yamldecode(
          try(local.csi-external-snapshotter.extra_values, "---")
        )[join(".", slice(split(".", k), 0, 2))]
      ),
      "REWRITE_ALL",
      "${v.repo}:${v.tag}"
      ), "REWRITE_TAG", v.tag), "REWRITE_NAME", v.repo))... if try(yamldecode(
      try(local.csi-external-snapshotter.extra_values, "---")
    )[join(".", slice(split(".", k), 0, 2))], null) != null
  }

  # Decode feteched manifests/CRDs etc documents and skip blobs without data
  kube_manifests = {
    for i, e in local.csi-external-snapshotter_yaml_files :
    i => [
      for d in split("---", data.http.csi-external-snapshotter[e].response_body) :
      yamldecode(d) if try(yamldecode(d), null) != null
    ]
  }
}

# Patch manifests with user defined overrides, whenever its kind and metadata name matches the target resource ones
module "deepmerge" {
  source = "github.com/cloudposse/terraform-yaml-config//modules/deepmerge?ref=1.0.2"
  maps = flatten([
    for k, v in local.kube_manifests :
    [
      { data = { "${k}" = v } },
      { data = { "${k}" = [
        for n in v : local.csi-external-snapshotter-extra-values_patched[k][0] if try(
          local.csi-external-snapshotter-extra-values_patched[k][0], null
          ) != null && try(
          n.kind, null
          ) == try(
          local.csi-external-snapshotter-extra-values_patched[k][0].kind, null
          ) && try(
          n.metadata.name, null
          ) == try(
          local.csi-external-snapshotter-extra-values_patched[k][0].metadata.name, null
        )
        ] }
      }
  ]])

  append_list_enabled    = false
  deep_copy_list_enabled = true
}

resource "local_file" "kube_manifests_debug" {
  count    = local.debug ? 1 : 0
  content  = <<-EOT
    === fetched and decoded ===
    ${yamlencode(local.kube_manifests)}
    === patched and encoded ===
    ${yamlencode(data.kubectl_file_documents.csi-external-snapshotter)}
    === merged data ===
    ${yamlencode(module.deepmerge.merged)}
    EOT
  filename = "/tmp/debug-csi-external-snapshotter-manifests"

  depends_on = [
    module.deepmerge
  ]
}

data "http" "csi-external-snapshotter" {
  for_each = local.csi-external-snapshotter.enabled ? toset(values(local.csi-external-snapshotter_yaml_files)) : []
  url      = each.key
}

data "kubectl_file_documents" "csi-external-snapshotter" {
  count   = local.csi-external-snapshotter.enabled ? 1 : 0
  content = join("\n---\n", [for k, v in data.http.csi-external-snapshotter : v.response_body])
}

resource "kubernetes_namespace" "csi-external-snapshotter" {
  count = local.csi-external-snapshotter.enabled && local.csi-external-snapshotter.create_ns ? 1 : 0

  metadata {
    labels = {
      name = local.csi-external-snapshotter.namespace
    }

    name = local.csi-external-snapshotter.namespace
  }
}

/*resource "kubectl_manifest" "csi-external-snapshotter" {
  for_each = local.csi-external-snapshotter.enabled ? {
    for _, v in values(module.deepmerge.merged) : lower(
      join("/", compact(
        [v.data.apiVersion,
          v.data.kind,
    lookup(v.data.metadata, "namespace", local.csi-external-snapshotter.namespace), v.data.metadata.name]))) => yamlencode(v.data)
  } : {}
  yaml_body = each.value

  depends_on = [
    kubernetes_namespace.csi-external-snapshotter,
    skopeo_copy.this
  ]
}*/
