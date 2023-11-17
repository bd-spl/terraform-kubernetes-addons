# terraform-kubernetes-addons:aws

[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/terraform-kubernetes-addons)
[![terraform-kubernetes-addons](https://github.com/particuleio/terraform-kubernetes-addons/workflows/terraform-kubernetes-addons/badge.svg)](https://github.com/particuleio/terraform-kubernetes-addons/actions?query=workflow%3Aterraform-kubernetes-addons)

## About

Provides various Kubernetes addons that are often used on Kubernetes with AWS

## Documentation

User guides, feature documentation and examples are available [here](https://github.com/particuleio/teks/)

## IAM permissions

This module can uses [IRSA](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/).

## Containers manager for AWS ECR

Each EKS addon in this repo may be given additional data in ``helm-dependencies.yaml``
to prepare ECR containers images for using it in private EKS clusters, for example.
Skopeo will copy images from the given source/registry into ensured ECR repos.

There are source/registry paths used to overwrite for helm and/or to prepared images.
It also can provide helm values override paths for image/tag data. For addons not
managed with ``helm_release``, but ``kubectl_manifest``, or kustomize, you can still
provide containers data in the same file and similar format.

Supported containers images data managers are: ``helm`` (default), ``kustomize``, and ``extra``.

### Containers images data examples

An example ``helm-dependencies.yaml`` contents snippet (extended with cutom data types):
```
apiVersion: v2
dependencies:
- name: foo-addon-charts
  repository: https://foo-addon-charts.io
  version: 1.2.3
  containers:
    # Examples for Helm manager (default)
    app.foo.spec.containers.frontend:
      # results in custom.io/prod/foo:v1.1 copied as <ECR repo>/foo:v1.1,
      # then its helm values updated via the 'helm set' interface
      manager: helm # default. Allowed: helm, kustomize, extra
      # updater script will discover .appVersion via helm search CLI based on that.
      # if not provided, it will poke .ver.version to the most recent tag
      chart: foo-addon-charts
      name:
        uri: foo # sets image for helm as app.foo.spec.containers.frontend.uri
      ver:
        # whenever executed, updater script replaces it with the best value
        # that matches appVersion of its Helm release version (1.2.3)
        version: v1.1 # sets tag for helm as app.foo.spec.containers.frontend.version

      # Optional ECR settings (not for helm), override the addons module vars
      ecr_immutable_tag: false
      ecr_scan_on_push: false
      ecr_encryption_type: KMS
      ecr_kms_key: my-kms-key

      # Either to prepare images in ECR, or just override the helm values.
      # Disabling it makes the 'source' data ignored. The name/registry values
      # then end up in helm as provided (i.e. no paths rewriting for ECR)
      ecr_prepare_images: true

      # Assumes the 'name' holds a shortname instead of URI.
      # When 'source' is unset, skopeo_copy takes this as a source, and ECR as a dst.
      # Helm takes the prepared ECR repo URL value, or the original value, if
      # 'ecr_prepare_images' was disabled.
      registry:
        # sets registry for helm as app.foo.spec.containers.frontend.repository,
        # based on ecr_prepare_images enabled, or not
        repository: custom.io/prod # used as a source only, or as a final value

      # Ignored when ecr_prepare_images is off.
      # Use this instead of 'registry', if image name is URI and already includes the
      # registry path. Then the registry path in the name will get overwritten by the
      # prepared ECR repositroy replacing the source value of it.
      # NOTE: to rewrite helm 'source' value, define it as {registry: {source: ...}}
      source: custom.io/prod  # cannot end with a slash /

    extra.image:
      # Has ecr_prepare_images enabled by default
      name:
        # NOTE: the registry path part of URI must be the same as in the source, e.g.:
        # custom.io, or custom.io/dev (ambiguous names might require the former notation)
        image_uri: custom.io/dev/baz # Helm takes prepared <ECR>/dev/baz:latest
      source: custom.io  # skopeo copies it from custom.io/dev/baz:latest to ECR

    sidecar.spec.containers:
      # Helm will use custom.io/dev/qux:<whatever tag it defines>
      ecr_prepare_images: false
      name:
        image: dev/qux # sets image for helm as sidecar.spec.containers.image
      registry: # sets helm to use sidecar.spec.containers.source registry as provided
        source: custom.io
      source: custom.io/prod  # will be ignored as ecr_prepare_images is off!

    bad.example:
      # 'registry' will be ignored when preparing images,
      # but helm will take both rewritten registry and uri paths,
      # which might result in a misconfigured chart (repo info looks redundant here)
      name:
        uri: custom.io/quux:v123  # helm takes <ECR>/quux:v123
      registry:
        repo: custom.io/prod      # helm takes <ECR>/prod?..
      source: custom.io

    # Other than Helm managers examples

    # Key name format: <extra_values_keyname>.<template_var>
    # Requires data: foo-addon-charts.extra_values.extraArgs
    extraArgs.acme-http01-solver-image:
      # rewrites ${acme-http01-solver-image-repo} and/or ${acme-http01-solver-image-tag}
      # templates (need to be escaped \$${...} in extra_values),
      # in foo-addon-charts.extra_values.extraArgs, with the prepared ECR image URI
      chart: bar-addon-charts # updater script will pick appVersion from another addon defined next to this one (not shown here)
      manager: extra
      name: {repository: ..., ...}

    # Key name format: <target_from_foo-addon-charts.kustomizations_images_map>.<target_container_name(s)_template>
    # Requires data: foo-addon-charts.kustomizations_images_map, foo-addon-charts.kustomizations
    controller-manager.kube-rbac-proxy:
      # rewrites kube-rbac-proxy container image URIs in foo-addon-charts.kustomizations with ECR path,
      # before applying it with kubectl.
      manager: kustomize
      name:
        # upstream image URI src to prepare its copy in ECR,
        # it may match, or differ to <original_image_uri> in the kustomization data source
        repository: <image_uri>
```

Required for Helm charts containers images sources and versions info is provided in ``helm-dependencies.yaml`` based on the following list of the source repositories (followed by the Helm chart name):
```
  # https://github.dev/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml
  - name: aws-ebs-csi-driver
--
  # https://github.dev/kubernetes-sigs/aws-efs-csi-driver/blob/master/charts/aws-efs-csi-driver/values.yaml
  - name: aws-efs-csi-driver
--
  # https://github.dev/kubernetes-sigs/aws-load-balancer-controller/blob/main/helm/aws-load-balancer-controller/values.yaml
  - name: aws-load-balancer-controller
--
  # https://github.dev/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml
  - name: cert-manager
--
  # https://github.dev/kubernetes/autoscaler/blob/master/charts/cluster-autoscaler/values.yaml
  - name: cluster-autoscaler
--
  # https://github.dev/kubernetes-sigs/external-dns/blob/master/charts/external-dns/values.yaml
  - name: external-dns
--
  # https://github.dev/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml
  - name: ingress-nginx
--
  # https://github.dev/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml
  - name: kube-prometheus-stack
--
      # https://github.dev/grafana/helm-charts/blob/main/charts/grafana/values.yaml
      grafana.image:
--
  # https://github.dev/kubernetes-sigs/metrics-server/blob/master/charts/metrics-server/values.yaml
  - name: metrics-server
--
  # https://github.dev/deliveryhero/helm-charts/blob/master/stable/node-problem-detector/values.yaml
  - name: node-problem-detector
--
  # https://github.dev/projectcalico/calico/blob/master/charts/tigera-operator/values.yaml
  - name: tigera-operator
--
  # https://github.dev/sagikazarmark/helm-charts/blob/master/charts/dex-k8s-authenticator/values.yaml
  # TODO: maybe switch to https://github.com/mintel/dex-k8s-authenticator/blob/master/charts/dex-k8s-authenticator/values.yaml
  # https://github.dev/dexidp/helm-charts/blob/master/charts/dex/values.yaml
  - name: dex
--
  # https://github.dev/FairwindsOps/charts/blob/master/stable/rbac-manager/values.yaml
  - name: rbac-manager
--
  # https://github.dev/helm/charts/blob/master/stable/kubernetes-dashboard/values.yaml
  # TODO: maybe switch to https://github.com/kubernetes/dashboard/blob/master/charts/helm-chart/kubernetes-dashboard
  - name: kubernetes-dashboard
--
  # https://github.dev/grafana/loki/blob/main/production/helm/loki/values.yaml
  - name: loki-stack
--
  # https://github.dev/grafana/helm-charts/blob/main/charts/promtail/values.yaml
  - name: promtail
--
  # https://github.dev/FairwindsOps/charts/blob/master/stable/vpa/values.yaml
  - name: vpa

  # https://github.dev/FairwindsOps/charts/blob/master/stable/goldilocks/values.yaml
  - name: goldilocks

  # https://github.com/stakater/Reloader/blob/master/deployments/kubernetes/chart/reloader/values.yaml
  - name: reloader
```

### Containers images data lifecycle

Rennovate proposes updates for the Helm release ``version`` values in ``helm-dependencies.yaml``.

There is a [helper script](../../update_containers_tags.sh) for updating containers images tags
in that file to follow the Helm charts version updates (by default), or just picking most recent tags instead.

Addons controlled with Helm manager should specify ``chart: <addon name>`` to discover `AppVersion` for conainer(s),
marked with that attribute. `AppVersion` is searched by the updater script, for a given Helm release ``version``
value of an addon, after adding helm repo by its repository URL. Required Helm repos will be installed
by the updater script, by calling it by each addon name and helm repository URL:

```bash
$ helm repo add cert-manager https://charts.jetstack.io
$ helm repo add cert-manager-csi-driver https://charts.jetstack.io
$ helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
$ helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver
```

`AppVersion` often holds the recommended container image tag for the main application, or sidecars.
The updater script discovers that information, or picks the most recent tags in the source
images repositories.

Only containers marked with the ``chart`` value will get the `AppVersion` tag recommendations instead
of fetching the most recent tag.
