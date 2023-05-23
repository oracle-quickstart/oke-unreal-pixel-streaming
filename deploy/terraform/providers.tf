# Copyright (c) 2023, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
#

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  region       = var.region

  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

provider "oci" {
  alias        = "home_region"
  tenancy_ocid = var.tenancy_ocid
  region       = local.home_region

  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

# New configuration to avoid Terraform Kubernetes provider interpolation. https://registry.terraform.io/providers/hashicorp/kubernetes/2.2.0/docs#stacking-with-managed-kubernetes-cluster-resources
# Currently need to uncheck to refresh (--refresh=false) when destroying or else the terraform destroy will fail

# https://docs.cloud.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm#notes
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  insecure               = local.external_private_endpoint
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["ce", "cluster", "generate-token", "--cluster-id", local.cluster_id, "--region", local.cluster_region]
    command     = "oci"
  }
}

# https://docs.cloud.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm#notes
provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    insecure               = local.external_private_endpoint
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["ce", "cluster", "generate-token", "--cluster-id", local.cluster_id, "--region", local.cluster_region]
      command     = "oci"
    }
  }
}

locals {
  cluster_endpoint          = yamldecode(module.oke-quickstart.kubeconfig)["clusters"][0]["cluster"]["server"]
  external_private_endpoint = false
  # cluster_endpoint = (var.cluster_endpoint_visibility == "Private") ? (
  #   "https://${module.oke.orm_private_endpoint_oke_api_ip_address}:6443") : (
  # yamldecode(module.oke.kubeconfig)["clusters"][0]["cluster"]["server"])
  # external_private_endpoint = (var.cluster_endpoint_visibility == "Private") ? true : false
  cluster_ca_certificate = base64decode(yamldecode(module.oke-quickstart.kubeconfig)["clusters"][0]["cluster"]["certificate-authority-data"])
  cluster_id             = yamldecode(module.oke-quickstart.kubeconfig)["users"][0]["user"]["exec"]["args"][4]
  cluster_region         = yamldecode(module.oke-quickstart.kubeconfig)["users"][0]["user"]["exec"]["args"][6]
}

# Gets home and current regions
data "oci_identity_tenancy" "tenant_details" {
  tenancy_id = var.tenancy_ocid
}
data "oci_identity_regions" "home_region" {
  filter {
    name   = "key"
    values = [data.oci_identity_tenancy.tenant_details.home_region_key]
  }

  count = var.home_region != "" ? 0 : 1
}
locals {
  home_region = var.home_region != "" ? var.home_region : lookup(data.oci_identity_regions.home_region.0.regions.0, "name")
}
