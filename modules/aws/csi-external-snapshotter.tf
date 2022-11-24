locals {

  csi-external-snapshotter = merge(
    {
      create_ns = false
      namespace = "csi-snapshotter"
      enabled   = false
      version   = "v6.0.1"
      # NOTE: the caller side must override roleRef/subjects' namespaces
      # as kubectl_manifest's override_namespace cannot do that.
      # See https://github.com/gavinbunney/terraform-provider-kubectl/issues/235.
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
  containers_data = {
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

  patches = {
    for k, v in yamldecode(try(local.csi-external-snapshotter.extra_values, "---")) : k => v
  }

  # Template patches containing REWRITE_* args with the prepared containers images data values
  # TODO(bogdando): find a better templating method (maybe use https://github.com/cloudposse/terraform-yaml-config)
  csi-external-snapshotter-extra-values_patched = {
    for k, v in local.patches :
    "${k}.${v.kind}" => try(local.containers_data["${k}.repository"], null) == null ? v : yamldecode(
      replace(
        replace(
          replace(
            yamlencode(try(local.patches[join(".", slice(split(".", k), 0, 2))], null)),
            "REWRITE_ALL",
            format("%s:%s",
              local.containers_data["${k}.repository"].repo,
              local.containers_data["${k}.repository"].tag
            )
          ),
          "REWRITE_TAG",
          local.containers_data["${k}.repository"].tag
        ),
        "REWRITE_NAME",
        local.containers_data["${k}.repository"].repo
      )
    )
  }

  # Decode feteched manifests/CRDs etc documents and skip blobs without data
  csi-external-snapshotter_yaml_files_decoded = {
    for name, uri in local.csi-external-snapshotter_yaml_files :
    name => [
      for content in split("---", data.http.csi-external-snapshotter[uri].response_body) :
      yamldecode(content) if try(yamldecode(content), null) != null
    ]
  }

  # Split decoded data into separate resources manifests, with keys
  # matching the patched data index
  kube_manifests = flatten([
    for name, manifests in local.csi-external-snapshotter_yaml_files_decoded :
    [
      for m in manifests : { "${name}.${m.metadata.name}.${m.kind}" = m }
    ]
  ])

  csi-external-snapshotter_apply = [
    for v in data.kubectl_file_documents.csi-external-snapshotter[0].documents : {
      data : yamldecode(v)
      content : v
    }
  ]
}

# Patch manifests with user defined overrides
module "deepmerge" {
  source = "github.com/cloudposse/terraform-yaml-config//modules/deepmerge?ref=1.0.2"
  maps = flatten([
    for m in local.kube_manifests :
    [
      m,
      { keys(local.kube_manifests[index(local.kube_manifests, m)])[0] = try(
        local.csi-external-snapshotter-extra-values_patched[
          keys(local.kube_manifests[index(local.kube_manifests, m)])[0]
        ], {}
        )
      }
    ]
  ])

  append_list_enabled    = false
  deep_copy_list_enabled = true
}

data "http" "csi-external-snapshotter" {
  for_each = local.csi-external-snapshotter.enabled ? toset(values(local.csi-external-snapshotter_yaml_files)) : []
  url      = each.key
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

# Combine processed manifests into a yaml blob as it's required for kubectl_file_documents
data "kubectl_file_documents" "csi-external-snapshotter" {
  count   = local.csi-external-snapshotter.enabled ? 1 : 0
  content = join("\n---\n", [for v in values(module.deepmerge.merged) : yamlencode(v)])
}

resource "kubectl_manifest" "csi-external-snapshotter" {
  for_each = {
    for v in local.csi-external-snapshotter_apply :
    lower(join("/", compact(
      [
        v.data.apiVersion,
        v.data.kind,
        local.csi-external-snapshotter.create_ns ? local.csi-external-snapshotter.namespace : lookup(v.data.metadata, "namespace", ""),
        v.data.metadata.name
      ]
    ))) => v.content
  }
  yaml_body          = each.value
  override_namespace = local.csi-external-snapshotter.create_ns ? local.csi-external-snapshotter.namespace : "kube-system"

  depends_on = [
    kubernetes_namespace.csi-external-snapshotter,
    module.deepmerge,
    data.kubectl_file_documents.csi-external-snapshotter,
    skopeo_copy.this
  ]
}
