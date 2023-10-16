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
      use_deploy_module   = true
      images_data         = { containers = {} }
      images_repos        = { repos = {} }
      containers_versions = {}
    },
    var.csi-external-snapshotter
  )

  # FIXME
  csi-external-snapshotter_containers_data = {
    for k, v in local.csi-external-snapshotter["images_data"].containers :
    v.rewrite_values.image.name => {
      tag = try(
        local.csi-external-snapshotter["containers_versions"][v.rewrite_values.tag.name],
        v.rewrite_values.tag.value,
        v.rewrite_values.image.tail
      )
      repo = v.ecr_prepare_images && v.source_provided ? try(
        local.csi-external-snapshotter["images_repos"].repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].repository_url, "") : v.ecr_prepare_images ? try(
        local.csi-external-snapshotter["images_repos"].repos[
          format("%s.%s", split(".", k)[0], split(".", k)[2])
        ].name, ""
      ) : v.rewrite_values.image.value
      src = v.src
    } if v.manager == "kustomize" || v.manager == "extra"
  }

  ## Kuztomize prepare images manager

  # Update kustomizations with the prepared containers images data
  csi-external-snapshotter_kustomizations_patched = flatten([
    for k, data in local.csi-external-snapshotter.kustomizations :
    [for v in compact(split("---", data)) :
      replace(
        yamlencode(merge(
          try(yamldecode(v), {}),
          {
            resources = lookup(
              try(yamldecode(v), {}),
              "resources",
              local.csi-external-snapshotter.resources
            )
          },
          length(lookup(try(yamldecode(v), {}), "images", {})) == 0 ? {} : {
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
                newTag = try(c.newTag, "") != "" ? c.newTag : local.csi-external-snapshotter_containers_data[
                  format(
                    "%s.%s.repository",
                    k,
                    split("::", local.csi-external-snapshotter.kustomizations_images_map[k][c.name])[0]
                  )
                ].tag
              }
            ]
          }
          )
        ),
      "$manifest_version", local.csi-external-snapshotter_manifests_version)
    ]
  ])
  # FIXME END
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
  count  = local.csi-external-snapshotter["enabled"] && local.csi-external-snapshotter["use_deploy_module"] ? 1 : 0
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

# FIXME
resource "local_file" "csi-external-snapshotter-kustomization" {
  for_each = local.csi-external-snapshotter.enabled && !local.csi-external-snapshotter["use_deploy_module"] ? zipmap(
    [for c in local.csi-external-snapshotter_kustomizations_patched : md5(c)],
    local.csi-external-snapshotter_kustomizations_patched
  ) : {}

  content  = each.value
  filename = "./kustomization-${each.key}/kustomization/kustomization.yaml"

  depends_on = [
    local_file.csi-external-snapshotter-manifests
  ]
}

resource "local_file" "csi-external-snapshotter-manifests" {
  for_each = local.csi-external-snapshotter.enabled && !local.csi-external-snapshotter["use_deploy_module"] ? var.csi-external-snapshotter.kustomizations_extra_resources : {}

  content  = each.value
  filename = "kustomizations-extra-resources/${each.key}.yaml"
}

resource "null_resource" "csi-external-snapshotter-kubectl" {
  for_each = local.csi-external-snapshotter.enabled && !local.csi-external-snapshotter["use_deploy_module"] ? var.csi-external-snapshotter.kustomizations_extra_resources : {}

  triggers = {
    kustomization = each.value
    filemd5       = filemd5("csi-external-snapshotter.tf")
    filemd5       = filemd5("../../helm-dependencies.yaml")
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ./kustomizations-extra-resources/${each.key}.yaml"
  }

  depends_on = [
    local_file.csi-external-snapshotter-kustomization,
    kubernetes_namespace.csi-external-snapshotter
  ]
}

resource "null_resource" "csi-external-snapshotter-kustomize" {
  for_each = local.csi-external-snapshotter.enabled && !local.csi-external-snapshotter["use_deploy_module"] ? zipmap(
    [for c in local.csi-external-snapshotter_kustomizations_patched : md5(c)],
    local.csi-external-snapshotter_kustomizations_patched
  ) : {}

  triggers = {
    kustomization = each.key
    filemd5       = filemd5("csi-external-snapshotter.tf")
  }

  provisioner "local-exec" {
    command = local.csi-external-snapshotter.kustomize_external ? "kustomize build ./kustomization-${each.key}/kustomization | kubectl apply -f -" : "kubectl apply -k ./kustomization-${each.key}/kustomization"
  }

  depends_on = [
    null_resource.csi-external-snapshotter-kubectl
  ]
}
