locals {

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
  # TODO(bogdando): find a better templating method...
  # NOTE: keys naming is <manifest_file>.<container_name>.repository,
  # use the 2nd subelement to get a container overrides
  csi-external-snapshotter-extra-values_patched = {
    for k, v in local.csi-external-snapshotter-containers-data : k => {
      patch = replace(replace(replace(
        yamlencode(
          try(yamldecode(
            try(local.csi-external-snapshotter.extra_values, "---")
          )[split(".", k)[1]], {})
        ),
        "REWRITE_ALL",
        "${v.repo}:${v.tag}"
      ), "REWRITE_TAG", v.tag), "REWRITE_NAME", v.repo)
    }
  }

  # Merge manifests with user defined overrides.name
  # NOTE: keys naming is <manifest_file>.<container_name>.repository,
  # use the 1st subelement to address the manifest to patch
  csi-external-snapshotter_apply = local.csi-external-snapshotter["enabled"] ? {
    for k, v in data.kubectl_file_documents.csi-external-snapshotter[0].documents : k => {
      data : merge(
        yamldecode(v),
        yamldecode(local.csi-external-snapshotter-extra-values_patched[k].patch)
      )
    }
  } : null

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

resource "kubectl_manifest" "csi-external-snapshotter" {
  for_each = local.csi-external-snapshotter.enabled ? {
    for _, v in local.csi-external-snapshotter_apply : lower(
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
}
