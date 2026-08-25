# Henkel Technical Assessment — Platform Engineer / DevOps Engineer

Solution to the 4-part Henkel take-home: containerize + IaC + CI/CD (1),
security hardening (2), multi-cloud network design (3), observability/SRE
design (4).

## Repo structure

```
.
├── app/                    Express app — GET /, GET /health, port 8080
├── Dockerfile               Multi-stage, non-root, minimal base
├── infra/                   Terraform (Azure) — see infra/README.md
│   └── modules/              registry / identity / container_app
├── .github/workflows/pipeline.yaml   CI/CD — the one actually wired to this repo
├── .azuredevops/pipeline.yaml         Parallel Azure DevOps version, illustrative only (see below)
├── docs/
│   ├── network-design.md + network-diagram.svg    Section 3 (SVG, not .drawio/.png — see file)
│   ├── observability.md + alerts.yaml             Section 4
│   ├── security-scan-output.txt                   Real CI scan timeline
│   └── screenshots/                                Real run screenshots
└── .trivyignore / .dockerignore
```

## Quick start

**App**
```bash
cd app && npm install && npm test && node server.js
curl http://localhost:8080/health   # {"status":"ok"}
```

**Docker**
```bash
docker build -t henkel-app .
docker run -d -p 8080:8080 henkel-app
curl http://localhost:8080/health
```

**Terraform** (plan only — no live Azure account wired up)
```bash
cd infra
cp backend.hcl.example backend.hcl   # fill in real state storage values
terraform init -backend-config=backend.hcl && terraform plan
```

**CI/CD** ([`pipeline.yaml`](.github/workflows/pipeline.yaml), on every push/PR to `main`):
`build-test` → `security-scan` (Trivy, fails on CRITICAL/HIGH) → `push` (ACR, main only) → `deploy` (Container Apps, main only).
`push`/`deploy` need these repo variables plus a federated credential (OIDC, no client secret):

| Variable | Purpose |
|---|---|
| `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` | OIDC login |
| `ACR_NAME` | Registry name (`terraform output acr_login_server`) |
| `AZURE_RESOURCE_GROUP` / `CONTAINER_APP_NAME` | Deploy target |

## Key decisions

- **Node/Express** — the app is intentionally trivial; the assessment is about the platform around it.
- **Container Apps, not AKS** — lowest ops overhead for one small service. Deliberately inconsistent with Sections 3/4 (which are K8s-based); AKS would be the pick if this had to join that architecture.
- **GitHub Actions as the primary CI/CD** — repo lives on GitHub. [`.azuredevops/pipeline.yaml`](.azuredevops/pipeline.yaml) is also included as a literal parallel to the brief's example path, mirroring the same 4 jobs and OIDC auth — but it's illustrative only, never run against a real Azure DevOps org.
- **Trivy** — one tool for both SCA and image scanning, free, SARIF-integrated.
- **OIDC everywhere** — no static Azure/ACR credentials stored in GitHub.

## Security (Section 2)

**Hardened:**
- Non-root `node` user, multi-stage build, no dev deps or secrets in the image.
- `apk upgrade` + stripped `npm`/`npx`/`corepack`/`yarn` from the runtime image — see below, this is what a real scan finding drove.
- Trivy (SCA + image) gates the pipeline: any CRITICAL/HIGH fails the build.
- OIDC for both ACR push and Container Apps deploy; ACR admin auth disabled; the pull identity has only `AcrPull`.

**Real finding → fix → verified** (not simulated — see [`docs/security-scan-output.txt`](docs/security-scan-output.txt) and [`docs/screenshots/`](docs/screenshots/)):
1. First real scan run failed the build: 1 CRITICAL + 18 HIGH Node.js CVEs — all traced to npm's/yarn's own bundled deps in the base image, not the app's `node_modules`. Plus 1 HIGH openssl CVE in alpine.
2. Fix: deleted npm/npx/corepack/yarn from the runtime image (app only runs `node server.js`), added `apk upgrade`.
3. Next run: `security-scan` passed clean.

(Two earlier runs also failed before any scan ran, over bad `trivy-action` version pins — also fixed, also logged in the same file.)

**Deferred (time-boxed), would add next:** image signing/SBOM (cosign), Private Endpoint for ACR (needs Premium SKU), scheduled image rebuilds for OS patching, WAF, secrets rotation.

## Known limitations

- Terraform: `fmt`/`init`/`validate` pass for real (see below), but never `plan`/`apply`'d against live Azure — no credentials here.
- `push`/`deploy` pipeline jobs: untested — need the repo variables above configured.
- No autoscaling load test, no WAF, no service mesh/mTLS (noted as future work in the network design), and severity-only scan gating doesn't weigh exploitability (would pair with a tool like Dependency-Track in a real setting).

## What was actually verified

| Item | Status |
|---|---|
| App install/test/run, `curl /health` | Ran locally — 2/2 tests pass, endpoints correct |
| Docker build/run | Not run locally (no daemon) — **ran repeatedly in CI**, green every time |
| Trivy SCA + image scan | **Ran for real in CI** — a genuine fail→fix→pass cycle, see Security above |
| SARIF → code scanning | Ran in CI on every scan |
| `terraform fmt`/`init`/`validate` | **Ran for real** — `fmt` fixed real alignment drift, `init -backend=false` pulled the azurerm provider, `validate` passed clean |
| `terraform plan`/`apply` | Not run — no Azure credentials anywhere |
| `push`/`deploy` jobs | Not run — repo variables not configured |
| `.azuredevops/pipeline.yaml` | Never run anywhere — no Azure DevOps org for this exercise; hand-written to mirror the GitHub workflow's logic |

Everything above the line has real evidence (test output, CI logs, screenshots), not just claims — that was deliberate, not an oversight.
