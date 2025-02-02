locals {
  dex = merge(
    local.helm_defaults,
    {
      name_idp                  = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex")].name
      chart_idp                 = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex")].name
      repository_idp            = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex")].repository
      chart_version_idp         = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex")].version
      name_auth                 = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex-k8s-authenticator")].name
      chart_auth                = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex-k8s-authenticator")].name
      repository_auth           = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex-k8s-authenticator")].repository
      chart_version_auth        = local.helm_dependencies[index(local.helm_dependencies.*.name, "dex-k8s-authenticator")].version
      namespace                 = try(local.helm_dependencies[index(local.helm_dependencies.*.name, "dex")].namespace, "dex")
      enabled                   = false
      default_network_policy    = true
      skip_crds                 = false
      name_prefix               = "${var.cluster-name}-dex"
      admin_email               = "admin@example.org"
      ingress_class             = "nginx"
      public_ingress_class      = "nginx"
      ingress_annotaions        = {}
      public_ingress_annotaions = {}
      infra_ca_secretname       = "infra-ca-secret" # a prefix for auto-generated secrets
      infra_ca_data             = [{ name = "ipa", pem = "" }]
      idp_fqdn                  = "idp.dex.example.org"
      login_fqdn                = "login.dex.example.org"
      ldap_fqdn                 = "openldap.example.org"
      ldap_groups_search_dn     = "ou=groups,dc=example,dc=org"
      ldap_users_search_dn      = "ou=users,dc=example,dc=org"
      ldap_user_filter          = "(objectClass=posixAccount)" # person?
      ldap_group_filter         = "(objectClass=groupOfNames)" # group?
      ldap_acc_secretname       = "ldap-acc-secret"
      cluster_name              = "EKS"
      cluster_api_endpoint      = ""
      cluster_ca_pem            = ""
      oauth_client_secretname   = "oauth-client-secret"
      oauth_client_id           = "kubernetes"
      create_secrets            = true
      hpa                       = ""
      resources                 = {}

      cluster_identity_providers = {
        ldap = {
          client_id                     = ""
          identity_provider_config_name = "LDAP"
          issuer_url                    = ""
          username_claim                = "email"
          groups_claim                  = "groups"
        }
      }

      extra_values = {
        idp  = ""
        auth = ""
      }
      vpa_enable = false
      images_data = {
        idp  = { containers = {} }
        auth = { containers = {} }
      }
      images_repos = {
        idp  = { repos = {} }
        auth = { repos = {} }
      }
      containers_versions = {}
    },
    var.dex
  )

  create_secrets = tobool(try(var.create_secrets, local.dex["create_secrets"]))

  values_dex_idp = <<VALUES
nameOverride: "${local.dex["name_idp"]}"
resources: ${jsonencode(local.dex["resources"])}
${yamldecode(jsonencode(local.dex["hpa"]))}

serviceMonitor:
  enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
  namespace: ${local.dex["namespace"]}

priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}

https:
  enabled: false # no e2e TLS as we terminate on ingress

ingress:
  enabled: true
  className: ${local.dex["public_ingress_class"]}
  annotations: ${jsonencode(local.dex["public_ingress_annotaions"])}
  hosts:
    - host: ${local.dex["idp_fqdn"]}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: dexidp-tls
      hosts:
        - ${local.dex["idp_fqdn"]}

config:
  issuer: https://${local.dex["idp_fqdn"]}

  storage:
    type: kubernetes
    config:
      inCluster: true

  oauth2:
    responseTypes: ["code", "token", "id_token"]
    skipApprovalScreen: true

  connectors:
    - type: ldap
      id: ldap
      name: LDAP
      config:
        adminEmail: ${local.dex["admin_email"]}
        redirectURI: https://${local.dex["idp_fqdn"]}/callback
        host: ${local.dex["ldap_fqdn"]}
        port: 636
        insecureNoSSL: false
        insecureSkipVerify: false
        startTLS: false # reach out by ldaps:// from the beginning
        rootCAData: "${base64encode(local.trusted_ca_certs_joined["ca"])}"
        bindDN: "$${LDAP_USER_DN}"
        bindPW: "$${LDAP_USER_PASSWORD}"
        userSearch:
          baseDN: ${local.dex["ldap_users_search_dn"]}
          filter: ${local.dex["ldap_user_filter"]}
          username: uid
          idAttr: uid
          emailAttr: mail
          nameAttr: displayName
          preferredUsernameAttr: uid
        groupSearch:
          baseDN: ${local.dex["ldap_groups_search_dn"]}
          filter: ${local.dex["ldap_group_filter"]}
          userMatchers:
            - userAttr: uid
              groupAttr: member
            - userAttr: DN
              groupAttr: member
            - userAttr: uid
              groupAttr: memberUid
          nameAttr: cn

  staticClients:
    - id: "${local.dex["oauth_client_id"]}"
      secretEnv: OAUTH_CLIENT_SECRET
      name: "EKS"
      redirectURIs:
        - https://${local.dex["login_fqdn"]}/callback

envFrom:
  - secretRef:
      name: ${local.dex["ldap_acc_secretname"]}
  - secretRef:
      name: ${local.dex["oauth_client_secretname"]}
VALUES

  trusted_ca_certs_volumes = [
    for cert in local.dex["infra_ca_data"] :
    {
      name = cert.name
      secret = {
        secretName = format("%s-%s", local.dex["infra_ca_secretname"], cert.name)
      }
    }
  ]
  trusted_ca_certs_volume_mounts = [
    for cert in local.dex["infra_ca_data"] :
    {
      name      = cert.name
      mountPath = "/certs/${cert.name}.crt"
      readOnly  = true
    }
  ]
  trusted_ca_certs_joined = {
    "ca" = join("\n", [for cert in local.dex["infra_ca_data"] : cert.pem])
  }

  values_dex_auth = <<VALUES
nameOverride: "${local.dex["name_auth"]}"
resources: ${jsonencode(local.dex["resources"])}
${yamldecode(jsonencode(local.dex["hpa"]))}
config:
  clusters:
    - name: "${local.dex["cluster_name"]}"
      short_description: "EKS cluster SSO"
      description: "EKS cluster SSO authenticator for LDAP Login"
      issuer: https://${local.dex["idp_fqdn"]}
      client_id: "${local.dex["oauth_client_id"]}"
      client_secret: "$${OAUTH_CLIENT_SECRET}"
      redirect_uri: https://${local.dex["login_fqdn"]}/callback
      k8s_master_uri: ${local.dex["cluster_api_endpoint"]}
      k8s_ca_pem: |
        ${indent(8, local.dex["cluster_ca_pem"])}
      idp_ca_pem: |
        ${indent(8, local.trusted_ca_certs_joined["ca"])}
  trusted_root_ca: ${jsonencode([for cert in local.dex["infra_ca_data"] : cert.pem])}

ingress:
  enabled: true
  className: ${local.dex["ingress_class"]}
  annotations: ${jsonencode(local.dex["ingress_annotaions"])}
  hosts:
    - host: ${local.dex["login_fqdn"]}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: dex-k8s-authenticator-tls
      hosts:
        - ${local.dex["login_fqdn"]}

envFrom:
  - secretRef:
      name: ${local.dex["oauth_client_secretname"]}

volumes: ${jsonencode(local.trusted_ca_certs_volumes)}
volumeMounts: ${jsonencode(local.trusted_ca_certs_volume_mounts)}
VALUES
}

resource "kubernetes_namespace" "dex" {
  count = local.dex["enabled"] ? 1 : 0

  metadata {
    labels = merge({
      name = local.dex["namespace"]
      }, local.vpa["vpa_only_recommend"] && local.dex["vpa_enable"] ? {
      "goldilocks.fairwinds.com/enabled" = "true"
    } : {})

    name = local.dex["namespace"]
  }
}

resource "kubernetes_secret" "oauth_client_secret" {
  count = local.dex["enabled"] && local.create_secrets ? 1 : 0
  metadata {
    name      = local.dex["oauth_client_secretname"]
    namespace = local.dex["namespace"]
  }

  type = "generic"

  data = {
    "OAUTH_CLIENT_SECRET" = var.oauth_client_secret
  }

  depends_on = [
    kubernetes_namespace.dex
  ]
}

resource "kubernetes_secret" "ldap_acc_secret" {
  count = local.dex["enabled"] && local.create_secrets ? 1 : 0
  metadata {
    name      = local.dex["ldap_acc_secretname"]
    namespace = local.dex["namespace"]
  }

  type = "generic"

  data = {
    "LDAP_USER_DN"       = var.ldap_user_dn
    "LDAP_USER_PASSWORD" = var.ldap_user_password
  }

  depends_on = [
    kubernetes_namespace.dex
  ]
}

resource "kubernetes_secret" "infra_ca_secret" {
  for_each = local.dex["enabled"] ? merge(
    local.trusted_ca_certs_joined,
    {
      for cert in local.dex["infra_ca_data"] : cert.name => cert.pem
    }
  ) : {}

  metadata {
    name      = "${local.dex["infra_ca_secretname"]}-${lower(each.key)}"
    namespace = local.dex["namespace"]
  }

  type = "generic"

  data = {
    lower(each.key) = base64encode(each.value)
  }

  depends_on = [
    kubernetes_namespace.dex
  ]
}

module "deploy_dex" {
  source                = "./deploy"
  images_data           = local.dex["images_data"]["idp"]
  images_repos          = local.dex["images_repos"]["idp"]
  containers_versions   = local.dex["containers_versions"]
  count                 = local.dex["enabled"] ? 1 : 0
  repository            = local.dex["repository_idp"]
  name                  = local.dex["name_idp"]
  chart                 = local.dex["chart_idp"]
  chart_version         = local.dex["chart_version_idp"]
  timeout               = local.dex["timeout"]
  force_update          = local.dex["force_update"]
  recreate_pods         = local.dex["recreate_pods"]
  wait                  = local.dex["wait"]
  atomic                = local.dex["atomic"]
  cleanup_on_fail       = local.dex["cleanup_on_fail"]
  dependency_update     = local.dex["dependency_update"]
  disable_crd_hooks     = local.dex["disable_crd_hooks"]
  disable_webhooks      = local.dex["disable_webhooks"]
  render_subchart_notes = local.dex["render_subchart_notes"]
  replace               = local.dex["replace"]
  reset_values          = local.dex["reset_values"]
  reuse_values          = local.dex["reuse_values"]
  helm_upgrade          = local.dex["helm_upgrade"]
  skip_crds             = local.dex["skip_crds"]
  verify                = local.dex["verify"]
  values = [
    local.values_dex_idp,
    local.dex["extra_values"]["idp"]
  ]

  namespace = kubernetes_namespace.dex.*.metadata.0.name[count.index]

  depends_on = [
    module.deploy_ingress-nginx
  ]
}

module "deploy_dex-k8s-authenticator" {
  count                 = local.dex["enabled"] ? 1 : 0
  source                = "./deploy"
  images_data           = local.dex["images_data"]["auth"]
  images_repos          = local.dex["images_repos"]["auth"]
  containers_versions   = local.dex["containers_versions"]
  repository            = local.dex["repository_auth"]
  name                  = local.dex["name_auth"]
  chart                 = local.dex["chart_auth"]
  chart_version         = local.dex["chart_version_auth"]
  timeout               = local.dex["timeout"]
  force_update          = local.dex["force_update"]
  recreate_pods         = local.dex["recreate_pods"]
  wait                  = local.dex["wait"]
  atomic                = local.dex["atomic"]
  cleanup_on_fail       = local.dex["cleanup_on_fail"]
  dependency_update     = local.dex["dependency_update"]
  disable_crd_hooks     = local.dex["disable_crd_hooks"]
  disable_webhooks      = local.dex["disable_webhooks"]
  render_subchart_notes = local.dex["render_subchart_notes"]
  replace               = local.dex["replace"]
  reset_values          = local.dex["reset_values"]
  reuse_values          = local.dex["reuse_values"]
  helm_upgrade          = local.dex["helm_upgrade"]
  skip_crds             = local.dex["skip_crds"]
  verify                = local.dex["verify"]
  values = [
    local.values_dex_auth,
    local.dex["extra_values"]["auth"]
  ]

  namespace = kubernetes_namespace.dex.*.metadata.0.name[count.index]

  depends_on = [
    module.deploy_dex
  ]
}

# See https://aws.amazon.com/blogs/containers/using-dex-dex-k8s-authenticator-to-authenticate-to-amazon-eks
resource "aws_eks_identity_provider_config" "dex" {
  for_each = local.dex["enabled"] ? local.dex["cluster_identity_providers"] : {}

  cluster_name = var.cluster-name

  oidc {
    client_id                     = try(each.value.client_id, "") == "" ? local.dex["oauth_client_id"] : each.value.client_id
    groups_claim                  = lookup(each.value, "groups_claim", null)
    groups_prefix                 = lookup(each.value, "groups_prefix", null)
    identity_provider_config_name = try(each.value.identity_provider_config_name, each.key)
    issuer_url                    = try(each.value.issuer_url, "") == "" ? "https://${local.dex["idp_fqdn"]}" : each.value.issuer_url
    required_claims               = lookup(each.value, "required_claims", null)
    username_claim                = lookup(each.value, "username_claim", null)
    username_prefix               = lookup(each.value, "username_prefix", null)
  }

  tags = local.tags
  depends_on = [
    module.deploy_dex-k8s-authenticator,
    kubernetes_network_policy.dex_allow_namespace,
    kubernetes_secret.oauth_client_secret,
    kubernetes_secret.ldap_acc_secret,
  ]
}

resource "kubernetes_network_policy" "dex_default_deny" {
  count = local.dex["enabled"] && local.dex["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dex.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.dex.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "dex_allow_namespace" {
  count = local.dex["enabled"] && local.dex["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dex.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.dex.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.dex.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "dex_allow_monitoring" {
  count = local.dex["enabled"] && local.dex["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.dex.*.metadata.0.name[count.index]}-allow-monitoring"
    namespace = kubernetes_namespace.dex.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      ports {
        port     = "5558"
        protocol = "TCP"
      }
      ports {
        port     = "http"
        protocol = "TCP"
      }

      from {
        namespace_selector {
          match_labels = {
            "${local.labels_prefix}/component" = "monitoring"
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
