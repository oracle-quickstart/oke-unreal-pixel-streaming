locals {
  extra_security_lists = [
    {
      security_list_name = "turn_for_nodes_security_list"
      display_name       = "TURN subnet for nodes Security List"
      egress_security_rules = [
        {
          description      = "Allow pods on turn nodes to communicate with pods on other worker nodes"
          destination      = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          destination_type = "CIDR_BLOCK"
          protocol         = local.security_list_ports.all_protocols
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
          }]
      ingress_security_rules = [
        {
          description  = "Allow pods on turn nodes to communicate with pods on other worker nodes"
          source       = lookup(local.network_cidrs, "NODES-REGIONAL-SUBNET-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.all_protocols
          stateless    = false
          tcp_options  = { max = -1, min = -1, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
          }]
    },]
  extra_subnets        = []
  extra_node_pools     = []
}