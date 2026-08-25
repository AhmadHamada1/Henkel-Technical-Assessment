terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  # No backend block: this exercise uses local state; see infra/README.md.
}

provider "azurerm" {
  features {}
}
