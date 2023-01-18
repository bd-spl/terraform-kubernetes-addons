%{ if acme_provider == "letsencrypt" }
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: '${acme_staging_server}'
    email: '${acme_email}'
    privateKeySecretRef:
      name: letsencrypt-staging
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
      %{ if acme_dns01_enabled }
      selector:
        matchLabels:
          "use-http01-solver": "true"
      %{ endif }
    %{ endif }
%{ endif }
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
    skipTLSVerify: ${acme_http01_skip_tls_verify}
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
      %{ if acme_dns01_enabled }
      selector:
        matchLabels:
          "use-http01-solver": "true"
      %{ endif }
    %{ endif }
