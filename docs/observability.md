# Observability & SRE Design (Section 4)

Context: the Section 3 application (AWS EKS frontend + AKS backend + Azure
PostgreSQL) currently has no observability, and reports occasional latency
spikes and intermittent failures. This document defines the observability
stack, metrics, dashboards, logging, and alerting needed to see and diagnose
those problems.

## 1. Tool choice: Prometheus + Grafana + Loki + Tempo

**Recommendation: a self-hosted, cloud-agnostic stack** — `kube-prometheus-stack`
(Prometheus + Alertmanager + Grafana) on **both** clusters, **Loki** for
logs, **Tempo** for traces, all remote-written / federated into one central
Grafana. **Grafana Cloud** (managed Prometheus/Loki/Tempo) is a reasonable
swap-in if the team doesn't want to operate the storage backends themselves
— same query language and dashboards, less operational burden, ongoing SaaS
cost instead.

**Why not a single-cloud-native tool (Azure Monitor / CloudWatch alone):**
the estate is split across AWS and Azure by design. A single-cloud-native
tool would give first-class visibility into *its own* cluster and
second-class (or no) visibility into the other one, forcing two separate
tools and two separate dashboards/alerting systems to reason about one
logical application. Prometheus/Grafana/Loki/Tempo run identically on EKS
and AKS, so metrics, logs, and traces from both sides land in the same
query language, the same dashboards, and the same alert rules — which is
what actually lets an on-call engineer reason about a request that crosses
both clouds.

**Why not Datadog/New Relic here specifically:** both are perfectly valid
choices and arguably *less* operational burden than self-hosting Prometheus
— it's a legitimate alternative. It's called out as "optionally SaaS" above
rather than the primary pick mainly because Prometheus/Grafana is free,
open, and avoids vendor lock-in for a take-home exercise; in a real
procurement decision this would come down to team size, existing contracts,
and whether anyone wants to operate Prometheus storage long-term.

### Implementation sketch

- Install `kube-prometheus-stack` via Helm on both EKS and AKS.
- Each cluster's Prometheus **remote-writes** to a central long-term-storage
  backend (e.g. Grafana Mimir, or Grafana Cloud's managed Prometheus) so
  queries spanning both clusters work from one Grafana instance.
- Deploy the **OpenTelemetry Collector** as a DaemonSet on both clusters to
  collect traces and forward to Tempo, and to normalize logs before Loki
  ingestion (also lets us swap vendors later without re-instrumenting apps).
- Application code is instrumented with the **OpenTelemetry SDK** (metrics +
  traces), emitting the RED metrics below and a trace per request carrying
  the correlation ID (§4).

## 2. Metrics: RED (app) + USE (infra)

**RED — per service/endpoint, from the application:**

| Metric | Example PromQL |
|---|---|
| **R**ate | `sum(rate(http_requests_total{service="backend-api"}[5m])) by (route)` |
| **E**rrors | `sum(rate(http_requests_total{service="backend-api", status=~"5.."}[5m])) by (route) / sum(rate(http_requests_total{service="backend-api"}[5m])) by (route)` |
| **D**uration (latency) | `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="backend-api"}[5m])) by (le, route))` |

**USE — per node/pod, from infrastructure:**

| Metric | Example PromQL |
|---|---|
| **U**tilization (CPU) | `sum(rate(container_cpu_usage_seconds_total{namespace="backend"}[5m])) by (pod) / sum(kube_pod_container_resource_limits{resource="cpu", namespace="backend"}) by (pod)` |
| **U**tilization (memory) | `sum(container_memory_working_set_bytes{namespace="backend"}) by (pod) / sum(kube_pod_container_resource_limits{resource="memory", namespace="backend"}) by (pod)` |
| **S**aturation (node CPU pressure) | `node_load1 / count(count(node_cpu_seconds_total) by (cpu)) by (instance)` |
| **S**aturation (pod pending/throttled) | `sum(kube_pod_status_phase{phase="Pending"}) by (namespace)` and `sum(rate(container_cpu_cfs_throttled_periods_total[5m])) by (pod)` |
| **E**rrors (infra) | `sum(rate(kube_pod_container_status_restarts_total[15m])) by (pod)` and node `NodeNotReady` conditions |

These map directly onto the reported symptoms: **latency spikes** show up
first in the RED "Duration" panel (p99) and are correlated against the USE
"Saturation" panels (CPU throttling, node pressure) to distinguish "app is
just slow" from "app is resource-starved." **Intermittent failures** show up
in the RED "Errors" panel and are correlated against pod restarts / node
readiness in the USE panels.

## 3. Dashboards

### a) Executive Service Health (audience: management/product)

- Overall **uptime %** (SLO: e.g. 99.9% over rolling 30 days) as a single
  big-number panel with a trend line.
- **SLO error-budget burn** (%, gauge) — how fast the error budget is being
  consumed this window.
- Business KPI panel(s), kept generic since the app itself is generic in
  this exercise — e.g. "successful requests/day" or "checkout success rate"
  as a stand-in for whatever the real business metric is.
- Weekly incident count / MTTR trend.
- Deliberately **no PromQL jargon or per-pod detail** on this dashboard —
  it's a KPI view, not a debugging tool.

### b) Application Observability (audience: engineers, feature debugging)

- RED metrics **per endpoint/route**: request rate, error rate, p50/p95/p99
  latency, each as a time series with the ability to filter by route.
- **Dependency latency**: time spent calling PostgreSQL, broken out from
  total request latency (traces from Tempo, or a
  `db_query_duration_seconds` histogram) — this is the panel that answers
  "is the DB the bottleneck?"
- **Error breakdown by type**: 4xx vs 5xx, and 5xx broken down by exception
  class/error code if the app emits one.
- A **trace search** panel (Tempo, queryable by `correlation_id` or
  `trace_id`) to jump from a spike in the rate graph straight into example
  slow/failed requests.

### c) Infrastructure Observability (audience: platform/SRE)

- Node & pod **CPU/memory utilization and saturation**, per cluster
  (EKS and AKS side by side).
- **Kubernetes events** (OOMKilled, CrashLoopBackOff, FailedScheduling,
  NodeNotReady) as an annotated log panel.
- **Network errors / VPN tunnel health**: since the two clusters talk over
  the Section 3 VPN, a panel tracking tunnel status and cross-cloud request
  latency specifically (isolates "network hop is slow" from "app is slow").
- **Cluster capacity**: pods pending due to resource pressure, HPA scaling
  events, node count vs. max.

## 4. Logging

- **Structured JSON logs** from every service. Required fields:
  - `timestamp` (RFC3339/UTC)
  - `level` (`debug`/`info`/`warn`/`error`)
  - `service` (e.g. `frontend`, `backend-api`)
  - `correlation_id` (see below)
  - `trace_id` / `span_id` (if tracing is active, links log lines directly to a trace)
  - `message`
- **Correlation ID propagation**: generated at the frontend/ingress edge if
  not already present on the inbound request (header `X-Correlation-Id`),
  and propagated on every downstream call. If/when distributed tracing is
  fully adopted, the W3C `traceparent` header supersedes this for
  span-level correlation, but `X-Correlation-Id` is kept as a simpler,
  human-greppable identifier that also shows up in log lines and support
  tickets.
- **Centralization**: both clusters ship logs to **Loki** via the
  OpenTelemetry Collector / Promtail, queryable from the same Grafana as
  metrics and traces (correlate a log line, a metric spike, and a trace in
  one pane).
- **Retention**: 14 days "hot" (fast query, used for active
  debugging/on-call) and 90 days "cold"/archive (cheaper storage, used for
  audits or post-incident deep dives) — stated here as a reasonable default
  assumption; real retention should be driven by the org's actual
  compliance/audit requirements, which weren't specified in the brief.

## 5. Alerts

Three alerts are defined below (availability, latency, error rate), each as
real Prometheus/Alertmanager rule syntax in [`alerts.yaml`](alerts.yaml).

| Alert | Condition | Severity | Routing |
|---|---|---|---|
| **Availability / SLO burn-rate** | Fast burn: consuming the 30-day 99.9% error budget at a rate that would exhaust it in <2 days (a standard multi-window burn-rate check: high burn over 5m **and** 1h simultaneously, per Google's SRE workbook pattern) | Critical (page) | PagerDuty / on-call phone page + Slack `#incidents` |
| **Latency (p99)** | `p99 request duration > 1s` for the `backend-api` service, sustained 10 minutes | Warning → escalates to Critical if sustained 30 minutes | Slack `#platform-alerts`; escalation pages on-call |
| **Error rate** | 5xx rate > 5% of total requests over a 5-minute window | Critical (page) | PagerDuty page + Slack `#incidents` |

Burn-rate alerting is preferred over a flat threshold for availability
specifically because it distinguishes "a brief blip that won't threaten the
monthly SLO" from "a sustained problem that will burn the whole error budget
by end of day" — a flat `error_rate > X for 5m` alert either pages too often
on noise or misses slow-burning problems, whichever way it's tuned.

See [`alerts.yaml`](alerts.yaml) for the runnable rule definitions.

## 6. Explicit assumptions & limitations

- Concrete thresholds (1s p99, 5% error rate, 99.9% SLO) are reasonable
  defaults for a generic API, not measured baselines — in a real rollout
  these would be tuned against a few weeks of actual traffic data before
  being trusted for paging.
- This design assumes the app can be instrumented with OpenTelemetry
  (source access available); if a component is closed-box, black-box
  synthetic monitoring (e.g. a scheduled probe hitting `/health` and key
  endpoints from outside) would need to substitute for RED metrics on that
  component.
- Multi-cluster federation (remote_write to a central store) adds
  operational complexity; for a smaller team, starting with Grafana Cloud's
  managed ingestion instead of self-hosting Mimir/Loki/Tempo storage is a
  reasonable simplification, noted here as the pragmatic alternative.
