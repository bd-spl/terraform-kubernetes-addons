locals {

  csi-external-snapshotter = merge(
    {
      create_ns          = false
      namespace          = "csi-snapshotter"
      enabled            = false
      extra_values       = {}
      kustomize_external = false
      # Kustomize resources
      resources = [
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/deploy/kubernetes/csi-snapshotter/setup-csi-snapshotter.yaml",
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${var.csi-external-snapshotter.version}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
      ]
    },
    var.csi-external-snapshotter
  )

  #TODO(bogdando): create a shared template, or a module, and refer it in addons managed by kustomize (copy-pasta until then)
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
      src = v.src
    } if v.manager == "kustomize" || v.manager == "extra"
  }

  ## Kuztomize prepare images manager

  # Update kustomizations with the prepared containers images data
  csi-external-snapshotter_containers_kustomizations_patched = {
    for k, data in local.csi-external-snapshotter.kustomizations :
    k => [for v in compact(split("---", data)) :
      merge(
        try(yamldecode(v), {}),
        {
          resources = lookup(
            try(yamldecode(v), {}),
            "resources",
            local.csi-external-snapshotter.resources
          )
        },
        lookup(try(yamldecode(v), {}), "images", null) == null ? {} : {
          images = [
            for c in try(yamldecode(v).images, []) :
            {
              # Remove unique identifiers distinguishing same images used for different containers
              name = split("::", c.name)[0]
              newName = local.csi-external-snapshotter_containers_data[
                format(
                  "%s.%s.repository",
                  k,
                  split("::", local.csi-external-snapshotter.kustomizations_images_map[k][c.name])[0]
                )
              ].repo
              newTag = try(c.newTag, local.csi-external-snapshotter_containers_data[
                format(
                  "%s.%s.repository",
                  k,
                  split("::", local.csi-external-snapshotter.kustomizations_images_map[k][c.name])[0]
                )
              ].tag)
            }
          ]
        }
    )]
  }
}

# FIXME: local_sensitive_file maybe?
resource "local_file" "csi-external-snapshotter-kustomization" {
  for_each = local.csi-external-snapshotter_containers_kustomizations_patched

  # reconstruct multi-kustomizations sections from the patched data
  content  = join("\n---\n", [for data in each.value : yamlencode(data)])
  filename = "./kustomization-${each.key}/kustomization/kustomization.yaml"

  depends_on = [
    skopeo_copy.this
  ]
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

resource "null_resource" "csi-external-snapshotter-kustomize" {
  for_each = local.csi-external-snapshotter_containers_kustomizations_patched
  triggers = {
    kustomizations = join("\n---\n", [for data in each.value : yamlencode(data)])
    filemd5        = filemd5("csi-external-snapshotter.tf")
  }

  provisioner "local-exec" {
    command = local.csi-external-snapshotter.kustomize_external ? "kustomize build ./kustomization-${each.key}/kustomization | kubectl apply -f -" : "kubectl apply -k ./kustomization-${each.key}/kustomization"
  }

  depends_on = [
    local_file.csi-external-snapshotter-kustomization,
    kubernetes_namespace.csi-external-snapshotter
  ]
}
