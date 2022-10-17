# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

variable "app_name" {
  default     = "K8s App"
  description = "Application name. Will be used as prefix to identify resources, such as OKE, VCN, ATP, and others"
}
variable "tag_values" {
  type = map(any)
  default = { "freeformTags" = {
    "Environment" = "Development",  # e.g.: Demo, Sandbox, Development, QA, Stage, ...
    "DeploymentType" = "generic" }, # e.g.: App Type 1, App Type 2, Red, Purple, ...
  "definedTags" = {} }
  description = "Use Tagging to add metadata to resources. All resources created by this stack will be tagged with the selected tag values."
}

# Locals
locals {
  deploy_id   = random_string.deploy_id.result
  deploy_tags = { "DeploymentID" = local.deploy_id, "AppName" = local.app_name, "Quickstart" = "oke_base" }
  oci_tag_values = {
    "freeformTags" = merge(var.tag_values.freeformTags, local.deploy_tags),
    "definedTags"  = var.tag_values.definedTags
  }
  app_name            = var.app_name
  app_name_normalized = substr(replace(lower(local.app_name), " ", "-"), 0, 6)
  app_name_for_dns    = substr(lower(replace(local.app_name, "/\\W|_|\\s/", "")), 0, 6)
}

resource "random_string" "deploy_id" {
  length  = 4
  special = false
}

output "deploy_id" {
  value = local.deploy_id
}