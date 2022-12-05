# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

################################################################################
# OCI Provider Variables
################################################################################
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "region" {}
variable "user_ocid" {
  default = ""
}
variable "fingerprint" {
  default = ""
}
variable "private_key_path" {
  default = ""
}

################################################################################
# Variables: OCI Networking
################################################################################
## VCN
variable "vcn_cidr_blocks" {
  default     = "10.26.0.0/16"
  description = "IPv4 CIDR Blocks for the Virtual Cloud Network (VCN). If use more than one block, separate them with comma. e.g.: 10.20.0.0/16,10.80.0.0/16. If you plan to peer this VCN with another VCN, the VCNs must not have overlapping CIDRs."
}

################################################################################
# Variables: OKE Node Pools
################################################################################
#### Note: ocpus and memory are only used if flex shape is selected
variable "node_pool_instance_shape_1" {
  type = map(any)
  default = {
    "instanceShape" = "VM.Standard.E4.Flex"
    "ocpus"         = 4
    "memory"        = 64
  }
  description = "Default Node Pool: A shape is a template that determines the number of OCPUs, amount of memory, and other resources allocated to a newly created instance for the Worker Node. Select at least 2 OCPUs and 16GB of memory if using Flex shapes"
}
variable "node_pool_instance_shape_turn" {
  type = map(any)
  default = {
    "instanceShape" = "VM.Standard.E4.Flex"
    "ocpus"         = 4
    "memory"        = 64
  }
  description = "Turn Node Pool: A shape is a template that determines the number of OCPUs, amount of memory, and other resources allocated to a newly created instance for the Worker Node. Select at least 2 OCPUs and 16GB of memory if using Flex shapes"
}
variable "node_pool_instance_shape_gpu" {
  type = map(any)
  default = {
    "instanceShape" = "BM.GPU.A10.4"
    "ocpus"         = 64
    "memory"        = 1024
  }
  description = "GPU Node Pool: A shape is a template that determines the number of OCPUs, amount of memory, and other resources allocated to a newly created instance for the Worker Node. Select at least 2 OCPUs and 16GB of memory if using Flex shapes"
}
variable "node_pool_shape_specific_ad_gpu" {
  description = "The number of the AD to get the shape for the node pool"
  type        = number
  default     = 0

  validation {
    condition     = var.node_pool_shape_specific_ad_gpu >= 0 && var.node_pool_shape_specific_ad_gpu <= 3
    error_message = "Invalid AD number, should be 0 to get all ADs or 1, 2 or 3 to be a specific AD."
  }
}

################################################################################
# Variables: Unreal Pixel Streaming
################################################################################
# variable "unreal_pixel_streaming_demo" {
#   type        = bool
#   default     = true
#   description = "Deploys Unreal Pixel Streaming Demo deployment helm chart - demo.yaml"
# }