variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "identity_id" {
  description = "Resource ID of the user-assigned managed identity used for both the container app's identity and ACR pull."
  type        = string
}

variable "registry_server" {
  description = "Login server of the ACR to pull from."
  type        = string
}

variable "container_image" {
  type = string
}

variable "container_cpu" {
  type = number
}

variable "container_memory" {
  type = string
}

variable "min_replicas" {
  type = number
}

variable "max_replicas" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
