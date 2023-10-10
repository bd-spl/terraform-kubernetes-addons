# ecr_upload

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |
| <a name="requirement_skopeo"></a> [skopeo](#requirement\_skopeo) | 0.0.4 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.20.1 |
| <a name="provider_skopeo"></a> [skopeo](#provider\_skopeo) | 0.0.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [skopeo_copy.this](https://registry.terraform.io/providers/abergmeier/skopeo/0.0.4/docs/resources/copy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_check_ecr_exists"></a> [check\_ecr\_exists](#input\_check\_ecr\_exists) | Results of ECR repos existance check from ECR prepare module | `map(any)` | `{}` | no |
| <a name="input_ecr_force_delete"></a> [ecr\_force\_delete](#input\_ecr\_force\_delete) | Force delete ECR repos (this doesn't work, and AWS provider cannot idempotently ensure it neither) | `bool` | `false` | no |
| <a name="input_ecr_repos"></a> [ecr\_repos](#input\_ecr\_repos) | ECR repos data prepared by ECR module | `map(any)` | `{}` | no |
| <a name="input_ecr_tags"></a> [ecr\_tags](#input\_ecr\_tags) | ECR repos tags to apply for newly created repos (cannot change tags for already existing repos) | `map(any)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ecr_data"></a> [ecr\_data](#output\_ecr\_data) | Prepared AWS ECR repos to consume it by deploy modules (JSON serializied per an addon key) |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
