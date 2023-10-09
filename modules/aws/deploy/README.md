# terraform-kubernetes-addons:aws:deploy

## About

The module that wraps ``helm_release`` resource to deploy a target addon with Helm manager.
Or to deploy it with the Kustomize and Extra (Helm values) managers, or a combination of it.
In such a case, Kustomize renders and applies manifests resources before Helm manager.
Then the extra manager templates extra values for Helm manager (like rewriting images paths for
the ones prepared as ECR repos). Finally, Helm manager deploys on top of all (if enabled).

There is also ``containers_versions`` variable to override the target addon's images data defaulted ``helm-dependencies.yaml``.
FIXME: Support for newer versions overrides - can only pin it for the known tags already existing in the prepared ECR repos.

Example global ``containers_versions`` definition for all addons:
```
---
containers_versions:
  # helm charts versions overrides for EKS addons from helm-dependencies.yaml
  flux2: v0.27.1

  # containers tags overrides for EKS addons containers data from helm-dependencies.yaml
  # Helm manager overrides:
  ingress-nginx:
    controller.admissionWebhooks.patch.image.tag: v42
  ingress-nginx-internal:
    controller.admissionWebhooks.patch.image.tag: v24
  kube-prometheus-stack:
    grafana.image.tag: 9.4.7
    prometheusOperator.image.tag: v0.63.0
    prometheusOperator.prometheusConfigReloader.image.tag: v0.63.0
  cluster-autoscaler:
    image.tag: v1.24.0

  # Kustomize manager overrides, and mixed cases
  csi-external-snapshotter:
    manifests: v6.0.1
    snapshot-controller: v5.0.1
    csi-provisioner: v3.2.1
    csi-snapshotter: v6.0.1
    hostpath: v1.8.0
  cert-manager:
    gateway-api-webhook: v0.5.1
    gateway-api-crd: v0.5.1
    gateway-api-admission: v1.1.1
    # Used by the 'helm' and 'extra' managers, hence the name format
    acmesolver.image.tag: v1.11.0
```
Then each instance of the module should be given the target addon name and its containers_versions overrides,
if needed.
This module uses all containers images data and ECR data that must be prepared by the dependency `ecr_prepare` and
`ecr_upload` modules in advance.
See also the AWS EKS addons ``*.tf`` files contents to learn how to use this module.

# Terraform docs

[Deploy](./TFDOCS.md)

# Known issue

If kustomize provider fails to apply for cert-manager deployment,
remove the immutable jobs and retry the deploy command:
```
kubectl delete job gateway-api-admission -n gateway-system --ignore-not-found
kubectl delete job gateway-api-admission-patch -n gateway-system --ignore-not-found
```
