# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

################################################################################
# OKE Cluster
################################################################################
module "oke-quickstart" {
  source = "github.com/oracle-quickstart/terraform-oci-oke-quickstart?ref=0.8.7"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  region           = var.region

  # Note: Just few arguments are showing here to simplify the basic example. All other arguments are using default values.
  # App Name to identify deployment. Used for naming resources.
  app_name = "Unreal Pixel Streaming"

  # Freeform Tags + Defined Tags. Tags are applied to all resources.
  tag_values = { "freeformTags" = { "Environment" = "Development", "DeploymentType" = "basic", "Quickstart" = "terraform-oke-unreal-pixel-streaming" }, "definedTags" = {} }

  # VCN for OKE arguments
  vcn_cidr_blocks      = "10.20.0.0/16"
  extra_security_lists = local.extra_security_lists
  extra_subnets        = local.extra_subnets

  # OKE Node Pool 1 arguments
  node_pool_cni_type_1                 = "FLANNEL_OVERLAY" # Use "OCI_VCN_IP_NATIVE" for VCN Native PODs Network. If the node pool 1 uses the OCI_VCN_IP_NATIVE, the cluster will also be configured with same cni
  cluster_autoscaler_enabled           = false
  node_pool_name_1                     = "Default"
  node_pool_initial_num_worker_nodes_1 = 3                                                                       # Minimum number of nodes in the node pool
  node_pool_max_num_worker_nodes_1     = 10                                                                      # Maximum number of nodes in the node pool
  node_pool_instance_shape_1           = { "instanceShape" = "VM.Standard.E4.Flex", "ocpus" = 2, "memory" = 64 } # If not using a Flex shape, ocpus and memory are ignored
  extra_node_pools                     = local.extra_node_pools

}

