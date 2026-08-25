terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  # No backend block: this exercise uses local state on purpose (see
  # infra README / top-level README "Missing improvements"). A real
  # deployment should configure an `azurerm` remote backend (storage
  # account + container) so state is shared and locked across engineers,
  # e.g.:
  #
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "henkeltfstate"
  #   container_name       = "tfstate"
  #   key                  = "henkel-assessment.tfstate"
  # }
}

provider "azurerm" {
  features {}
}
