# terraform-kubernetes-addons

[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/terraform-kubernetes-addons)
[![terraform-kubernetes-addons](https://github.com/particuleio/terraform-kubernetes-addons/workflows/terraform-kubernetes-addons/badge.svg)](https://github.com/particuleio/terraform-kubernetes-addons/actions?query=workflow%3Aterraform-kubernetes-addons)

## Main components

TODO: update for newly added modules dashboard, rbac-manager, dex, vpa, etc.

| Name                                                                                                                          | Description                                                                                      | Generic             | AWS                 | Scaleway            | GCP                 | Azure               |
|------|-------------|:-------:|:---:|:--------:|:---:|:-----:|
| [admiralty](https://admiralty.io/)                                                                                            | A system of Kubernetes controllers that intelligently schedules workloads across clusters        | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [aws-ebs-csi-driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)                                                   | Enable new feature and the use of `gp3` volumes                                                  | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [aws-efs-csi-driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)                                                   | Enable EFS Support                                                                               | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [aws-for-fluent-bit](https://github.com/aws/aws-for-fluent-bit)                                                               | Cloudwatch logging with fluent bit instead of fluentd                                            | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [aws-load-balancer-controller](https://aws.amazon.com/about-aws/whats-new/2020/10/introducing-aws-load-balancer-controller/)  | Use AWS ALB/NLB for ingress and services                                                         | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [aws-node-termination-handler](https://github.com/aws/aws-node-termination-handler)                                           | Manage spot instance lifecyle                                                                    | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [aws-calico](https://github.com/aws/eks-charts/tree/master/stable/aws-calico)                                                 | Use calico for network policy                                                                    | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [secrets-store-csi-driver-provider-aws](https://github.com/aws/secrets-store-csi-driver-provider-aws) | AWS Secret Store and Parameter store driver for secret store CSI driver | :heavy_check_mark:  | N/A  | N/A  | N/A  | N/A  |
| [cert-manager](https://github.com/jetstack/cert-manager)                                                                      | automatically generate TLS certificates, supports ACME v2                                        | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :x:                 | N/A                 |
| [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)                                 | scale worker nodes based on workload                                                             | N/A                 | :heavy_check_mark:  | Included            | Included            | Included            |
| [cni-metrics-helper](https://docs.aws.amazon.com/eks/latest/userguide/cni-metrics-helper.html)                                | Provides cloudwatch metrics for VPC CNI plugins                                                  | N/A                 | :heavy_check_mark:  | N/A                 | N/A                 | N/A                 |
| [external-dns](https://github.com/kubernetes-incubator/external-dns)                                                          | sync ingress and service records in route53                                                      | :x:                 | :heavy_check_mark:  | :heavy_check_mark:  | :x:                 | :x:                 |
| [flux2](https://github.com/fluxcd/flux2)                                                                                      | Open and extensible continuous delivery solution for Kubernetes. Powered by GitOps Toolkit       | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [ingress-nginx](https://github.com/kubernetes/ingress-nginx)                                                                  | processes `Ingress` object and acts as a HTTP/HTTPS proxy (compatible with cert-manager)         | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :x:                 | :x:                 |
| [istio-operator](https://istio.io)                                                                                            | Service mesh for Kubernetes                                                                      | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [k8gb](https://www.k8gb.io/)                                                                                                  | A cloud native Kubernetes Global Balancer                                                        | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [karma](https://github.com/prymitive/karma)                                                                                   | An alertmanager dashboard                                                                        | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [keda](https://github.com/kedacore/keda)                                                                                      | Kubernetes Event-driven Autoscaling                                                              | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [keycloak](https://www.keycloak.org/)                                                                                         | Identity and access management                                                                   | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [kong](https://konghq.com/kong)                                                                                               | API Gateway ingress controller                                                                   | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :x:                 | :x:                 |
| [kube-prometheus-stack](https://github.com/prometheus-operator/kube-prometheus)                                               | Monitoring / Alerting / Dashboards                                                               | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :x:                 | :x:                 |
| [kyverno](https://github.com/kyverno/kyverno)                                                                                 | Kubernetes Native Policy Management                                                              | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [loki-stack](https://grafana.com/oss/loki/)                                                                                   | Grafana Loki logging stack                                                                       | :heavy_check_mark:  | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [promtail](https://grafana.com/docs/loki/latest/clients/promtail/)                                                            | Ship log to loki from other cluster (eg. mTLS)                                                   | :construction:      | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [prometheus-adapter](https://github.com/kubernetes-sigs/prometheus-adapter)                                                   | Prometheus metrics for use with the autoscaling/v2 Horizontal Pod Autoscaler in Kubernetes 1.6+  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [prometheus-cloudwatch-exporter](https://github.com/prometheus/cloudwatch_exporter)                                           | An exporter for Amazon CloudWatch, for Prometheus.                                               | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [prometheus-blackbox-exporter](https://github.com/prometheus/blackbox_exporter)                                               | The blackbox exporter allows blackbox probing of endpoints over HTTP, HTTPS, DNS, TCP and ICMP.  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [rabbitmq-cluster-operator](https://github.com/rabbitmq/cluster-operator)                                                     | The RabbitMQ Cluster Operator automates provisioning, management of RabbitMQ clusters.           | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [metrics-server](https://github.com/kubernetes-incubator/metrics-server)                                                      | enable metrics API and horizontal pod scaling (HPA)                                              | :heavy_check_mark:  | :heavy_check_mark:  | Included            | Included            | Included            |
| [node-problem-detector](https://github.com/kubernetes/node-problem-detector)                                                  | Forwards node problems to Kubernetes events                                                      | :heavy_check_mark:  | :heavy_check_mark:  | Included            | Included            | Included            |
| [secrets-store-csi-driver](https://github.com/kubernetes-sigs/secrets-store-csi-driver) | Secrets Store CSI driver for Kubernetes secrets - Integrates secrets stores with Kubernetes via a CSI volume. | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [sealed-secrets](https://github.com/bitnami-labs/sealed-secrets)                                                              | Technology agnostic, store secrets on git                                                        | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [strimzi-kafka-operator](https://github.com/strimzi/strimzi-kafka-operator)                                                   | Apache Kafka running on Kubernetes                                                               | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |
| [thanos](https://thanos.io/)                                                                                                  | Open source, highly available Prometheus setup with long term storage capabilities               | :x:                 | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [thanos-memcached](https://thanos.io/tip/components/query-frontend.md/#memcached)                                             | Open source, highly available Prometheus setup with long term storage capabilities               | :x:                 | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [thanos-storegateway](https://thanos.io/)                                                                                     | Additional storegateway to query multiple object stores                                          | :x:                 | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [thanos-tls-querier](https://thanos.io/tip/operating/cross-cluster-tls-communication.md/)                                     | Thanos TLS querier for cross cluster collection                                                  | :x:                 | :heavy_check_mark:  | :construction:      | :x:                 | :x:                 |
| [vault](https://www.vaultproject.io/)                                                                                         | A tool for secrets management, encryption as a service, and privileged access management         | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  | :heavy_check_mark:  |

## Submodules

Submodules are used for specific cloud provider configuration such as IAM role, or preparing containers images for
AWS ECR. For a Kubernetes vanilla cluster, generic addons should be used.

Any contribution supporting a new cloud provider is welcomed.

* [AWS](./modules/aws)
  * [deploy](./modules/aws/deploy)
  * [ecr_prepare](./modules/aws/ecr_prepare)
  * [ecr_upload](./modules/aws/ecr_upload)
* [Scaleway](./modules/scaleway)
* [GCP](./modules/gcp)
* [Azure](./modules/azure)

## Doc generation

Code formatting and documentation for variables and outputs is generated using
[pre-commit-terraform
hooks](https://github.com/antonbabenko/pre-commit-terraform) which uses
[terraform-docs](https://github.com/segmentio/terraform-docs).

Follow [these
instructions](https://github.com/antonbabenko/pre-commit-terraform#how-to-install)
to install pre-commit locally.

And install `terraform-docs` with `go get github.com/segmentio/terraform-docs`
or `brew install terraform-docs`.

## Contributing

Report issues/questions/feature requests on in the
[issues](https://github.com/spearlineltd/terraform-kubernetes-addons/issues/new)
section.

Full contributing [guidelines are covered
here](https://github.com/spearlineltd/terraform-kubernetes-addons/blob/master/.github/CONTRIBUTING.md).

Keep the pre-commit hook up to date:
```
pre-commit autoupdate
pre-commit uninstall
pre-commit install
```

Triggering a full-repo pre-commit run:
```
pre-commit run --show-diff-on-failure --color=always --show-diff-on-failure --all-files
```

To make the pre-commit hook that validates terraform passing, init terraform for the required submodules modules:
```
terraform init
cd modules/aws
terraform init
cd deploy
terraform init
cd ../ecr_prepare
terraform init
cd ../ecr_upload
terraform init
```

## Terraform documentation for this repo and modules

* [Main](./TFDOCS.md)
* [AWS](./modules/aws/TFDOCS.md)
  * [ECR prepare](./modules/aws/ecr_prepare/TFDOCS.md)
  * [ECR upload](./modules/aws/ecr_upload/TFDOCS.md)
  * [Deploy](./modules/aws/deploy/TFDOCS.md)
* [Azure](./modules/azure/TFDOCS.md)
* [Scaleway](./modules/scaleway/TFDOCS.md)

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
TFDOCS.md updated successfully
modules/aws/TFDOCS.md updated successfully
modules/azure/TFDOCS.md updated successfully
modules/scaleway/TFDOCS.md updated successfully
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
