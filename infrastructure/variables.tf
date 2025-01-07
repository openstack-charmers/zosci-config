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
