# terraform-kubernetes-addons:aws:ecr_prepare

## About

The module prepares AWS ECR images data based on the containers images data
in ``helm-dependencies.yaml``, and checks for existance/shared
state of the addons' ECR repos.

Its outputs are used by the ECR upload module and each of the deploy module
instances invoked for EKS addons deployment.

The `aws_ecr_repository` module cannot idempotently ensure already existing ECR repos.
To workaround that, this module only identifies already existing repos and checks if
those are shared, or not. The actual deployment of the repos and images layers happens
later on.
## Terraform docs

[ecr_prepare](./TFDOCS.md)
