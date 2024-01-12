# ecr_upload

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.20 |
| <a name="requirement_skopeo"></a> [skopeo](#requirement\_skopeo) | 0.0.4 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.32.0 |
| <a name="provider_external"></a> [external](#provider\_external) | 2.3.2 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.1 |
| <a name="provider_skopeo"></a> [skopeo](#provider\_skopeo) | 0.0.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [local_file.ecr_repos_names](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [skopeo_copy.this](https://registry.terraform.io/providers/abergmeier/skopeo/0.0.4/docs/resources/copy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [external_external.check_ecr_exists](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_check_ecr_exists"></a> [check\_ecr\_exists](#input\_check\_ecr\_exists) | Results of ECR repos existance check from ECR prepare module | `map(any)` | `{}` | no |
| <a name="input_ecr_encryption_type"></a> [ecr\_encryption\_type](#input\_ecr\_encryption\_type) | Encryption type for ECR images. This global flag can be overriden for specific containers | `string` | `"AES256"` | no |
| <a name="input_ecr_force_delete"></a> [ecr\_force\_delete](#input\_ecr\_force\_delete) | Force delete ECR repos (this doesn't work, and AWS provider cannot idempotently ensure it neither) | `bool` | `false` | no |
| <a name="input_ecr_immutable_tag"></a> [ecr\_immutable\_tag](#input\_ecr\_immutable\_tag) | Use immutable tags for ECR images. This global flag can be overriden for specific containers | `bool` | `false` | no |
| <a name="input_ecr_kms_key"></a> [ecr\_kms\_key](#input\_ecr\_kms\_key) | Preconfigured KMS key arn to encrypt ECR images. This global flag can be overriden for specific containers. Shared repos must use the same KMS key ARN | `string` | `null` | no |
| <a name="input_ecr_prepare_images"></a> [ecr\_prepare\_images](#input\_ecr\_prepare\_images) | Prepare containers images for addons and store it in ECR. This global flag can be overriden for specific containers | `bool` | `true` | no |
| <a name="input_ecr_repos"></a> [ecr\_repos](#input\_ecr\_repos) | ECR repos data prepared by ECR module | `map(any)` | `{}` | no |
| <a name="input_ecr_scan_on_push"></a> [ecr\_scan\_on\_push](#input\_ecr\_scan\_on\_push) | Scan prepared ECR images on push. This global flag can be overriden for specific containers | `bool` | `false` | no |
| <a name="input_ecr_tags"></a> [ecr\_tags](#input\_ecr\_tags) | ECR repos tags to apply for newly created repos (cannot change tags for already existing repos) | `map(any)` | `{}` | no |
| <a name="input_shared_ecr_kms_key"></a> [shared\_ecr\_kms\_key](#input\_shared\_ecr\_kms\_key) | A KMS key ARN to identify already existing ECR repos as shared, if those match this key ARN | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ecr_data"></a> [ecr\_data](#output\_ecr\_data) | Prepared AWS ECR repos to consume it by deploy modules (JSON serializied per an addon key) |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
