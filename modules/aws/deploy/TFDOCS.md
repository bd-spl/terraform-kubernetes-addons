# deploy

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.12.1 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.2 |
| <a name="provider_template"></a> [template](#provider\_template) | 2.2.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.this](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [local_file.kustomization](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.kustomize](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [template_file.extra_values_patched](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_atomic"></a> [atomic](#input\_atomic) | n/a | `bool` | `null` | no |
| <a name="input_chart"></a> [chart](#input\_chart) | n/a | `string` | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | n/a | `string` | `null` | no |
| <a name="input_cleanup_on_fail"></a> [cleanup\_on\_fail](#input\_cleanup\_on\_fail) | n/a | `bool` | `null` | no |
| <a name="input_containers_versions"></a> [containers\_versions](#input\_containers\_versions) | Containers images versions to use with the target addon deployment | `map(any)` | `{}` | no |
| <a name="input_dependency_update"></a> [dependency\_update](#input\_dependency\_update) | n/a | `bool` | `null` | no |
| <a name="input_disable_crd_hooks"></a> [disable\_crd\_hooks](#input\_disable\_crd\_hooks) | n/a | `bool` | `null` | no |
| <a name="input_disable_webhooks"></a> [disable\_webhooks](#input\_disable\_webhooks) | n/a | `bool` | `null` | no |
| <a name="input_extra_tpl"></a> [extra\_tpl](#input\_extra\_tpl) | Extra Helm values templated for the target addon's to override containers images with prepared data | `map(any)` | `{}` | no |
| <a name="input_force_update"></a> [force\_update](#input\_force\_update) | n/a | `bool` | `null` | no |
| <a name="input_helm_deploy"></a> [helm\_deploy](#input\_helm\_deploy) | Whether to deploy with Helm manager | `bool` | `true` | no |
| <a name="input_helm_upgrade"></a> [helm\_upgrade](#input\_helm\_upgrade) | Whether to upgrade (no install) existing helm release (no support in upstream provider yet) | `bool` | `false` | no |
| <a name="input_helm_upgrade_install"></a> [helm\_upgrade\_install](#input\_helm\_upgrade\_install) | Whether to upgrade --install existing helm release (no support in upstream provider yet) | `bool` | `false` | no |
| <a name="input_images_data"></a> [images\_data](#input\_images\_data) | Containers images data from ECR prepare module for the target addon | `map(any)` | <pre>{<br>  "containers": {}<br>}</pre> | no |
| <a name="input_images_repos"></a> [images\_repos](#input\_images\_repos) | Containers repos data from ECR upload module for the target addon | `map(any)` | <pre>{<br>  "repos": {}<br>}</pre> | no |
| <a name="input_kustomizations"></a> [kustomizations](#input\_kustomizations) | kustomizations for the target addon | `map(any)` | `{}` | no |
| <a name="input_kustomizations_images_map"></a> [kustomizations\_images\_map](#input\_kustomizations\_images\_map) | containers images mappings for the target addon to kustomize it after the paths get rewritten for ECR | `map(any)` | `{}` | no |
| <a name="input_kustomize_external"></a> [kustomize\_external](#input\_kustomize\_external) | Apply with Kustomize or kubectl -k | `bool` | `false` | no |
| <a name="input_kustomize_resources"></a> [kustomize\_resources](#input\_kustomize\_resources) | kustomization resources for the target addon | `list(any)` | `[]` | no |
| <a name="input_kustomize_resources_manifests_version"></a> [kustomize\_resources\_manifests\_version](#input\_kustomize\_resources\_manifests\_version) | the target addon's manifests versions to be used as kustomize resources | `string` | `null` | no |
| <a name="input_kustomize_workarounds"></a> [kustomize\_workarounds](#input\_kustomize\_workarounds) | Apply commands before applying kustomizations | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | n/a | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | n/a | `string` | `null` | no |
| <a name="input_recreate_pods"></a> [recreate\_pods](#input\_recreate\_pods) | n/a | `bool` | `null` | no |
| <a name="input_render_subchart_notes"></a> [render\_subchart\_notes](#input\_render\_subchart\_notes) | n/a | `bool` | `null` | no |
| <a name="input_replace"></a> [replace](#input\_replace) | n/a | `bool` | `null` | no |
| <a name="input_repository"></a> [repository](#input\_repository) | Those below are the standard arguments of helm\_release, look for details at the source, and keep them synced here | `string` | `null` | no |
| <a name="input_reset_values"></a> [reset\_values](#input\_reset\_values) | n/a | `bool` | `null` | no |
| <a name="input_reuse_values"></a> [reuse\_values](#input\_reuse\_values) | n/a | `bool` | `null` | no |
| <a name="input_set_sensitive"></a> [set\_sensitive](#input\_set\_sensitive) | n/a | `list(any)` | `[]` | no |
| <a name="input_skip_crds"></a> [skip\_crds](#input\_skip\_crds) | n/a | `bool` | `null` | no |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | n/a | `number` | `null` | no |
| <a name="input_values"></a> [values](#input\_values) | n/a | `list(any)` | `null` | no |
| <a name="input_verify"></a> [verify](#input\_verify) | n/a | `bool` | `null` | no |
| <a name="input_wait"></a> [wait](#input\_wait) | n/a | `bool` | `null` | no |

## Outputs

No outputs.
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
