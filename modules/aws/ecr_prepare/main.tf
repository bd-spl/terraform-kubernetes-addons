resource "local_file" "ecr_repos_names" {
  count    = length(local.ecr_repos) > 0 ? 1 : 0
  content  = format("%s\n", join("\n", keys(local.ecr_repos)))
  filename = "${path.module}/ecr_repos_names.txt"
}

data "external" "check_ecr_exists" {
  count = length(local.ecr_repos) > 0 ? 1 : 0
  program = [
    "${path.module}/check_ecr_exists.sh",
    data.aws_region.current.name,
    "${path.module}/ecr_repos_names.txt",
    var.shared_ecr_kms_key
  ]

  depends_on = [
    local_file.ecr_repos_names
  ]
}
