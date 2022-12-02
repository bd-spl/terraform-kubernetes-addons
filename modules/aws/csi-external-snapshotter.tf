locals {

  csi-external-snapshotter = merge(
    {
      create_ns = false
      namespace = "csi-snapshotter"
      enabled   = false
      version   = "v6.0.1"
      # NOTE: the caller side must override subjects' namespaces
      # as kubectl_manifest's override_namespace cannot do that.
      # See https://github.com/gavinbunney/terraform-provider-kubectl/issues/235.
      # Targets for patching will match by keys named as <fetched YAML files type>.<metadata.name>.<kind>
      extra_values = {}
    },
    var.csi-external-snapshotter
  )

  yaml_files = {
    crd-snapshot-classes      = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml",
    crd-snapshot-contents     = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml",
    crd-snapshots             = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml",
    setup-snapshot-controller = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml",
    setup-csi-snapshotter     = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/csi-snapshotter/setup-csi-snapshotter.yaml",
    rbac-snapshot-controller  = "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${local.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
  }

  # Adhoc workarounds for missing things to merge with YAML manifests defined above
  # Define each item in the list as <fetched YAML files type>.<metadata.name>.<kind>
  csi-external-snapshotter_fixes = <<-EOT
    - setup-csi-snapshotter.csi-snapshotter.ServiceAccount:
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: csi-snapshotter
    EOT

  #TODO(bogdando): create a shared template and refer it in addons managed by kubectl_manifest (copy-pasta until then)
  csi-external-snapshotter_containers_data = {
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

  csi-external-snapshotter_patches = {
    for k, v in try(yamldecode(try(local.csi-external-snapshotter.extra_values, "---")), {}) : k => v
  }

  # Template patches containing REWRITE_* args with the prepared containers images data values
  # FIXME: No support for CR templates but only pods standard '*.spec.template.spec.containers' paths.
  # NOTE: containers data does not contain the Kind data subfield, so strip it off the patches names
  # TODO(bogdando): find a better templating method (maybe use https://github.com/cloudposse/terraform-yaml-config)
  csi-external-snapshotter-extra-values_patched = {
    for k, v in local.csi-external-snapshotter_patches :
    k => [
      # to deepmerge the original and templated patches later, if anything there to rewrite
      v,
      try(
        { spec = { template = { spec = { containers = [
          for c in v.spec.template.spec.containers :
          yamldecode(
            replace(
              replace(
                replace(
                  yamlencode(c),
                  "REWRITE_ALL",
                  format("%s:%s",
                    local.csi-external-snapshotter_containers_data[format("%s.%s.repository", split(".", k)[0], c.name)].repo,
                    local.csi-external-snapshotter_containers_data[format("%s.%s.repository", split(".", k)[0], c.name)].tag
                  )
                ),
                "REWRITE_TAG",
                local.csi-external-snapshotter_containers_data[format("%s.%s.repository", split(".", k)[0], c.name)].tag
              ),
              "REWRITE_NAME",
              local.csi-external-snapshotter_containers_data[format("%s.%s.repository", split(".", k)[0], c.name)].repo
            )
          )
        ] } } } },
        {}
      )
    ]
  }

  # Decode feteched manifests/CRDs etc documents and skip blobs without data
  csi-external-snapshotter_yaml_files_decoded = {
    for name, uri in local.yaml_files :
    name => [
      for content in split("---", try(data.http.csi-external-snapshotter[uri].response_body, "---")) :
      yamldecode(content) if try(yamldecode(content), null) != null
    ]
  }

  # Split decoded data into separate resources manifests, with keys
  # matching the patched data index
  csi-external-snapshotter_kube_manifests = concat(yamldecode(local.csi-external-snapshotter_fixes), flatten([
    for name, manifests in local.csi-external-snapshotter_yaml_files_decoded :
    [
      for m in manifests : { "${name}.${m.metadata.name}.${m.kind}" = m }
    ]
  ]))

  csi-external-snapshotter_manifests_apply = [
    for v in try(data.kubectl_file_documents.csi-external-snapshotter[0].documents, {}) : {
      data : yamldecode(v)
      content : v
    }
  ]
}

# Patch manifests with user defined overrides
module "deepmerge" {
  source = "github.com/cloudposse/terraform-yaml-config//modules/deepmerge?ref=1.0.2"
  maps = flatten([
    for m in local.csi-external-snapshotter_kube_manifests :
    [
      m,
      [
        for p in try(local.csi-external-snapshotter-extra-values_patched[
          keys(local.csi-external-snapshotter_kube_manifests[index(local.csi-external-snapshotter_kube_manifests, m)])[0]
        ], {}) : { keys(local.csi-external-snapshotter_kube_manifests[index(local.csi-external-snapshotter_kube_manifests, m)])[0] = p }
      ]
    ]
  ])

  append_list_enabled    = false
  deep_copy_list_enabled = true
}

data "http" "csi-external-snapshotter" {
  for_each = local.csi-external-snapshotter.enabled ? toset(values(local.yaml_files)) : []
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
    for v in local.csi-external-snapshotter_manifests_apply :
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
