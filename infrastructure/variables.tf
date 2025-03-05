variable "kubeconfig" {
  type = string
  default = "~/.kube/config"
  description = "Path to kubectl configuration file"
}

variable "storage_class_name" {
  type = string
  default = "csi-cinder-default"
  description = "Storage class name to use when creating volumes"
}

variable "docker-username" {
  type = string
  default = ""
  description = "Dockerhub username"
}

variable "docker-password" {
  type = string
  default = ""
  description = "Dockerhub password"
}

variable "docker-server" {
  type = string
  default = "https://index.docker.io/v1"
  description = "Dockerhub server"
}

variable "docker-email" {
  type = string
  default = ""
  description = "Dockerhub email"
}

variable "clouds_yaml" {
  type        = string
  description = "Path to a clouds.yaml file used to authenticate against the OpenStack cloud."
}

variable "cloud_name" {
  type        = string
  description = "Cloud name to use (e.g. serverstack)"
}

variable "nodepool_ssh_key_path" {
  type        = string
  description = "Path to the public ssh key the nodepool nodes will be created with"
}

variable "enable_zk_disruption_budget" {
  type        = bool
  default     = false
  description = "Enable zookeeper disruption budget declaration for HA scenarios"
}

variable "k8s_cluster_secgroup" {
  type        = string
  description = "Security group name associated to the juju model where the k8s cluser is deployed"
}

variable "nodepool_image" {
  type        = string
  default     = "freyes/nodepool-launcher:custom"
  description = "Nodepool image"
}

variable "zuul_scheduler_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-scheduler:9.1"
  description = "Zuul Scheduler image"
}

variable "zuul_web_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-web:9.1"
  description = "Zuul Web image"
}

variable "zuul_fingergw_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-fingergw:9.1"
  description = "Zuul Finger Gateway image"
}

variable "zuul_executor_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-executor:9.1"
  description = "Zuul Executor image"
}

variable "zuul_merger_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-merger:9.1"
  description = "Zuul Merger image"
}

variable "zuul_preview_image" {
  type        = string
  default     = "quay.io/zuul-ci/zuul-preview:latest"
  description = "Zuul Preview image"
}

variable "image_pull_policy" {
  type        = string
  default     = "IfNotPresent"  # alternatively use "Always"
  description = "Image pull policy"
}

variable "vip_network_id" {
  type        = string
  description = "ID of the network that will be used to allocate VIP ports from"
}

variable "vip_subnet_id" {
  type        = string
  description = "ID of the subnet that will be used to allocate VIP ports from"
}
