# Infra (Terraform / Azure)

```
infra/
  main.tf, variables.tf, outputs.tf, providers.tf   # root module
  backend.hcl.example                                # copy to backend.hcl (gitignored)
  modules/
    registry/        # Azure Container Registry, admin auth disabled
    identity/         # user-assigned managed identity
    container_app/    # Log Analytics workspace + Container Apps environment + app
```

The root module wires the three together: `identity` gets `AcrPull` on `registry`,
and `container_app` runs the image built in `../app`, pulling from `registry`
using `identity` — no stored credentials anywhere.

## Remote state

State is stored in Azure Blob Storage rather than locally, so it can be
shared and locked across engineers/CI. The storage account itself has to
exist before Terraform can use it as a backend (a chicken-and-egg problem
Terraform can't solve for its own backend), so bootstrap it once with the
Azure CLI:

```bash
az group create -n rg-henkelassess-tfstate -l westeurope
az storage account create -n henkelassesstfstate -g rg-henkelassess-tfstate -l westeurope --sku Standard_LRS
az storage container create -n tfstate --account-name henkelassesstfstate
```

Then:

```bash
cp backend.hcl.example backend.hcl   # fill in real values, not committed
terraform init -backend-config=backend.hcl
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

CI would pass the same `-backend-config` values (or `ARM_*`/`TF_*` env vars)
non-interactively; only the storage account name/keys differ per environment,
so `backend.hcl` is gitignored and `backend.hcl.example` documents the shape.

Requires `az login` (or `ARM_*` env vars / OIDC in CI) with Contributor +
User Access Administrator (for the role assignment) on the target subscription.

**This was not run against a live subscription in this exercise** — there
were no Azure credentials or a pre-existing state storage account available
in the build sandbox. `terraform fmt` was run; `terraform validate`/`plan`/
`apply` were not executed because the Terraform CLI itself was not installed
in the sandbox either. The files were written by hand against the `azurerm`
provider docs and cross-checked argument-by-argument, but treat them as
**unverified against a live provider** until someone runs `terraform
validate` with the CLI installed.

## Notes on design choices

- **Modules over one flat file**: `registry`, `identity`, and `container_app`
  are separated because they're independently reusable/testable units with a
  clear single responsibility; the root module's job is just to wire their
  inputs/outputs together plus the one cross-cutting resource (the role
  assignment) that genuinely belongs at the composition layer.
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
