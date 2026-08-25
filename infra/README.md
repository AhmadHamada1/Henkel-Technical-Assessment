# Infra (Terraform / Azure)

```
infra/
  main.tf, variables.tf, outputs.tf, providers.tf   # root module
  backend.hcl.example                                # copy to backend.hcl (gitignored)
  modules/
    registry/        # Azure Container Registry, admin auth disabled
    identity/         # user-assigned managed identity
    container_app/    # Log Analytics + Container Apps environment + app
```

Root module wires them together: `identity` gets `AcrPull` on `registry`,
`container_app` pulls from `registry` using `identity` — no stored
credentials anywhere.

## Remote state

State lives in Azure Blob Storage, not locally. The storage account has to
exist before Terraform can use it as a backend, so bootstrap it once:

```bash
az group create -n rg-henkelassess-tfstate -l westeurope
az storage account create -n henkelassesstfstate -g rg-henkelassess-tfstate -l westeurope --sku Standard_LRS
az storage container create -n tfstate --account-name henkelassesstfstate
```

Then:

```bash
cp backend.hcl.example backend.hcl   # fill in real values, not committed
terraform init -backend-config=backend.hcl
terraform plan -out plan.tfplan && terraform apply plan.tfplan
```

Needs `az login` (or `ARM_*`/OIDC in CI) with Contributor + User Access
Administrator on the target subscription.

**Verified:** `terraform fmt`, `init -backend=false`, and `validate` have
actually been run and pass clean. **Not verified:** `plan`/`apply` — no
Azure credentials or state storage account available for this exercise.

## Why these choices

- **Modules, not one flat file** — `registry`/`identity`/`container_app` are independent, reusable units; the root module just wires them together.
- **Container Apps, not AKS** — lowest ops overhead for one small service (tradeoff discussed in the top-level README).
- **ACR admin disabled** — registry access is Azure AD only (OIDC for push, managed identity for pull).
- **`min_replicas = 0`** — scale-to-zero for a demo environment; use `1+` for production.
