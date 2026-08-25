variable "location" {
  description = "Azure region to deploy all resources into."
  type        = string
  default     = "westeurope"
}

variable "project_name" {
  description = "Short name used as a prefix for all resource names. Keep it lowercase/alphanumeric since it also feeds the globally-unique ACR name."
  type        = string
  default     = "henkelassess"
}

variable "environment" {
  description = "Deployment environment name, used in resource naming and tags (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "resource_group_name" {
  description = "Name of the resource group that will hold all resources. Defaults to a name derived from project_name/environment."
  type        = string
  default     = null
}

variable "container_image" {
  description = "Full container image reference (registry/repo:tag) to deploy to the Container App. The CI/CD pipeline overrides this on each deploy via `az containerapp update --image`; the Terraform-managed value is only used for the initial `terraform apply`."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest" # placeholder "hello world" image so the Container App has something valid to boot with before CI ever pushes a real image
}

variable "container_cpu" {
  description = "vCPU cores allocated to the container app (Container Apps billing increment, e.g. 0.25, 0.5, 1)."
  type        = number
  default     = 0.25
}

variable "container_memory" {
  description = "Memory allocated to the container app, e.g. '0.5Gi', '1Gi'. Must be a valid Container Apps CPU/memory combination."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "Minimum number of replicas for the Container App. 0 allows scale-to-zero for cost savings in non-prod; use >=1 for prod to avoid cold starts."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of replicas the Container App environment will scale out to."
  type        = number
  default     = 3
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry (Basic/Standard/Premium). Premium is required for private endpoints, which is why it's the noted future improvement in the README."
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    project = "henkel-technical-assessment"
    managed_by = "terraform"
  }
}
