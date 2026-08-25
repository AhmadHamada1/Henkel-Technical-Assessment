output "resource_group_name" {
  description = "Name of the resource group holding all resources."
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "Login server (hostname) of the Azure Container Registry, used by CI to tag/push images."
  value       = azurerm_container_registry.main.login_server
}

output "container_app_fqdn" {
  description = "Public FQDN of the deployed Container App, used by CI/CD's post-deploy validation step to curl /health."
  value       = azurerm_container_app.main.latest_revision_fqdn
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity used for ACR pull. Useful when wiring up federated credentials for GitHub Actions OIDC."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "container_app_name" {
  description = "Name of the Container App, needed by `az containerapp update` in the deploy pipeline step."
  value       = azurerm_container_app.main.name
}
