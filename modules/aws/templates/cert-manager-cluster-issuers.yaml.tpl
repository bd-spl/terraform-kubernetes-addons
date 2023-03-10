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
    - http01:
        ingress:
          class: '${acme_http01_ingress_class}'
          %{ if whitelist_source_range != "" }
          ingressTemplate:
            metadata:
              annotations:
                nginx.ingress.kubernetes.io/whitelist-source-range: '${whitelist_source_range}'
          %{ endif }
          %{ if acme_use_egress_proxy }
          podTemplate:
            spec:
              env:
                - name: http_proxy
                  valuefrom:
                    secretkeyref:
                      name: '${acme_egress_proxy_secret}'
                      key: http_proxy
                - name: https_proxy
                  valuefrom:
                    secretkeyref:
                      name: '${acme_egress_proxy_secret}'
                      key: https_proxy
                - name: no_proxy
                  valuefrom:
                    secretkeyref:
                      name: '${acme_egress_proxy_secret}'
                      key: no_proxy
          %{ endif }
      %{ if acme_dns01_enabled }
      selector:
        matchLabels:
          "use-http01-solver": "true"
      %{ endif }
    %{ endif }
