# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

################################################################################
# OKE Cluster
################################################################################
module "oke-quickstart" {
  source = "github.com/oracle-quickstart/terraform-oci-oke-quickstart?ref=0.8.8"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  region           = var.region

  # Note: Just few arguments are showing here to simplify the basic example. All other arguments are using default values.
  # App Name to identify deployment. Used for naming resources.
  app_name = "Unreal Pixel Streaming"

  # Freeform Tags + Defined Tags. Tags are applied to all resources.
  tag_values = { "freeformTags" = { "Environment" = "Development", "DeploymentType" = "full", "Quickstart" = "terraform-oke-unreal-pixel-streaming" }, "definedTags" = {} }

  # VCN for OKE arguments
  vcn_cidr_blocks                           = "10.20.0.0/16"
  extra_security_lists                      = local.extra_security_lists
  extra_subnets                             = local.extra_subnets
  extra_security_list_name_for_api_endpoint = "turn_for_k8s_api_security_list"

  # OKE Node Pool 1 arguments
  node_pool_cni_type_1                 = "FLANNEL_OVERLAY" # Use "OCI_VCN_IP_NATIVE" for VCN Native PODs Network. If the node pool 1 uses the OCI_VCN_IP_NATIVE, the cluster will also be configured with same cni
  cluster_autoscaler_enabled           = false
  node_pool_name_1                     = "Default"
  node_pool_initial_num_worker_nodes_1 = 3  # Minimum number of nodes in the node pool
  node_pool_max_num_worker_nodes_1     = 10 # Maximum number of nodes in the node pool
  node_pool_instance_shape_1           = var.node_pool_instance_shape_1
  extra_node_pools                     = local.extra_node_pools
  extra_security_list_name_for_nodes   = "turn_for_nodes_security_list"

  # Cluster Tools
  ingress_nginx_enabled = true
  cert_manager_enabled  = true
}

# Extra Node Pools for TURN and GPU node pools
locals {
  extra_node_pools = [{
    node_pool_name                            = "Turn"
    node_pool_min_nodes                       = 1
    node_pool_max_nodes                       = 1
    node_k8s_version                          = "Latest"
    node_pool_shape                           = var.node_pool_instance_shape_turn.instanceShape
    node_pool_shape_specific_ad               = 0
    node_pool_node_shape_config_ocpus         = var.node_pool_instance_shape_turn.ocpus
    node_pool_node_shape_config_memory_in_gbs = var.node_pool_instance_shape_turn.memory
    node_pool_boot_volume_size_in_gbs         = "100"
    existent_oke_nodepool_id_for_autoscaler   = null
    node_pool_alternative_subnet              = "turn_nodes_subnet"
    image_operating_system                    = "Oracle Linux"
    image_operating_system_version            = "8"
    extra_initial_node_labels                 = [{ key = "app.pixel/turn", value = "true" }]
    cni_type                                  = "FLANNEL_OVERLAY"
    }, {
    node_pool_name                            = "GPU"
    node_pool_min_nodes                       = 1
    node_pool_max_nodes                       = 1
    node_k8s_version                          = "Latest"
    node_pool_shape                           = var.node_pool_instance_shape_gpu.instanceShape
    node_pool_shape_specific_ad               = var.node_pool_shape_specific_ad_gpu
    node_pool_node_shape_config_ocpus         = var.node_pool_instance_shape_gpu.ocpus
    node_pool_node_shape_config_memory_in_gbs = var.node_pool_instance_shape_gpu.memory
    node_pool_boot_volume_size_in_gbs         = "100"
    existent_oke_nodepool_id_for_autoscaler   = null
    node_pool_alternative_subnet              = null
    image_operating_system                    = "Oracle Linux"
    image_operating_system_version            = "8"
    extra_initial_node_labels                 = [{ key = "app.pixel/gpu", value = "true" }]
    cni_type                                  = "FLANNEL_OVERLAY"
  }, ]
}
