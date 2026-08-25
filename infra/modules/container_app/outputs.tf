output "fqdn" {
  value = azurerm_container_app.this.latest_revision_fqdn
}

output "name" {
  value = azurerm_container_app.this.name
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}
