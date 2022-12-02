# Copyright (c) 2022, Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# 

terraform {
  required_version = ">= 1.1"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 4, < 5"
      # https://registry.terraform.io/providers/oracle/oci/
      configuration_aliases = [oci.home_region, oci.current_region]
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
      # https://registry.terraform.io/providers/hashicorp/kubernetes/
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2"
      # https://registry.terraform.io/providers/hashicorp/helm/
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4"
      # https://registry.terraform.io/providers/hashicorp/tls/
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2"
      # https://registry.terraform.io/providers/hashicorp/local/
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3"
      # https://registry.terraform.io/providers/hashicorp/random/
    }
  }
}
