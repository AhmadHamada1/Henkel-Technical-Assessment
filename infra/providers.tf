terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  # Partial config: values are supplied via `-backend-config=backend.hcl` at init time, see infra/README.md.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
