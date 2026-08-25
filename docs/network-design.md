# Network Design — Multi-Cloud Connectivity (Section 3)

## 1. Scenario

- **Frontend application** runs in **AWS EKS**.
- **Backend API** runs in **Azure Kubernetes Service (AKS)**.
- **PostgreSQL database** runs as **Azure Database for PostgreSQL Flexible
  Server**.

Design goal: connect the three across two clouds with **no public
endpoints** on the backend or the database — only the frontend (behind an
ingress/load balancer) is internet-facing. Everything else communicates over
private, encrypted, cross-cloud connectivity.

Diagram: [`network-diagram.svg`](network-diagram.svg) — SVG instead of the
brief's `.drawio`/`.png` because it's plain text (diffable in git, no binary
blob) and renders natively in any browser/GitHub preview without the draw.io
app, while staying just as scalable/vector as `.drawio`.

## 2. Design principle: zero public exposure for backend + data

- The **frontend's ingress/ALB** is the only component with a public IP.
  TLS terminates there.
- The **AKS backend API** is exposed only via an **internal** (private) load
  balancer / ingress — never a public `LoadBalancer` service or public
  ingress class.
- The **AKS API server** itself is deployed as a **private cluster**
  (`--enable-private-cluster`), so cluster management traffic never touches
  the public internet either.
- **PostgreSQL Flexible Server** has **public network access disabled** and
  is reachable only via VNet integration (private access), i.e. it has no
  public endpoint at all — not even one gated by a firewall allow-list.
- Cross-cloud traffic (EKS → AKS) travels over a **private, encrypted
  tunnel** between the two clouds' VPC/VNet, never over the public internet
  in plaintext, and never via public IPs on either side.

## 3. Connectivity choice: site-to-site IPsec VPN (with ExpressRoute/Direct Connect as the scale-up path)

**Chosen for this exercise: AWS Site-to-Site VPN ↔ Azure VPN Gateway
(IPsec/IKEv2).**

| Option | Setup time | Cost | Throughput/SLA | Verdict |
|---|---|---|---|---|
| **Site-to-site IPsec VPN** (AWS VPN Gateway ↔ Azure VPN Gateway) | Hours (fully self-service, no carrier involved) | Low (~$0.05/hr per Azure VPN Gateway + AWS VPN Gateway hourly + data processing; no monthly circuit fee) | Up to ~1.25 Gbps per tunnel (Azure VpnGw2), best-effort over the public internet backbone, no end-to-end SLA on latency | **Best fit here**: this is a single backend API + single DB, traffic volume is modest, and there's no indication of a strict low-latency SLA. Fast to stand up, fully IaC-able, no procurement lead time. |
| **ExpressRoute (Azure) + Direct Connect (AWS) via a colo/Megaport partner** | Weeks (carrier provisioning, cross-connects, sometimes a physical site visit) | High (monthly circuit + port fees on both sides, plus the interconnect partner's fee) | Guaranteed bandwidth, low/predictable latency, formal SLA from both clouds | The right call **at enterprise scale**: many services, high sustained throughput, or a contractual latency/uptime SLA (e.g. financial transactions, real-time inventory). Also worth it once VPN tunnel bandwidth becomes a bottleneck. |
| VNet/VPC peering | N/A | N/A | N/A | **Not applicable** — native peering (VNet peering, VPC peering) only works within a single cloud. AWS↔Azure requires either VPN or a carrier interconnect (ExpressRoute+Direct Connect, or a multi-cloud network provider like Megaport/Equinix). |
| AWS/Azure "Private Link" style service | N/A | N/A | N/A | Private Link / Private Endpoint is used *within* each cloud in this design (e.g. the Postgres private endpoint) but does not itself provide cross-cloud connectivity — it still needs a network path (the VPN) to be reachable from the other cloud. |

**Recommendation for production at scale:** start with the VPN (cheap, fast,
fully declarative in Terraform), and set an explicit trigger to migrate to
ExpressRoute + Direct Connect — e.g. "if the tunnel's utilization or backend
API p99 latency crosses a defined threshold for N consecutive days" or "if
the business signs an SLA that requires guaranteed bandwidth." Document that
trigger rather than over-building for a load that may never materialize —
this is the "reasonable defaults over over-engineering" principle applied to
networking.

For **redundancy**, even in the VPN design, provision **two tunnels** (AWS
supports two by default; pair with two Azure VPN Gateway public IPs in
active-active mode) so a single tunnel failure doesn't cause an outage.

## 4. Network topology

### AWS side — VPC `10.0.0.0/16` (region: e.g. `us-east-1`)

| Subnet | CIDR | Purpose |
|---|---|---|
| Public subnet(s) | `10.0.0.0/24` (+ a second AZ: `10.0.1.0/24`) | ALB/ingress controller, NAT Gateway. Only tier with public IPs. |
| Private subnet(s) — EKS nodes | `10.0.10.0/23` (+ `10.0.12.0/23` for a second AZ) | EKS worker nodes and pods (via VPC CNI). No public IPs; egress via NAT Gateway. |
| VPN attachment | uses the VPC's main route table + a Virtual Private Gateway (or Transit Gateway if there are multiple VPCs) | Terminates the IPsec tunnels to Azure. |

### Azure side — VNet `10.1.0.0/16` (region: e.g. West Europe)

| Subnet | CIDR | Purpose |
|---|---|---|
| `GatewaySubnet` | `10.1.0.0/27` | Required, fixed name, hosts the Azure VPN Gateway. |
| AKS subnet | `10.1.10.0/23` | AKS nodes (private cluster). No public IPs. |
| Database subnet | `10.1.20.0/26` | Delegated subnet for Postgres Flexible Server VNet integration, or a subnet hosting the DB's Private Endpoint if using the Private Link model instead of subnet delegation. |

CIDR ranges are chosen to be **non-overlapping** (`10.0.0.0/16` vs
`10.1.0.0/16`) since overlapping ranges are the single most common reason
cross-cloud/cross-VPC routing breaks — this must be planned before either
network is built, because it's expensive to renumber later.

## 5. DNS flow

- **Azure Private DNS Zone** (`privatelink.postgres.database.azure.com` or
  the Flexible Server VNet-integration equivalent) resolves the Postgres
  FQDN to its private IP inside the AKS VNet. AKS pods use this zone
  automatically since it's linked to the VNet.
- **AKS backend service name** (e.g. `backend-api.internal.contoso.com`) is
  published in an **Azure Private DNS Zone** linked to the Azure VNet.
- For **EKS to resolve that Azure-side private name**, use one of:
  - **Azure DNS Private Resolver** exposing an inbound endpoint reachable
    over the VPN tunnel, with a **conditional forwarder** configured in
    Route 53 Resolver (AWS side) for the `internal.contoso.com` zone
    pointing at the Azure DNS Private Resolver's inbound IP; or
  - Skip cross-cloud DNS entirely and give the frontend a **static
    private IP / internal FQDN** for the backend's internal load balancer,
    configured directly (simpler, but loses the flexibility of DNS-based
    failover — acceptable for this exercise's scale, called out here as a
    conscious simplification).
- Recommendation for this exercise: **Azure DNS Private Resolver +
  Route 53 Resolver conditional forwarding**, since it's the standard,
  supported pattern and keeps DNS authoritative on each side without manual
  IP pinning.

## 6. Traffic flow (end to end)

1. **End user → Frontend**: HTTPS request hits the AWS ALB / ingress
   controller in the public subnet. TLS terminates there (cert via AWS
   Certificate Manager).
2. **Frontend pod (EKS) → Backend API call**: the frontend pod, running in
   the private EKS subnet, calls the backend's internal DNS name (resolved
   per §5). The packet is routed out of the VPC via the VPN attachment.
3. **Cross-cloud hop**: traffic traverses the **IPsec tunnel** between the
   AWS Virtual Private Gateway and the Azure VPN Gateway — encrypted
   end-to-end, never touching either cloud's public-facing services.
4. **Azure VPN Gateway → AKS internal ingress**: the packet arrives in the
   Azure VNet and is routed to the AKS subnet, hitting the backend's
   **internal** load balancer / ingress (no public IP).
5. **AKS pod → PostgreSQL**: the backend pod connects to the DB over its
   **Private Endpoint / VNet-integrated private IP**, on port 5432, entirely
   within the Azure VNet — this hop never uses the VPN at all since both
   ends are in the same VNet.

See the dashed line in [`network-diagram.svg`](network-diagram.svg) for the
cross-cloud VPN hop, and the solid arrows for the intra-cloud hops.

## 7. Security controls

- **AWS Security Groups**: ALB SG allows `443` from `0.0.0.0/0` only; EKS
  node SG allows inbound only from the ALB SG and from the Azure VNet CIDR
  (via the VPN) — nothing else.
- **AWS NACLs**: subnet-level deny-by-default backstop behind the security
  groups (defense in depth in case a security group is misconfigured).
- **Azure NSGs**: on the AKS subnet, allow inbound only from the VPN
  gateway's CIDR + intra-VNet; on the DB subnet, allow inbound only from the
  AKS subnet on port 5432.
- **Kubernetes NetworkPolicies** (both clusters): default-deny, then
  explicit allow rules — e.g. in AKS, only pods labeled `app=backend-api`
  may reach the DB service/port; in EKS, only the frontend's own pods may
  egress to the backend's internal name.
- **Private Endpoint for PostgreSQL**, public network access **disabled** —
  this is the single most important control for the data tier: even a
  misconfigured firewall rule can't expose the DB publicly because there is
  no public endpoint to expose.
- **mTLS between frontend and backend** — not implemented in this design,
  flagged as a **future enhancement**: either terminate mTLS at each
  cluster's ingress (cert-manager + a shared internal CA) or adopt a service
  mesh (e.g. Istio/Linkerd) with automatic mTLS between meshed services if
  the environment grows past a couple of services. For two services and a
  private network path, this is reasonably deprioritized for now but should
  be revisited before handling regulated data.
- **Secrets management**: database credentials and API keys are stored in
  **Azure Key Vault** (mounted into AKS via the Secrets Store CSI driver)
  and **AWS Secrets Manager** (mounted into EKS via the same CSI driver's
  AWS provider) — never as plaintext Kubernetes Secrets or environment
  variables baked into images or manifests.

## 8. Explicit assumptions

- Traffic volume is "typical enterprise service," not high-frequency
  trading-grade — this is what justifies the VPN-first recommendation over
  ExpressRoute/Direct Connect from day one.
- Both clusters are single-region for this design; multi-region DR is out
  of scope but would mean a second VPN tunnel pair (or ExpressRoute circuit)
  per region and multi-region DNS failover, noted as future work.
- The frontend calls the backend over HTTP(S) request/response, not a
  persistent streaming protocol that would need different connectivity
  characteristics (e.g. gRPC streams still work fine over the same VPN
  tunnel, just called out as an assumption).
