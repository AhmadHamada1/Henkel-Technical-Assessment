variable "name" {
  description = "Name of the Azure Container Registry (globally unique, alphanumeric, 5-50 chars)."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  description = "ACR SKU (Basic/Standard/Premium). Premium is required for private endpoints."
  type        = string
  default     = "Basic"
}

variable "tags" {
  type    = map(string)
  default = {}
}
