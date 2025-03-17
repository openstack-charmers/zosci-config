terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# Create a SSH key for zosci.
resource "openstack_compute_keypair_v2" "zosci-keypair" {
  name       = "${var.keypair_name}"
  public_key = "${var.keypair_public_key}"
}

# Create a security group for nodepool managed instances
resource "openstack_networking_secgroup_v2" "zosci_secgroup" {
  name = "${var.secgroup_name}"
  description = "Security group for nodepool instances"
}

# Security group associated to the juju model where the k8s cluster is deployed
data "openstack_networking_secgroup_v2" "k8s_cluster_secgroup" {
  name = "${var.k8s_cluster_secgroup}"
}

resource "openstack_networking_secgroup_rule_v2" "zosci_secgroup_rule_allow_k8s" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  security_group_id = openstack_networking_secgroup_v2.zosci_secgroup.id
  remote_group_id   = "${data.openstack_networking_secgroup_v2.k8s_cluster_secgroup.id}"
}


# ports that will allocate an ip address, although the port stays disabled, so
# the ip address can be used as virtual ip address (VIP).
resource "openstack_networking_port_v2" "vip_port" {
  count                 = var.num_vips
  name                  = "${format("TEST_VIP%02d", count.index)}"
  network_id            = var.vip_network_id
  admin_state_up        = false
  port_security_enabled = false
  tags                  = ["vip", "zosci", "${format("TEST_VIP%02d", count.index)}"]
  fixed_ip {
    subnet_id = var.vip_subnet_id
  }
}


# # data sources
# data "openstack_images_image_v2" "ubuntu_noble" {
#   name        = "auto-sync/ubuntu-noble-24.04-amd64-server-20240710-disk1.img"
#   most_recent = true

#   properties = {
#     os_distro    = "ubuntu"
#     os_version   = "24.04"
#     product_name = "com.ubuntu.cloud:server:24.04:amd64"
#   }
# }

output "vip_addresses" {
  value       = {for item in openstack_networking_port_v2.vip_port : item.name => item.all_fixed_ips[0]}
  description = "Ports allocated to be used as virtual IP addresses"
}
