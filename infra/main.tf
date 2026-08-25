# Resource group plus the registry, identity, and container-app modules,
# wired together with a least-privilege AcrPull role assignment.

locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.project_name}-${var.environment}")
  name_prefix         = "${var.project_name}-${var.environment}"
  # ACR names must be globally unique, alphanumeric only, 5-50 chars.
  acr_name = replace("${var.project_name}${var.environment}acr", "-", "")
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

module "registry" {
  source = "./modules/registry"

  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  tags                = var.tags
}

module "identity" {
  source = "./modules/identity"

  name                = "id-${local.name_prefix}-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.identity.principal_id
}

module "container_app" {
  source = "./modules/container_app"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  identity_id         = module.identity.id
  registry_server     = module.registry.login_server
  container_image     = var.container_image
  container_cpu       = var.container_cpu
  container_memory    = var.container_memory
  min_replicas        = var.min_replicas
  max_replicas        = var.max_replicas
  tags                = var.tags

  depends_on = [azurerm_role_assignment.acr_pull]
}
