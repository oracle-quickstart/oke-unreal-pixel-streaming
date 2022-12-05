# Copyright (c) 2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

# Network locals
locals {
  vcn_cidr_blocks = split(",", var.vcn_cidr_blocks)
  network_cidrs = {
    VCN-MAIN-CIDR             = local.vcn_cidr_blocks[0]                    # e.g.: "10.20.0.0/16" = 65536 usable IPs
    SUBNET-TURN-REGIONAL-CIDR = cidrsubnet(local.vcn_cidr_blocks[0], 8, 11) # e.g.: "10.20.11.0/24" = 256 usable IPs
    ALL-CIDR                  = "0.0.0.0/0"
  }
}

# Extra Security Lists for TURN
locals {
  extra_security_lists = [
    {
      security_list_name = "turn_for_nodes_security_list"
      display_name       = "TURN subnet for nodes Security List"
      ingress_security_rules = [
        {
          description  = "Allow pods on turn nodes to communicate with pods on other worker nodes"
          source       = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.all_protocols
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
      }]
      egress_security_rules = [
        {
          description      = "Allow pods on turn nodes to communicate with pods on other worker nodes"
          destination      = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.all_protocols
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
      }]
      }, {
      security_list_name = "turn_security_list"
      display_name       = "TURN Security List"
      ingress_security_rules = [
        {
          description  = "STUN TCP"
          source       = lookup(local.network_cidrs, "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.stun_turn_port_number, min = local.security_list_ports.stun_turn_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "TURN UDP"
          source       = lookup(local.network_cidrs, "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.udp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = local.security_list_ports.stun_turn_port_number, min = local.security_list_ports.stun_turn_port_number, source_port_range = null }
          icmp_options = null
          }, {
          description  = "STUN Connection ports"
          source       = lookup(local.network_cidrs, "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.stun_turn_connection_port_number_max, min = local.security_list_ports.stun_turn_connection_port_number_min, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "TURN Connection ports"
          source       = lookup(local.network_cidrs, "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.udp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = local.security_list_ports.stun_turn_connection_port_number_max, min = local.security_list_ports.stun_turn_connection_port_number_min, source_port_range = null }
          icmp_options = null
      }, ]
      egress_security_rules = []
      }, {
      security_list_name = "turn_for_k8s_api_security_list"
      display_name       = "TURN for K8s API endpoint Security List"
      ingress_security_rules = [
        {
          description  = "TURN worker to k8s API endpoint"
          source       = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.k8s_api_endpoint_port_number, min = local.security_list_ports.k8s_api_endpoint_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "TURN worker to OKE control plane"
          source       = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.k8s_worker_to_control_plane_port_number, min = local.security_list_ports.k8s_worker_to_control_plane_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }, {
          description  = "Path discovery - TURN"
          source       = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.icmp_protocol_number
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = { type = "3", code = "4" }
      }, ]
      egress_security_rules = [
        {
          description      = "TURN traffic from worker nodes"
          destination      = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.tcp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }, {
          description      = "Path discovery - TURN"
          destination      = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.icmp_protocol_number
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = { type = "3", code = "4" }
      }, ]
  }, ]
  security_list_ports = {
    http_port_number                        = 80
    https_port_number                       = 443
    k8s_api_endpoint_port_number            = 6443
    k8s_api_endpoint_to_worker_port_number  = 10250
    k8s_worker_to_control_plane_port_number = 12250
    stun_turn_port_number                   = 3478
    stun_turn_connection_port_number_min    = 49152
    stun_turn_connection_port_number_max    = 65535
    ssh_port_number                         = 22
    tcp_protocol_number                     = "6"
    udp_protocol_number                     = "17"
    icmp_protocol_number                    = "1"
    all_protocols                           = "all"
  }
}

# Extra Subnet for TURN
locals {
  extra_subnets = [{
    subnet_name                  = "turn_nodes_subnet"
    cidr_block                   = lookup(local.network_cidrs, "SUBNET-TURN-REGIONAL-CIDR")
    display_name                 = "TURN Nodes Subnet"
    dns_label                    = "turn"
    prohibit_public_ip_on_vnic   = false
    prohibit_internet_ingress    = false
    route_table_id               = null
    alternative_route_table_name = "public"
    dhcp_options_id              = ""
    security_list_ids            = []
    extra_security_list_names    = ["oke_nodes_security_list", "turn_for_nodes_security_list", "turn_security_list"]
    ipv6cidr_block               = null
  }, ]
}
