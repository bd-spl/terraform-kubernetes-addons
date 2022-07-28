locals {

  testrtc-speedtest = merge(
    local.helm_defaults,
    {
      name                   = local.helm_dependencies[index(local.helm_dependencies.*.name, "testrtc-speedtest")].name
      chart                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "testrtc-speedtest")].name
      repository             = local.helm_dependencies[index(local.helm_dependencies.*.name, "testrtc-speedtest")].repository
      chart_version          = local.helm_dependencies[index(local.helm_dependencies.*.name, "testrtc-speedtest")].version
      enabled                = true
      default_network_policy = true
      namespace              = "testrtc-speedtest"
    },
    var.testrtc-speedtest
  )

  values_testrtc-speedtest = <<VALUES
VALUES

}

resource "helm_release" "testrtc-speedtest" {
  count                 = local.testrtc-speedtest["enabled"] ? 1 : 0
  repository            = local.testrtc-speedtest["repository"]
  name                  = local.testrtc-speedtest["name"]
  chart                 = local.testrtc-speedtest["chart"]
  version               = local.testrtc-speedtest["chart_version"]
  timeout               = local.testrtc-speedtest["timeout"]
  force_update          = local.testrtc-speedtest["force_update"]
  recreate_pods         = local.testrtc-speedtest["recreate_pods"]
  wait                  = local.testrtc-speedtest["wait"]
  atomic                = local.testrtc-speedtest["atomic"]
  cleanup_on_fail       = local.testrtc-speedtest["cleanup_on_fail"]
  dependency_update     = local.testrtc-speedtest["dependency_update"]
  disable_crd_hooks     = local.testrtc-speedtest["disable_crd_hooks"]
  disable_webhooks      = local.testrtc-speedtest["disable_webhooks"]
  render_subchart_notes = local.testrtc-speedtest["render_subchart_notes"]
  replace               = local.testrtc-speedtest["replace"]
  reset_values          = local.testrtc-speedtest["reset_values"]
  reuse_values          = local.testrtc-speedtest["reuse_values"]
  skip_crds             = local.testrtc-speedtest["skip_crds"]
  verify                = local.testrtc-speedtest["verify"]
  values = [
    local.values_testrtc-speedtest,
    local.testrtc-speedtest["extra_values"]
  ]
  namespace = local.testrtc-speedtest.namespace

  #depends_on = [
  #  helm_release.kube-prometheus-stack
  #]
}
