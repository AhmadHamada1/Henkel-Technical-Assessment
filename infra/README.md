# Infra (Terraform / Azure)

Provisions: resource group, Azure Container Registry (admin auth disabled),
a user-assigned managed identity with `AcrPull` on the registry, a Log
Analytics workspace, and an Azure Container Apps environment + Container App
that serves the image built in `../app`.

## Usage

```bash
cd infra
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

Requires `az login` (or `ARM_*` environment variables / OIDC in CI) with
Contributor + User Access Administrator (for the role assignment) on the
target subscription.

**This was not run against a live subscription in this exercise** — there
were no Azure credentials available in the build sandbox. `terraform fmt`
was run; `terraform validate`/`plan`/`apply` were not executed because the
Terraform CLI itself was not installed in the sandbox either. The files were
written by hand against the `azurerm` provider docs and cross-checked
argument-by-argument, but treat them as **unverified against a live
provider** until someone runs `terraform validate` with the CLI installed.

## State

Local state only (`terraform.tfstate` in this directory, gitignored). For
any real/shared use this needs a remote backend — see the commented
`backend "azurerm" {}` block in `providers.tf`. Local state is fine for a
single-person take-home exercise but is explicitly **not** production-ready
(no locking, no shared state, state file with secrets sitting on a laptop).

## Notes on design choices

- **Container Apps over AKS/App Service**: lowest operational overhead for a
  single small service, still supports managed identity, scale-to-zero, and
  ingress out of the box. See the top-level README for the explicit
  tradeoff discussion against AKS (which would be the natural choice if this
  service needed to match the Section 3/4 Kubernetes-based architecture).
- **ACR admin account disabled**: all registry access goes through Azure AD
  identities (the CI pipeline's federated OIDC identity for push, this
  module's user-assigned identity for pull) instead of the shared
  username/password admin credential.
- **`min_replicas = 0` by default**: scale-to-zero saves cost for a demo
  environment; set to `1+` for latency-sensitive or production use.
