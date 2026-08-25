# Infrastructure for the Section 1/2 assessment app:
#   - Resource group
#   - Azure Container Registry (admin account disabled - pull is via managed identity)
#   - User-assigned managed identity, granted AcrPull on the registry
#     (this is the "identities required to host the application")
#   - Log Analytics workspace (required by the Container Apps environment,
#     and doubles as the log sink discussed in docs/observability.md)
#   - Container Apps environment + Container App running the image built by CI

locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.project_name}-${var.environment}")
  name_prefix          = "${var.project_name}-${var.environment}"
  # ACR names must be globally unique, alphanumeric only, 5-50 chars.
  acr_name = replace("${var.project_name}${var.environment}acr", "-", "")
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  # Admin credentials (username/password) are disabled on purpose - all
  # push/pull auth goes through Azure AD identities (CI's federated OIDC
  # identity for push, the Container App's managed identity for pull).
  # See README "Security" section.
  admin_enabled = false
  tags          = var.tags
}

# User-assigned identity so the Container App can pull from ACR without any
# stored credential. This is the identity that satisfies the assessment's
# "provision infra including identities required to host the application".
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.name_prefix}-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# Least-privilege: this identity can only pull images, nothing else.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days    = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${local.name_prefix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags
}

resource "azurerm_container_app" "main" {
  name                         = "ca-${local.name_prefix}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Pull auth: the app's own managed identity, not a stored ACR password.
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport         = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
