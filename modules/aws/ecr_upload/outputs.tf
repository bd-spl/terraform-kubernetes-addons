output "ecr_data" {
  description = "Prepared AWS ECR repos to consume it by deploy modules (JSON serializied per an addon key)"
  value = {
    for k, v in {
      for k, v in skopeo_copy.this : split(".", k)[0] => {
        "${k}" = { # tflint-ignore: terraform_deprecated_interpolation
          repository_url = split(":", split("://", v.destination_image)[1])[0]
          name           = k
        }
      }...
    } : k => { repos = merge(v...) }
  }
}
