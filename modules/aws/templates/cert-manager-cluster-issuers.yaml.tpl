---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: '${acme_provider}'
spec:
  acme:
    server: '${acme_server}'
    email: '${acme_email}'
    privateKeySecretRef:
      name: '${acme_provider}'
    skipTLSVerify: ${acme_skip_tls_verify}
    solvers:
    %{ if acme_dns01_enabled }
    - dns01:
        route53:
          region: '${aws_region}'
    %{ endif }
    %{ if acme_http01_enabled }
      %{ for solver in jsondecode(acme_http01_solvers)}
      - http01:
          ingress:
            %{ if lookup(solver, "acme_http01_ingress_class", "") != "" }
            ingressClassName: '${solver.acme_http01_ingress_class}'
            %{ else }
            class: '${acme_http01_ingress_class}'
            %{ endif }
            ingressTemplate:
              metadata:
                annotations:
                  %{ if lookup(solver, "whitelist_source_range", "") != "" }
                  nginx.ingress.kubernetes.io/whitelist-source-range: '${solver.whitelist_source_range}'
                  %{ endif }
                  acme.cert-manager.io/http01-ingress-class: '${solver.acme_http01_ingress_class}'
            %{ if lookup(solver, "acme_use_egress_proxy", false) || acme_use_egress_proxy }
            podTemplate:
              spec:
                env:
                  - name: http_proxy
                    valuefrom:
                      secretkeyref:
                        %{ if lookup(solver, "acme_egress_proxy_secret", "") != "" }
                        name: '${solver.acme_egress_proxy_secret}'
                        %{ else }
                        name: '${acme_egress_proxy_secret}'
                        %{ endif }
                        key: http_proxy
                  - name: https_proxy
                    valuefrom:
                      secretkeyref:
                        %{ if lookup(solver, "acme_egress_proxy_secret", "") != "" }
                        name: '${solver.acme_egress_proxy_secret}'
                        %{ else }
                        name: '${acme_egress_proxy_secret}'
                        %{ endif }
                        key: https_proxy
                  - name: no_proxy
                    valuefrom:
                      secretkeyref:
                        %{ if lookup(solver, "acme_egress_proxy_secret", "") != "" }
                        name: '${solver.acme_egress_proxy_secret}'
                        %{ else }
                        name: '${acme_egress_proxy_secret}'
                        %{ endif }
                        key: no_proxy
            %{ endif }
        %{ if lookup(solver, "acme_dns_zones", []) != [] || lookup(solver, "acme_dns_names", []) != [] || acme_dns01_enabled }
        selector:
          %{ if lookup(solver, "acme_dns_zones", []) != [] }
          dnsZones: ${jsonencode(solver.acme_dns_zones)}
          %{ endif }
          %{ if lookup(solver, "acme_dns_names", []) != [] }
          dnsNames: ${jsonencode(solver.acme_dns_names)}
          %{ endif }
          %{ if acme_dns01_enabled }
          matchLabels:
            "use-http01-solver": "true"
          %{ endif }
        %{ endif }
      %{ endfor }
    %{ endif }
