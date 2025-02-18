terraform {
    required_providers {
      helm = {
        source = "hashicorp/helm"
      }
      kubernetes = {
        source  = "hashicorp/kubernetes"
        version = ">= 2.0.0"
      }
      kubectl = {
        source  = "gavinbunney/kubectl"
        version = ">= 1.7.0"
      }
    }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}
provider "kubectl" {
    config_path = var.kubeconfig
}

provider "kubernetes" {
    config_path = var.kubeconfig
}

resource "kubernetes_namespace" "zuul" {
    metadata {
        name = "zuul"
    }
}

module "openstack_bootstrap" {
  source               = "./modules/zosci-openstack"
  keypair_name         = "nodepool"
  keypair_public_key   = file("${var.nodepool_ssh_key_path}")
  k8s_cluster_secgroup = var.k8s_cluster_secgroup
}

data "template_file" "docker_config_script" {
  template = "${file("${path.module}/dockerconfig.json")}"
  vars = {
    docker-username           = "${var.docker-username}"
    docker-password           = "${var.docker-password}"
    docker-server             = "${var.docker-server}"
    docker-email              = "${var.docker-email}"
    auth                      = base64encode("${var.docker-username}:${var.docker-password}")
  }
}

module "cert_manager" {
  source = "github.com/sculley/terraform-kubernetes-cert-manager"
  namespace = "cert-manager"
}

# Secrets
resource "kubernetes_secret" "docker_registry" {
  metadata {
    name = "dockerhub-image-pull-secret"
    namespace = kubernetes_namespace.zuul.metadata[0].name
  }

  data = {
    ".dockerconfigjson" = "${data.template_file.docker_config_script.rendered}"
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_secret" "nodepool_config" {
  metadata {
    name = "nodepool-config"
    namespace = kubernetes_namespace.zuul.metadata[0].name
  }

  data = {
    "nodepool.yaml" = "${file("${path.module}/nodepool.yaml")}"
  }
}

resource "kubernetes_secret" "clouds_config" {
  metadata {
    name = "clouds-config"
    namespace = kubernetes_namespace.zuul.metadata[0].name
  }

  data = {
    "clouds.yaml" = "${file("${var.clouds_yaml}")}"
  }
}

resource "kubernetes_secret" "tenant_config" {
    metadata {
        name = "zuul-tenant-config"
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    data = {
        "main.yaml" = "${file("${path.module}/../main.yaml")}"
    }
}

resource "kubernetes_secret" "uosci_id_rsa" {
    metadata {
        name = "uosci-id-rsa"
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    data = {
        "id_rsa" = "${file("${path.module}/secrets/uosci_id_rsa.priv")}"
    }
}

resource "kubernetes_service" "mysql" {
    metadata {
        name = "mysql"
        labels = {
            k8s-app = "mysql"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        selector = {
            k8s-app = "mysql"
        }
        port {
            port = 3306
            name = "client"
        }
    }
}

resource "kubernetes_stateful_set" "mysql" {
    metadata {
        labels = {
            k8s-app                           = "mysql"
            "kubernetes.io/cluster-service"   = "true"
            "addonmanager.kubernetes.io/mode" = "Reconcile"
            version                           = "8"
        }
        name = "mysql"
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }

    spec {
        pod_management_policy   = "Parallel"
        replicas                = 1
        revision_history_limit  = 5

        selector {
          match_labels = {
            k8s-app = "mysql"
          }
        }

        service_name = "mysql"

        template {
            metadata {
              labels = {
                k8s-app = "mysql"
              }

              annotations = {}
            }

            spec {
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                init_container {
                    name                = "init-chown-data"
                    image               = "busybox:latest"
                    image_pull_policy   = var.image_pull_policy
                    command             = ["chown", "-R", "65534:65534", "/var/lib/mysql"]

                    volume_mount {
                        name = "mysql-data"
                        mount_path = "/var/lib/mysql"
                        sub_path = ""
                    }
                }

                container {
                    name                = "mariadb-server"
                    image               = "mariadb:jammy"
                    image_pull_policy   = var.image_pull_policy
                    env {
                        name    = "MYSQL_ROOT_PASSWORD"
                        value   = "rootpassword"
                    }
                    env {
                        name = "MYSQL_DATABASE"
                        value = "zuul"
                    }
                    env {
                        name = "MYSQL_USER"
                        value = "zuul"
                    }

                    env {
                        name = "MYSQL_PASSWORD"
                        value = "secret"
                    }

                    env {
                        name = "MYSQL_INITDB_SKIP_TZINFO"
                        value = 1
                    }

                    port {
                        container_port = 3306
                    }

                    resources {
                        limits = {
                            cpu = "1000m"
                            memory = "500Mi"
                        }

                        requests = {
                            cpu = "1000m"
                            memory = "500Mi"
                        }
                    }

                    volume_mount {
                        name        = "mysql-data"
                        mount_path  = "/var/lib/mysql"
                        sub_path    = ""
                    }
                }
                termination_grace_period_seconds = 300
            }
        }

        update_strategy {
            type = "RollingUpdate"

            rolling_update {
                partition = 1
            }
        }

        volume_claim_template {
            metadata {
                name = "mysql-data"
            }

            spec {
                access_modes = ["ReadWriteOnce"]
                storage_class_name = var.storage_class_name

                resources {
                    requests = {
                        storage = "10Gi"
                    }
                }
            }
        }
    }
}

######### Zookeeper ########
resource "kubectl_manifest" "selfsigned_issuer" {
  # apply_only    = true
  # ignore_fields = ["data", "annotations"]
  server_side_apply = true
  yaml_body     = <<YAML
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: ${kubernetes_namespace.zuul.metadata[0].name}
spec:
  selfSigned: {}
YAML
}

resource "kubectl_manifest" "ca_cert" {
  # apply_only    = true
  # ignore_fields = ["data", "annotations"]
  yaml_body     = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ca-cert
  namespace: ${kubernetes_namespace.zuul.metadata[0].name}
spec:
  secretName: ca-cert
  duration: 87600h
  renewBefore: 360h
  isCA: true
  privateKey:
    size: 2048
    algorithm: RSA
    encoding: PKCS1
  commonName: cacert
  dnsNames:
  - caroot
  issuerRef:
    name: selfsigned-issuer
YAML
}

resource "kubectl_manifest" "ca_issuer" {
  # apply_only    = true
  #ignore_fields = ["data", "annotations"]
  yaml_body     = <<YAML
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: ${kubernetes_namespace.zuul.metadata[0].name}
spec:
  ca:
    secretName: ca-cert
YAML
}

resource "kubectl_manifest" "zookeeper_server_tls" {
  depends_on = [module.cert_manager]
  # apply_only    = true
  # ignore_fields = ["data", "annotations"]
  yaml_body     = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: zookeeper-server
  namespace: ${kubernetes_namespace.zuul.metadata[0].name}
  labels:
    app.kubernetes.io/name: zookeeper-server-certificate
    app.kubernetes.io/part-of: zuul
    app.kubernetes.io/component: zookeeper-server-certificate
spec:
  privateKey:
    encoding: PKCS8
  secretName: zookeeper-server-tls
  usages:
    - digital signature
    - key encipherment
    - server auth
    - client auth
  dnsNames:
  - zookeeper-0
  - zookeeper-0.zookeeper-headless.${kubernetes_namespace.zuul.metadata[0].name}.svc.cluster.local
  - zookeeper-1
  - zookeeper-1.zookeeper-headless.${kubernetes_namespace.zuul.metadata[0].name}.svc.cluster.local
  - zookeeper-2
  - zookeeper-2.zookeeper-headless.${kubernetes_namespace.zuul.metadata[0].name}.svc.cluster.local
  issuerRef:
    name: ca-issuer
    kind: Issuer
YAML
}
resource "kubectl_manifest" "zookeeper_client_tls" {
  depends_on = [module.cert_manager]
  # apply_only    = true
  # ignore_fields = ["data", "annotations"]
  server_side_apply = true
  yaml_body     = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: zookeeper-client-tls
  namespace: ${kubernetes_namespace.zuul.metadata[0].name}
  labels:
    app.kubernetes.io/name: zookeeper-client-certificate
    app.kubernetes.io/part-of: zuul
    app.kubernetes.io/component: zookeeper-client-certificate
spec:
  privateKey:
    encoding: PKCS8
  secretName: zookeeper-client-tls
  commonName: client
  usages:
    - digital signature
    - key encipherment
    - server auth
    - client auth
  issuerRef:
    name: ca-issuer
    kind: Issuer
YAML
}

resource "kubernetes_deployment" "nodepool_deployment" {
  metadata {
    name = "nodepool-launcher-${var.cloud_name}"
    namespace = kubernetes_namespace.zuul.metadata[0].name
    labels = {
      name = "nodepool"
      instance = "nodepool-${var.cloud_name}"
      part-of = "zuul"
      component = "nodepool-launcher"
      nodepool-provider = "${var.cloud_name}"
    }
  }
  timeouts {
    create = "2m"
    update = "2m"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "nodepool"
        instance = "nodepool-${var.cloud_name}"
        part-of = "zuul"
        component  = "nodepool-launcher"
        nodepool-provider = "${var.cloud_name}"
      }
    }
    template {
      metadata {
        labels = {
          name = "nodepool"
          instance = "nodepool-${var.cloud_name}"
          part-of = "zuul"
          component  = "nodepool-launcher"
          nodepool-provider = "${var.cloud_name}"
        }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_registry.metadata[0].name
        }
        container {
          name = "launcher"
          # image = "quay.io/zuul-ci/nodepool-launcher:9.1"
          image = var.nodepool_image
          image_pull_policy = var.image_pull_policy
          #command = ["/bin/sh", "-c"]
          #args = ["until test -s /etc/openstack/clouds.yaml ;do echo -n '.'; sleep 5;done && cat /etc/openstack/clouds.yaml && ls -l /etc/openstack/clouds.yaml && echo ~nodepool && su - nodepool 'cat /etc/openstack/clouds.yaml' && id && /usr/local/bin/nodepool-launcher -f"]
          command = ["/bin/sh", "-c"]
          args = ["/usr/local/bin/nodepool-launcher -d -f"]
          env {
            name  = "DEBUG"
            value = "1"
          }
          volume_mount {
            name = "nodepool-config"
            mount_path = "/etc/nodepool"
            read_only = true
          }
          volume_mount {
            name = "zookeeper-client-tls"
            mount_path = "/tls/client"
            read_only = true
          }
          volume_mount {
            name = "clouds-config"
            mount_path = "/etc/openstack"
            read_only = true
          }
        }
        volume {
          name = "nodepool-config"
          secret {
            secret_name = "nodepool-config"
          }
        }
        volume {
          name = "zookeeper-client-tls"
          secret {
            secret_name = "zookeeper-client-tls"
          }
        }
        volume {
          name = "clouds-config"
          secret {
            secret_name = "clouds-config"
            default_mode = "0444"
          }
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget" "zookeeper" {
  count = var.enable_zk_disruption_budget ? 1 : 0
  metadata {
    name = "zookeeper"
    namespace = kubernetes_namespace.zuul.metadata[0].name

    labels = {
      app       = "zookeeper"
      component = "server"
      release   = "zookeeper"
    }
  }

  spec {
    selector {
      match_labels = {
        app       = "zookeeper"
        component = "server"
        release   = "zookeeper"
      }
    }

    max_unavailable = "1"
  }
}

resource "kubernetes_config_map" "zookeeper" {
  metadata {
    name = "zookeeper"
    namespace = kubernetes_namespace.zuul.metadata[0].name

    labels = {
      app       = "zookeeper"
      component = "server"
      release   = "zookeeper"
    }
  }

  data = {
    ok    = file("${path.module}/scripts/zookeeper.ok.sh")
    ready = file("${path.module}/scripts/zookeeper.ready.sh")
    run   = file("${path.module}/scripts/zookeeper.run.sh")
  }
}

resource "kubernetes_service" "zookeeper_headless" {
  metadata {
    name = "zookeeper-headless"
    namespace = kubernetes_namespace.zuul.metadata[0].name

    labels = {
      app     = "zookeeper"
      release = "zookeeper"
    }
  }

  spec {
    port {
      name        = "client"
      protocol    = "TCP"
      port        = 2281
      target_port = "client"
    }

    port {
      name        = "election"
      protocol    = "TCP"
      port        = 3888
      target_port = "election"
    }

    port {
      name        = "server"
      protocol    = "TCP"
      port        = 2888
      target_port = "server"
    }

    selector = {
      app     = "zookeeper"
      release = "zookeeper"
    }

    cluster_ip                  = "None"
    publish_not_ready_addresses = true
  }
}

resource "kubernetes_service" "zookeeper" {
  metadata {
    name = "zookeeper"
    namespace = kubernetes_namespace.zuul.metadata[0].name

    labels = {
      app     = "zookeeper"
      release = "zookeeper"
    }
  }

  spec {
    port {
      name        = "client"
      protocol    = "TCP"
      port        = 2281
      target_port = "client"
    }

    selector = {
      app     = "zookeeper"
      release = "zookeeper"
    }

    type = "ClusterIP"
  }
}
resource "kubernetes_stateful_set" "zookeeper" {
  metadata {
    name = "zookeeper"
    namespace = kubernetes_namespace.zuul.metadata[0].name

    labels = {
      app       = "zookeeper"
      component = "server"
      release   = "zookeeper"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app       = "zookeeper"
        component = "server"
        release   = "zookeeper"
      }
    }

    template {
      metadata {
        labels = {
          app       = "zookeeper"
          component = "server"
          release   = "zookeeper"
        }
      }

      spec {
        volume {
          name = "config"

          config_map {
            name         = "zookeeper"
            default_mode = "0555"
          }
        }

        volume {
          name = "zookeeper-server-tls"

          secret {
            secret_name = "zookeeper-server-tls"
          }
        }

        volume {
          name = "zookeeper-client-tls"

          secret {
            secret_name = "zookeeper-server-tls"
          }
        }

        image_pull_secrets {
          name = kubernetes_secret.docker_registry.metadata[0].name
        }
        container {
          name    = "zookeeper"
          image   = "docker.io/library/zookeeper:3.8.4"
          image_pull_policy   = var.image_pull_policy
          command = ["/bin/bash", "-xec", "/config-scripts/run"]

          port {
            name           = "client"
            container_port = 2281
            protocol       = "TCP"
          }

          port {
            name           = "election"
            container_port = 3888
            protocol       = "TCP"
          }

          port {
            name           = "server"
            container_port = 2888
            protocol       = "TCP"
          }

          env {
            name  = "ZK_REPLICAS"
            value = "3"
          }

          env {
            name  = "JMXAUTH"
            value = "false"
          }

          env {
            name  = "JMXDISABLE"
            value = "false"
          }

          env {
            name  = "JMXPORT"
            value = "1099"
          }

          env {
            name  = "JMXSSL"
            value = "false"
          }

          env {
            name  = "ZK_SYNC_LIMIT"
            value = "10"
          }

          env {
            name  = "ZK_TICK_TIME"
            value = "2000"
          }

          env {
            name  = "ZOO_AUTOPURGE_PURGEINTERVAL"
            value = "0"
          }

          env {
            name  = "ZOO_AUTOPURGE_SNAPRETAINCOUNT"
            value = "3"
          }

          env {
            name  = "ZOO_INIT_LIMIT"
            value = "5"
          }

          env {
            name  = "ZOO_MAX_CLIENT_CNXNS"
            value = "60"
          }

          env {
            name  = "ZOO_PORT"
            value = "2181"
          }

          env {
            name  = "ZOO_STANDALONE_ENABLED"
            value = "false"
          }

          env {
            name  = "ZOO_TICK_TIME"
            value = "2000"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "zookeeper-server-tls"
            read_only  = true
            mount_path = "/tls/server"
          }

          volume_mount {
            name       = "zookeeper-client-tls"
            read_only  = true
            mount_path = "/tls/client"
          }

          volume_mount {
            name       = "config"
            mount_path = "/config-scripts"
          }

          liveness_probe {
            exec {
              command = ["sh", "/config-scripts/ok"]
            }

            initial_delay_seconds = 20
            timeout_seconds       = 5
            period_seconds        = 30
            success_threshold     = 1
            failure_threshold     = 2
          }

          readiness_probe {
            exec {
              command = ["sh", "/config-scripts/ready"]
            }

            initial_delay_seconds = 20
            timeout_seconds       = 5
            period_seconds        = 30
            success_threshold     = 1
            failure_threshold     = 2
          }
        }

        termination_grace_period_seconds = 1800

        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = {
            storage = "5Gi"
          }
        }

        storage_class_name = var.storage_class_name
      }
    }
    service_name          = "zookeeper-headless"
    pod_management_policy = "Parallel"

    update_strategy {
      type = "RollingUpdate"
    }
  }
}

############################

resource "kubernetes_service" "zuul_executor" {
    metadata {
        name = "zuul-executor"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-executor"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }

    spec {
        type        = "ClusterIP"
        cluster_ip  = "None"
        port {
            name        = "logs"
            port        = "7900"
            protocol    = "TCP"
            target_port = "logs"
        }
        selector = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-executor"
        }
    }
}

resource "kubernetes_service" "zuul_web" {
    metadata {
        name = "zuul-web"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-web"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        type = "NodePort"
        port {
            name        = "zuul-web"
            port        = "9000"
            protocol    = "TCP"
            target_port = "zuul-web"
        }
        selector = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-web"
        }
    }
}

resource "kubernetes_service" "zuul_fingergw" {
    metadata {
        name = "zuul-fingergw"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-fingergw"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        type = "NodePort"
        port {
            name        = "zuul-fingergw"
            port        = "9079"
            protocol    = "TCP"
            target_port = "zuul-web"
        }
        selector = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-fingergw"
        }
    }
}


resource "kubernetes_config_map" "zuul_config" {
    metadata {
        name = "zuul-config"
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    data = {
        "zuul.conf" = "${file("${path.module}/zuul.conf")}"
    }
}

resource "kubernetes_stateful_set" "zuul_scheduler" {
    metadata {
        name = "zuul-scheduler"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-scheduler"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        replicas = 1
        service_name = "zuul-scheduler"
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-scheduler"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-scheduler"
                }
            }
            spec {
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                container {
                    name = "scheduler"
                    image = var.zuul_scheduler_image
                    image_pull_policy   = var.image_pull_policy
                    args = [
                        "/usr/local/bin/zuul-scheduler",
                        "-f",
                        "-d"
                    ]
                    volume_mount {
                        name = "zuul-config"
                        mount_path = "/etc/zuul"
                        read_only = "true"
                    }
                    volume_mount {
                        name = "zuul-tenant-config"
                        mount_path = "/etc/zuul/tenant"
                        read_only = "true"
                    }
                    volume_mount {
                        name = "zuul-scheduler"
                        mount_path = "/var/lib/zuul"
                    }
                    volume_mount {
                        name = "zookeeper-client-tls"
                        mount_path = "/tls/client"
                        read_only = "true"
                    }
                    volume_mount {
                        name = "uosci-id-rsa"
                        mount_path = "/zuul/.ssh"
                        read_only = "true"
                    }
                    env {
                        name = "ZUUL_MYSQL_PASSWORD"
                        value = "secret"
                    }
                    env {
                        name = "ZUUL_MYSQL_USER"
                        value = "zuul"
                    }
                }
                volume {
                    name = "zuul-config"
                    config_map {
                        name = kubernetes_config_map.zuul_config.metadata[0].name
                        items {
                            key = "zuul.conf"
                            path = "zuul.conf"
                        }
                    }
                }
                volume {
                    name = "zuul-tenant-config"
                    secret {
                        secret_name = "zuul-tenant-config"
                    }
                }
                volume {
                    name = "zookeeper-client-tls"
                    secret {
                        secret_name = "zookeeper-client-tls"
                    }
                }
                volume {
                    name = "uosci-id-rsa"
                    secret {
                      secret_name = "uosci-id-rsa"
                      default_mode = "0600"
                    }
                }
            }
        }
        volume_claim_template {
            metadata {
                name = "zuul-scheduler"
            }

            spec {
                access_modes = [ "ReadWriteOnce" ]
                storage_class_name = var.storage_class_name
                resources {
                    requests = {
                        storage = "10Gi"
                    }
                }
            }
        }
    }
}

resource "kubernetes_deployment" "zuul_web" {
    metadata {
        name = "zuul-web"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-web"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        replicas = "1"
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-web"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-web"
                }
            }
            spec {
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                container {
                    name = "web"
                    image = var.zuul_web_image
                    image_pull_policy   = var.image_pull_policy
                    port {
                        name = "zuul-web"
                        container_port = "9000"
                    }
                    volume_mount {
                        name = "zuul-config"
                        mount_path = "/etc/zuul"
                    }
                    volume_mount {
                        name = "zookeeper-client-tls"
                        mount_path = "/tls/client"
                        read_only = "true"
                    }
                }
                volume {
                    name = "zuul-config"
                    config_map {
                        name = kubernetes_config_map.zuul_config.metadata[0].name
                        items {
                            key = "zuul.conf"
                            path = "zuul.conf"
                        }
                    }
                }
                volume {
                    name = "zookeeper-client-tls"
                    secret {
                        secret_name = "zookeeper-client-tls"
                    }
                }
            }
        }
    }
}

resource "kubernetes_deployment" "zuul_fingergw" {
    metadata {
        name = "zuul-fingergw"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-fingergw"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        replicas = "1"
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-fingergw"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-fingergw"
                }
            }
            spec {
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                container {
                    name = "fingergw"
                    image = var.zuul_fingergw_image
                    image_pull_policy   = var.image_pull_policy
                    port {
                        name = "zuul-fingergw"
                        container_port = "9079"
                    }
                    volume_mount {
                        name = "zuul-config"
                        mount_path = "/etc/zuul"
                    }
                    volume_mount {
                        name = "zookeeper-client-tls"
                        mount_path = "/tls/client"
                        read_only = "true"
                    }
                }
                volume {
                    name = "zuul-config"
                    config_map {
                        name = kubernetes_config_map.zuul_config.metadata[0].name
                        items {
                            key = "zuul.conf"
                            path = "zuul.conf"
                        }
                    }
                }
                volume {
                    name = "zookeeper-client-tls"
                    secret {
                        secret_name = "zookeeper-client-tls"
                    }
                }
            }
        }
    }
}

resource "kubernetes_stateful_set" "zuul_executor" {
    metadata {
        name = "zuul-executor"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-executor"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        service_name = "zuul-executor"
        replicas = "1"
        pod_management_policy = "Parallel"
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-executor"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-executor"
                }
            }
            spec {
                security_context {
                  run_as_user  = "10001"
                  run_as_group = "10001"
                  fs_group     = "10001"
                }
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                init_container {
                  name                = "init-chown-data"
                  image               = "busybox:latest"
                  image_pull_policy   = var.image_pull_policy
                  command             = ["/bin/sh", "-c"]
                  args = ["mkdir /var/lib/zuul/.ssh && chmod 700 /var/lib/zuul/.ssh && cp /zuul/.ssh/id_rsa /var/lib/zuul/.ssh/ && chmod 600 /var/lib/zuul/.ssh/id_rsa"]

                  volume_mount {
                    name = "uosci-id-rsa"
                    mount_path = "/zuul/.ssh"
                    read_only = "true"
                  }
                  volume_mount {
                    name = "zuul-var"
                    mount_path = "/var/lib/zuul"
                  }
                }
                container {
                    name = "executor"
                    image = var.zuul_executor_image
                    image_pull_policy   = var.image_pull_policy
                  # command = ["/bin/sh", "-c"]
                  # args = ["while true; do echo 'yo' && sleep 5; done;"]
                    args = [
                        "/usr/local/bin/zuul-executor",
                        "-f",
                        "-d"
                    ]
                    port {
                        name = "logs"
                        container_port = "7900"
                    }
                    env {
                        name = "ZUUL_EXECUTOR_SIGTERM_GRACEFUL"
                        value = "1"
                    }
                    volume_mount {
                        name = "zuul-config"
                        mount_path = "/etc/zuul"
                    }
                    volume_mount {
                        name = "zuul-var"
                        mount_path = "/var/lib/zuul"
                    }
                    volume_mount {
                        name = "zookeeper-client-tls"
                        mount_path = "/tls/client"
                        read_only = "true"
                    }
                    volume_mount {
                        name = "uosci-id-rsa"
                        mount_path = "/zuul/.ssh"
                        read_only = "true"
                    }
                    security_context {
                        privileged = "true"
                    }
                }
                termination_grace_period_seconds = 300
                volume {
                    name = "uosci-id-rsa"
                    secret {
                      secret_name = "uosci-id-rsa"
                      default_mode = "0600"
                    }
                }
                volume {
                    name = "zuul-var"
                    empty_dir {}
                }
                volume {
                    name = "zuul-config"
                    config_map {
                        name = kubernetes_config_map.zuul_config.metadata[0].name
                        items {
                            key = "zuul.conf"
                            path = "zuul.conf"
                        }
                    }
                }
                volume {
                    name = "zookeeper-client-tls"
                    secret {
                        secret_name = "zookeeper-client-tls"
                    }
                }
            }
        }
    }
}

resource "kubernetes_stateful_set" "zuul_merger" {
    metadata {
        name = "zuul-merger"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-merger"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        service_name = "zuul-merger"
        replicas = 1
        pod_management_policy = "Parallel"
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-merger"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-merger"
                }
            }
            spec {
                security_context {
                  run_as_user     = "10001"
                  run_as_group    = "10001"
                  fs_group        = "10001"
                }
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                container {
                    name = "merger"
                    image = var.zuul_merger_image
                    image_pull_policy   = var.image_pull_policy
                    args = [
                        "/usr/local/bin/zuul-merger",
                        "-f",
                        "-d"
                    ]
                    volume_mount {
                        name = "uosci-id-rsa"
                        mount_path = "/zuul/.ssh"
                        read_only = "true"
                    }
                    volume_mount {
                        name = "zuul-config"
                        mount_path = "/etc/zuul"
                    }
                    volume_mount {
                        name = "zuul-var"
                        mount_path = "/var/lib/zuul"
                    }
                    volume_mount {
                        name = "zookeeper-client-tls"
                        mount_path = "/tls/client"
                        read_only = "true"
                    }
                }
                termination_grace_period_seconds = 3600
                volume {
                    name = "uosci-id-rsa"
                    secret {
                      secret_name = "uosci-id-rsa"
                      default_mode = "0600"
                    }
                }
                volume {
                    name = "zuul-var"
                    empty_dir {}
                }
                volume {
                    name = "zuul-config"
                    config_map {
                        name = kubernetes_config_map.zuul_config.metadata[0].name
                        items {
                            key = "zuul.conf"
                            path = "zuul.conf"
                        }
                    }
                }
                volume {
                    name = "zookeeper-client-tls"
                    secret {
                        secret_name = "zookeeper-client-tls"
                    }
                }
            }
            
        }
    }
}

resource "kubernetes_service" "zuul_preview" {
    metadata {
        name = "zuul-preview"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-preview"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        type = "NodePort"
        port {
            name = "zuul-preview"
            port = "80"
            protocol = "TCP"
            target_port = "zuul-preview"
        }
        selector = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-preview"
        }
    }
}

resource "kubernetes_deployment" "zuul_preview" {
    metadata {
        name = "zuul-preview"
        labels = {
            k8s-app                         = "zuul"
            "app.kubernetes.io/part-of"     = "zuul"
            "app.kubernetes.io/component"   = "zuul-preview"
        }
        namespace = kubernetes_namespace.zuul.metadata[0].name
    }
    spec {
        replicas = 1
        selector {
            match_labels = {
                k8s-app                         = "zuul"
                "app.kubernetes.io/part-of"     = "zuul"
                "app.kubernetes.io/component"   = "zuul-preview"
            }
        }
        template {
            metadata {
                labels = {
                    k8s-app                         = "zuul"
                    "app.kubernetes.io/part-of"     = "zuul"
                    "app.kubernetes.io/component"   = "zuul-preview"
                }
            }
            spec {
              image_pull_secrets {
                name = kubernetes_secret.docker_registry.metadata[0].name
              }
                container {
                    name = "preview"
                    image = var.zuul_preview_image
                    image_pull_policy   = var.image_pull_policy
                    port {
                        name = "zuul-preview"
                        container_port = "80"
                    }
                    env {
                        name = "ZUUL_API_URL"
                        value = "http://zuul-web/"
                    }
                }
            }
        }
    }
}

resource "kubernetes_service_v1" "zuul_web_service" {
  metadata {
    name = "zuul-web-service"
    namespace = kubernetes_namespace.zuul.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/openstack-internal-load-balancer": "true"
    }
    labels = {
      k8s-app                         = "zuul"
      "app.kubernetes.io/part-of"     = "zuul"
      "app.kubernetes.io/component"   = "zuul-web"
    }
  }

  spec {
    selector = {
      k8s-app                         = "zuul"
      "app.kubernetes.io/part-of"     = "zuul"
      "app.kubernetes.io/component"   = "zuul-web"
    }
    session_affinity = "ClientIP"
    type = "LoadBalancer"
    port {
      port        = "80"
      target_port = "9000"
    }
  }
}
