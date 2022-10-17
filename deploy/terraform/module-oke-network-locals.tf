# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# File Version: 0.7.1

# Dependencies:
#   - module-oci-networking.tf file
#   - module-defaults.tf file

# Required locals for the oci-networking module
locals {
  create_new_vcn                = (var.create_new_oke_cluster && var.create_new_vcn) ? true : false
  create_subnets                = (var.create_new_oke_cluster || var.create_subnets) ? true : false
  subnets                       = concat(local.subnets_oke, local.subnet_vcn_native_pod_networking, local.subnet_fss_mount_targets)
  route_tables                  = concat(local.route_tables_oke)
  security_lists                = concat(local.security_lists_oke)
  resolved_vcn_compartment_ocid = (var.create_new_compartment_for_oke ? local.oke_compartment_ocid : var.compartment_ocid)
}

# OKE Subnets definitions
locals {
  subnets_oke = [
    {
      subnet_name                = "oke_k8s_endpoint_subnet"
      cidr_block                 = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
      display_name               = "OKE K8s Endpoint subnet (${local.deploy_id})"
      dns_label                  = "okek8s${local.deploy_id}"
      prohibit_public_ip_on_vnic = (var.cluster_endpoint_visibility == "Private") ? true : false
      prohibit_internet_ingress  = (var.cluster_endpoint_visibility == "Private") ? true : false
      route_table_id             = (var.cluster_endpoint_visibility == "Private") ? module.route_tables["private"].route_table_id : module.route_tables["public"].route_table_id
      dhcp_options_id            = module.vcn.default_dhcp_options_id
      security_list_ids          = [module.security_lists["oke_endpoint_security_list"].security_list_id]
      ipv6cidr_block             = null
    },
    {
      subnet_name                = "oke_nodes_subnet"
      cidr_block                 = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
      display_name               = "OKE Nodes subnet (${local.deploy_id})"
      dns_label                  = "okenodes${local.deploy_id}"
      prohibit_public_ip_on_vnic = (var.cluster_workers_visibility == "Private") ? true : false
      prohibit_internet_ingress  = (var.cluster_workers_visibility == "Private") ? true : false
      route_table_id             = (var.cluster_workers_visibility == "Private") ? module.route_tables["private"].route_table_id : module.route_tables["public"].route_table_id
      dhcp_options_id            = module.vcn.default_dhcp_options_id
      security_list_ids          = [module.security_lists["oke_nodes_security_list"].security_list_id]
      ipv6cidr_block             = null
    },
    {
      subnet_name                = "oke_lb_subnet"
      cidr_block                 = lookup(local.network_cidrs, "LB-REGIONAL-SUBNET-CIDR")
      display_name               = "OKE LoadBalancers subnet (${local.deploy_id})"
      dns_label                  = "okelb${local.deploy_id}"
      prohibit_public_ip_on_vnic = (var.cluster_load_balancer_visibility == "Private") ? true : false
      prohibit_internet_ingress  = (var.cluster_load_balancer_visibility == "Private") ? true : false
      route_table_id             = (var.cluster_load_balancer_visibility == "Private") ? module.route_tables["private"].route_table_id : module.route_tables["public"].route_table_id
      dhcp_options_id            = module.vcn.default_dhcp_options_id
      security_list_ids          = [module.security_lists["oke_lb_security_list"].security_list_id]
      ipv6cidr_block             = null
    }
  ]
  subnet_vcn_native_pod_networking = [] # 10.20.128.0/17 (1,1) = 32766 usable IPs (10.20.128.0 - 10.20.255.255)
  subnet_fss_mount_targets         = [] # 10.20.20.64/26 (10,81) = 62 usable IPs (10.20.20.64 - 10.20.20.255)
}

# OKE Route Tables definitions
locals {
  route_tables_oke = [
    {
      route_table_name = "private"
      display_name     = "OKE Private Route Table (${local.deploy_id})"
      route_rules = [
        {
          description       = "Traffic to the internet"
          destination       = lookup(local.network_cidrs, "ALL-CIDR")
          destination_type  = "CIDR_BLOCK"
          network_entity_id = module.gateways.nat_gateway_id
        },
        {
          description       = "Traffic to OCI services"
          destination       = lookup(data.oci_core_services.all_services_network.services[0], "cidr_block")
          destination_type  = "SERVICE_CIDR_BLOCK"
          network_entity_id = module.gateways.service_gateway_id
      }]

    },
    {
      route_table_name = "public"
      display_name     = "OKE Public Route Table (${local.deploy_id})"
      route_rules = [
        {
          description       = "Traffic to/from internet"
          destination       = lookup(local.network_cidrs, "ALL-CIDR")
          destination_type  = "CIDR_BLOCK"
          network_entity_id = module.gateways.internet_gateway_id
      }]
  }]
}

# OKE Security Lists definitions
locals {
  security_lists_oke = [
    {
      security_list_name = "oke_nodes_security_list"
      display_name       = "OKE Node Workers Security List (${local.deploy_id})"
      egress_security_rules = [
        {
          description      = "Allow pods on one worker node to communicate with pods on other worker nodes"
          destination      = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.all_protocols
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Worker Nodes access to Internet"
          destination      = lookup(local.network_cidrs, "ALL-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.all_protocols
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Allow nodes to communicate with OKE to ensure correct start-up and continued functioning"
          destination      = lookup(data.oci_core_services.all_services_network.services[0], "cidr_block")
          destination_type = "SERVICE_CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = local.security_list_ports.https_port_number, min = local.security_list_ports.https_port_number, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "ICMP Access from Kubernetes Control Plane"
          destination      = lookup(local.network_cidrs, "ALL-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.icmp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = { type = "3", code = "4" }
          }, {
          description      = "Access to Kubernetes API Endpoint"
          destination      = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = local.security_list_ports.k8s_api_endpoint_port_number, min = local.security_list_ports.k8s_api_endpoint_port_number, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Kubernetes worker to control plane communication"
          destination      = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = local.security_list_ports.k8s_worker_to_control_plane_port_number, min = local.security_list_ports.k8s_worker_to_control_plane_port_number, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Path discovery"
          destination      = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.icmp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = { type = "3", code = "4" }
      }]
      ingress_security_rules = [
        {
          description  = "Allow pods on one worker node to communicate with pods on other worker nodes"
          source       = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.all_protocols
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Inbound SSH traffic to worker nodes"
          source       = lookup(local.network_cidrs, (var.cluster_workers_visibility == "Private") ? "VCN-MAIN-CIDR" : "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.ssh_port_number, min = local.security_list_ports.ssh_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "TCP access from Kubernetes Control Plane"
          source       = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Path discovery"
          source       = lookup(local.network_cidrs, "ENDPOINT-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.icmp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = { type = "3", code = "4" }
      }]
    },
    {
      security_list_name     = "oke_lb_security_list"
      display_name           = "OKE Load Balancer Security List (${local.deploy_id})"
      egress_security_rules  = []
      ingress_security_rules = []
    },
    {
      security_list_name = "oke_endpoint_security_list"
      display_name       = "OKE K8s API Endpoint Security List (${local.deploy_id})"
      egress_security_rules = [
        {
          description      = "Allow Kubernetes Control Plane to communicate with OKE"
          destination      = lookup(data.oci_core_services.all_services_network.services[0], "cidr_block")
          destination_type = "SERVICE_CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = local.security_list_ports.https_port_number, min = local.security_list_ports.https_port_number, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "All traffic to worker nodes"
          destination      = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Path discovery"
          destination      = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.icmp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = { type = "3", code = "4" }
      }]
      ingress_security_rules = [
        {
          description  = "External access to Kubernetes API endpoint"
          source       = lookup(local.network_cidrs, (var.cluster_endpoint_visibility == "Private") ? "VCN-MAIN-CIDR" : "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.k8s_api_endpoint_port_number, min = local.security_list_ports.k8s_api_endpoint_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Kubernetes worker to Kubernetes API endpoint communication"
          source       = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.k8s_api_endpoint_port_number, min = local.security_list_ports.k8s_api_endpoint_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Kubernetes worker to control plane communication"
          source       = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.k8s_worker_to_control_plane_port_number, min = local.security_list_ports.k8s_worker_to_control_plane_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Path discovery"
          source       = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.icmp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = { type = "3", code = "4" }
      }]
    }
  ]
  security_list_ports = {
    http_port_number                        = 80
    https_port_number                       = 443
    k8s_api_endpoint_port_number            = 6443
    k8s_worker_to_control_plane_port_number = 12250
    ssh_port_number                         = 22
    tcp_protocol_number                     = "6"
    icmp_protocol_number                    = "1"
    all_protocols                           = "all"
  }
}

# Network locals
locals {
  network_cidrs = {
    VCN-MAIN-CIDR                                  = local.vcn_cidr_blocks[0]                     # e.g.: "10.20.0.0/16" = 65536 usable IPs
    ENDPOINT-REGIONAL-SUBNET-CIDR                  = cidrsubnet(local.vcn_cidr_blocks[0], 12, 0)  # e.g.: "10.20.0.0/28" = 15 usable IPs
    NODES-REGIONAL-SUBNET-CIDR                     = cidrsubnet(local.vcn_cidr_blocks[0], 6, 3)   # e.g.: "10.20.12.0/22" = 1021 usable IPs (10.20.12.0 - 10.20.15.255)
    LB-REGIONAL-SUBNET-CIDR                        = cidrsubnet(local.vcn_cidr_blocks[0], 6, 4)   # e.g.: "10.20.16.0/22" = 1021 usable IPs (10.20.16.0 - 10.20.19.255)
    FSS-MOUNT-TARGETS-REGIONAL-SUBNET-CIDR         = cidrsubnet(local.vcn_cidr_blocks[0], 10, 81) # e.g.: "10.20.20.64/26" = 62 usable IPs (10.20.20.64 - 10.20.20.255)
    APIGW-FN-REGIONAL-SUBNET-CIDR                  = cidrsubnet(local.vcn_cidr_blocks[0], 8, 30)  # e.g.: "10.20.30.0/24" = 254 usable IPs (10.20.30.0 - 10.20.30.255)
    VCN-NATIVE-POD-NETWORKING-REGIONAL-SUBNET-CIDR = cidrsubnet(local.vcn_cidr_blocks[0], 1, 1)   # e.g.: "10.20.128.0/17" = 32766 usable IPs (10.20.128.0 - 10.20.255.255)
    PODS-CIDR                                      = "10.244.0.0/16"
    KUBERNETES-SERVICE-CIDR                        = "10.96.0.0/16"
    ALL-CIDR                                       = "0.0.0.0/0"
  }
}

# Available OCI Services
data "oci_core_services" "all_services_network" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# OKE Network Visibility (Workers, Endpoint and Load Balancers)
variable "cluster_workers_visibility" {
  default     = "Private"
  description = "The Kubernetes worker nodes that are created will be hosted in public or private subnet(s)"

  validation {
    condition     = var.cluster_workers_visibility == "Private" || var.cluster_workers_visibility == "Public"
    error_message = "Sorry, but cluster visibility can only be Private or Public."
  }
}
variable "cluster_endpoint_visibility" {
  default     = "Public"
  description = "The Kubernetes cluster that is created will be hosted on a public subnet with a public IP address auto-assigned or on a private subnet. If Private, additional configuration will be necessary to run kubectl commands"

  validation {
    condition     = var.cluster_endpoint_visibility == "Private" || var.cluster_endpoint_visibility == "Public"
    error_message = "Sorry, but cluster endpoint visibility can only be Private or Public."
  }
}
variable "cluster_load_balancer_visibility" {
  default     = "Public"
  description = "The Load Balancer that is created will be hosted on a public subnet with a public IP address auto-assigned or on a private subnet. This affects the Kubernetes services, ingress controller and other load balancers resources"

  validation {
    condition     = var.cluster_load_balancer_visibility == "Private" || var.cluster_load_balancer_visibility == "Public"
    error_message = "Sorry, but cluster load balancer visibility can only be Private or Public."
  }
}

# OKE Network Resources
## Subnets
# VCN Variables
variable "create_subnets" {
  default     = true
  description = "Create subnets for OKE: Endpoint, Nodes, Load Balancers. If CNI Type VCN-Native, also creates the PODs VCN. If FSS Mount Targets, also creates the FSS Mount Targets Subnet"
}
variable "existent_oke_k8s_endpoint_subnet_ocid" {
  default     = ""
  description = "The OCID of the subnet where the Kubernetes cluster endpoint will be hosted"
}
variable "existent_oke_nodes_subnet_ocid" {
  default     = ""
  description = "The OCID of the subnet where the Kubernetes worker nodes will be hosted"
}
variable "existent_oke_load_balancer_subnet_ocid" {
  default     = ""
  description = "The OCID of the subnet where the Kubernetes load balancers will be hosted"
}
variable "existent_oke_vcn_native_pod_networking_subnet_ocid" {
  default     = ""
  description = "The OCID of the subnet where the Kubernetes VCN Native Pod Networking will be hosted"
}
variable "existent_oke_fss_mount_targets_subnet_ocid" {
  default     = ""
  description = "The OCID of the subnet where the Kubernetes FSS mount targets will be hosted"
}
# variable "existent_apigw_fn_subnet_ocid" {
#   default     = ""
#   description = "The OCID of the subnet where the API Gateway and Functions will be hosted"
# }
