variable "keypair_name" {
  type = string
  description = "Keypair name when uploading the public key to OpenStack"
}

variable "keypair_public_key" {
  type = string
  description = "Public key to be upload to OpenStack"
}

variable "secgroup_name" {
  type        = string
  default     = "zosci-sec-group"  # needs to be in sync with nodepool.yaml
  description = "Security group name associated to nodepool instances by default"
}

variable "k8s_cluster_secgroup" {
  type        = string
  description = "Security group name associated to the juju model where the k8s cluser is deployed"
}

variable "num_vips" {
  type        = number
  default     = 3
  description = "Number of IP addresses to allocate and use as VIPs"
}

variable "vip_network_id" {
  type        = string
  description = "ID of the network that will be used to allocate VIP ports from"
}

variable "vip_subnet_id" {
  type        = string
  description = "ID of the subnet that will be used to allocate VIP ports from"
}
