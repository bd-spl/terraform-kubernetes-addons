# terraform-kubernetes-addons:aws:ecr_upload

## About

The module ensures that the required containers images uploaded into AWS ECR, based
on the containers images data inputs from the ECR prepare module.

Its outputs are used by each of the deploy module instances invoked for EKS
addons deployment.

The `aws_ecr_repository` module cannot idempotently ensure already
existing ECR repos. To workaround that, the ECR prepare and upload modules are split
into different steps. The former identifies already existing repos and marks
them in its outputs as shared, or not. The latter consumes the check results
output as its inputs and creates AWS ECR repos for missing images only.
Then calls `scopeo_copy` module to ensure the actual container images repos contents.

## Terraform docs

[ecr_upload](./TFDOCS.md)
