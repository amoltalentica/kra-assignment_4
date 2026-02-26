# Secure API Platform using Kong on Kubernetes

A self-managed, secure API platform built with Kong API Gateway (DB-less), Envoy Proxy for DDoS protection, and a FastAPI microservice — fully deployable on Kubernetes using Helm.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Helm Charts](#helm-charts)
- [API Documentation](#api-documentation)
- [Security Features](#security-features)
- [Testing](#testing)
- [Monitoring and Observability](#monitoring-and-observability)
- [Troubleshooting](#troubleshooting)

---

## 🏗️ Architecture Overview

### Request Flow

```
                         ┌──────────────────────────────────────┐
  External Traffic       │           Kubernetes Cluster          │
  (minikube :30082)      │           Namespace: api-platform     │
                         │                                       │
  ┌──────────┐           │  ┌─────────────────────────────────┐  │
  │  Client  │──────────►│  │   Envoy Proxy  (NodePort 30082) │  │
  └──────────┘           │  │   DDoS Protection               │  │
                         │  │   • Token bucket: 10 / 60s      │  │
                         │  │   • Circuit breaker             │  │
                         │  └────────────────┬────────────────┘  │
                         │                   │                    │
                         │                   ▼                    │
                         │  ┌─────────────────────────────────┐  │
                         │  │   Kong API Gateway (ClusterIP)  │  │
                         │  │   DB-less mode (kong.yml)       │  │
                         │  │   • JWT auth (on /users)        │  │
                         │  │   • Rate limiting (10 req/min)  │  │
                         │  │   • IP restriction (whitelist)  │  │
                         │  │   • Custom Lua header injector  │  │
                         │  └────────────────┬────────────────┘  │
                         │                   │                    │
                         │                   ▼                    │
                         │  ┌─────────────────────────────────┐  │
                         │  │   User Service (ClusterIP)      │  │
                         │  │   FastAPI · 2 replicas          │  │
                         │  │   GET  /health  GET  /verify    │  │
                         │  │   POST /login   GET  /users     │  │
                         │  │   SQLite PVC (1Gi)              │  │
                         │  └─────────────────────────────────┘  │
                         └──────────────────────────────────────┘
```

### JWT Authentication Flow

```
  Client        Envoy            Kong              User Service
    │              │               │                    │
    │  POST /login │               │                    │
    │─────────────►│               │                    │
    │              │───────────────►               │
    │              │               │  (no JWT plugin)   │
    │              │               │───────────────────►│
    │              │               │                    │ generate JWT
    │              │               │                    │ with iss claim
    │◄─────────────────────────────────────────────────│
    │  {access_token}              │                    │
    │              │               │                    │
    │  GET /users  │               │                    │
    │  Bearer token│               │                    │
    │─────────────►│ rate limit    │                    │
    │              │ (token bucket)│                    │
    │              │───────────────►                    │
    │              │               │ verify iss claim   │
    │              │               │ + rate limit       │
    │              │               │ + IP whitelist     │
    │              │               │───────────────────►│
    │◄─────────────────────────────────────────────────│
```

### Plugin Coverage per Route

| Route | JWT | Rate Limit | IP Restrict | Custom Lua |
|-------|-----|-----------|------------|------------|
| `GET /health` | ✗ | 10/min | ✗ | ✓ |
| `GET /verify` | ✗ | 10/min | ✗ | ✓ |
| `POST /login` | ✗ | 5/min | ✗ | ✓ |
| `GET /users` | ✓ | 10/min | ✓ | ✓ |
| `POST /users` | ✓ | 10/min | ✓ | ✓ |

---

## 🛠️ Technology Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| API Gateway | Kong OSS | 3.5 | Routing, JWT, rate limiting, IP restriction |
| DDoS Protection | Envoy Proxy | v1.28 | Token bucket rate limiter, circuit breaker |
| Microservice | Python FastAPI | 3.11 | REST API + JWT issuance |
| Database | SQLite | 3 | User storage (file-based, on PVC) |
| Orchestration | Kubernetes | 1.30+ | Container management |
| Package Manager | Helm | 3 | Declarative deployment |
| Container Runtime | Docker | 24+ | Image build |

---

## 📁 Repository Structure

```
.
├── microservice/                   # User service application
│   ├── app/
│   │   ├── main.py                 # FastAPI app (JWT issue + endpoints)
│   │   └── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── helm/                           # Helm charts (primary deployment method)
│   ├── user-service/               # Chart: FastAPI microservice
│   │   ├── Chart.yaml
│   │   ├── values.yaml             # replicaCount, image, jwt.secretKey, jwt.issKey
│   │   └── templates/
│   │       ├── configmap.yaml      # DATABASE_PATH, LOG_LEVEL, KONG_JWT_ISS_KEY
│   │       ├── deployment.yaml
│   │       ├── pvc.yaml            # 1Gi for SQLite
│   │       ├── secret.yaml         # JWT_SECRET_KEY
│   │       └── service.yaml
│   │
│   ├── kong/                       # Chart: Kong API Gateway (DB-less)
│   │   ├── Chart.yaml
│   │   ├── values.yaml             # JWT consumer, rate limit, IP whitelist
│   │   ├── plugins/
│   │   │   └── custom-token-validator.lua
│   │   └── templates/
│   │       ├── configmap.yaml      # Kong declarative config (services/routes/plugins)
│   │       ├── custom-plugin-configmap.yaml  # handler.lua + schema.lua
│   │       ├── deployment.yaml
│   │       └── service.yaml        # kong-proxy (ClusterIP) + kong-admin (ClusterIP)
│   │
│   └── envoy/                      # Chart: Envoy DDoS proxy
│       ├── Chart.yaml
│       ├── values.yaml             # rateLimiting, circuitBreaker, NodePort
│       └── templates/
│           ├── configmap.yaml      # Envoy static config (listener + cluster)
│           ├── deployment.yaml     # 2 replicas
│           └── service.yaml        # NodePort 30082 (http) + 30091 (admin)
│
├── kong/                           # Reference Kong declarative config
│   ├── kong.yaml                   # Full config: consumers, plugins, routes
│   └── plugins/
│       └── custom-token-validator.lua
│
├── k8s/                            # Raw Kubernetes manifests (fallback)
│   ├── deployment.yaml             # User service namespace + Deployment + PVC
│   ├── envoy-simple.yaml           # Envoy proxy (kubectl apply alternative)
│   └── kong-simple-v2.yaml        # Kong deployment (kubectl apply alternative)
│
├── scripts/
│   ├── deploy-all.sh               # Helm-based full deploy script
│   └── cleanup.sh                  # Teardown script
│
├── test-platform.sh                # Full integration test suite (8 sections)
├── test-user-service-direct.sh     # Lightweight direct tests
├── Makefile
└── ai-usage.md
```

---

## 📦 Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| minikube | 1.30+ | Local Kubernetes cluster |
| kubectl | 1.24+ | Cluster management |
| Helm | 3.10+ | Chart deployment |
| Docker | 20.10+ | Image build |

### Start minikube

```bash
minikube start --cpus=4 --memory=4096
```

---

## 🚀 Quick Start

### 1. Build the Docker image inside minikube

```bash
eval $(minikube docker-env)
docker build -t user-service:latest microservice/
```

### 2. Deploy all three Helm charts

```bash
./scripts/deploy-all.sh
```

This runs `helm upgrade --install` for all three charts in order:
1. **user-service** — FastAPI + SQLite PVC
2. **kong-gateway** — Kong DB-less + all plugins
3. **envoy-ddos** — Envoy DDoS proxy (NodePort 30082)

### 3. Verify deployment

```bash
helm list -n api-platform
kubectl get pods -n api-platform
```

Expected:
```
NAME           NAMESPACE     STATUS    CHART
envoy-ddos     api-platform  deployed  envoy-ddos-1.0.0
kong-gateway   api-platform  deployed  kong-gateway-1.0.0
user-service   api-platform  deployed  user-service-1.0.0

NAME                              READY   STATUS
envoy-ddos-xxxx                   1/1     Running   (×2)
kong-gateway-xxxx                 1/1     Running
user-service-xxxx                 1/1     Running   (×2)
```

### 4. Run integration tests

```bash
./test-platform.sh
```

### Manual deploy (individual charts)

```bash
NS=api-platform

helm upgrade --install user-service helm/user-service \
  --namespace $NS --create-namespace \
  --set image.pullPolicy=IfNotPresent --wait

helm upgrade --install kong-gateway helm/kong \
  --namespace $NS --wait

helm upgrade --install envoy-ddos helm/envoy \
  --namespace $NS --wait
```

---

## 🔧 Helm Charts

### user-service — key values

```yaml
# helm/user-service/values.yaml
replicaCount: 2
image:
  repository: user-service
  tag: "latest"
  pullPolicy: IfNotPresent

jwt:
  # MUST match helm/kong/values.yaml jwt.consumer.secret
  secretKey: "production-jwt-secret-change-this-randomly-generated-key-12345"
  # MUST match helm/kong/values.yaml jwt.consumer.key
  # Written as 'iss' claim in every issued JWT
  issKey: "kong-jwt-key"
```

### kong-gateway — key values

```yaml
# helm/kong/values.yaml
userService:
  host: "user-service.api-platform.svc.cluster.local"
  port: 80

jwt:
  consumer:
    username: api-consumer
    key: "kong-jwt-key"       # matches jwt.issKey in user-service chart
    secret: "production-jwt-secret-change-this-randomly-generated-key-12345"
  keyClaimName: iss           # Kong looks up consumer by 'iss' claim value

rateLimiting:
  enabled: true
  minute: 10
  policy: local

ipRestriction:
  whitelist:
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "127.0.0.1"
```

### envoy-ddos — key values

```yaml
# helm/envoy/values.yaml
replicaCount: 2

rateLimiting:
  maxTokens: 10
  tokensPerFill: 10
  fillInterval: "60s"

upstream:
  host: "kong-proxy.api-platform.svc.cluster.local"

service:
  type: NodePort
  httpNodePort: 30082    # external traffic entrypoint
  adminNodePort: 30091   # Envoy admin/stats
```

---

## 📚 API Documentation

### Base URL

All external traffic enters through Envoy on NodePort 30082:

```bash
BASE_URL="http://$(minikube ip):30082"
```

> API calls must be made from inside the minikube network (e.g. `minikube ssh`), or via port-forward if testing from the host.

### Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | None | Health check |
| `/verify` | GET | None | Public token verification endpoint |
| `/login` | POST | None | Authenticate, returns JWT |
| `/users` | GET | JWT | List all users |
| `/users` | POST | JWT | Create a user |

### Examples

#### Health check
```bash
minikube ssh "curl -s http://$(minikube ip):30082/health"
```
```json
{"status": "healthy", "service": "user-service"}
```

#### Login — get JWT token
```bash
minikube ssh "curl -s -X POST http://$(minikube ip):30082/login \
  -H 'Content-Type: application/json' \
  -d '{\"username\":\"testuser\",\"password\":\"testpassword\"}'"
```
```json
{"access_token": "eyJhbGci...", "token_type": "bearer"}
```

Default seed credentials: `testuser` / `testpassword`

#### Get users (JWT required)
```bash
TOKEN=$(minikube ssh "curl -s -X POST http://$(minikube ip):30082/login \
  -H 'Content-Type: application/json' \
  -d '{\"username\":\"testuser\",\"password\":\"testpassword\"}'" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

minikube ssh "curl -s http://$(minikube ip):30082/users \
  -H 'Authorization: Bearer $TOKEN'"
```

#### Create user
```bash
minikube ssh "curl -s -X POST http://$(minikube ip):30082/users \
  -H 'Authorization: Bearer $TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{\"username\":\"alice\",\"email\":\"alice@example.com\",\"password\":\"pass1234\"}'"
```

---

## 🔒 Security Features

### 1. JWT Authentication (Kong JWT Plugin)

- **Algorithm**: HS256
- **Token fields**: `sub`, `email`, `iss`, `exp`, `iat`
- **`iss` claim**: set to the Kong consumer key (`kong-jwt-key`) — Kong uses `key_claim_name: iss` to look up the consumer and verify the secret
- **Token expiry**: 30 minutes
- **Applied to**: `/users` route only — `/health`, `/verify`, and `/login` are public

The `jwt.consumer.secret` in `helm/kong/values.yaml` must match `jwt.secretKey` in `helm/user-service/values.yaml`. The `jwt.consumer.key` must match `jwt.issKey` (written as the `iss` claim).

### 2. Kong Rate Limiting

| Route | Limit | Policy |
|-------|-------|--------|
| `/health`, `/verify`, `/users` | 10 req/min | local (per Kong pod) |
| `/login` | 5 req/min | local |

- **Error**: HTTP 429 Too Many Requests
- Kong adds `X-RateLimit-Limit-Minute` and `X-RateLimit-Remaining-Minute` headers

### 3. IP Whitelisting (Kong `ip-restriction` Plugin)

Applied to `/users` only. Permitted CIDRs:
- `10.0.0.0/8` (pod network)
- `172.16.0.0/12`
- `192.168.0.0/16` (minikube network)
- `127.0.0.1`

### 4. Envoy DDoS Protection

Envoy is the **only external entrypoint** — Kong has no NodePort and is not reachable from outside the cluster.

**Token Bucket Rate Limiter:**
- 10 tokens, refilled every 60 seconds
- Each request consumes 1 token; beyond 10 → HTTP 429
- 2 replicas, each with an independent bucket

**Circuit Breaker (upstream cluster):**
```yaml
max_connections: 10
max_pending_requests: 1000
max_requests: 1000
max_retries: 3
```

Layer separation:
```
Internet → Envoy (network-level DDoS/rate-limit)
               → Kong (app-level JWT / rate-limit / IP restrict)
                   → User Service
```

### 5. Custom Lua Plugin (`custom-token-validator`)

Deployed as a Kong custom plugin via ConfigMap, loaded from `/opt/kong/plugins/custom-token-validator/`.

**Upstream headers added (to User Service):**

| Header | Value |
|--------|-------|
| `X-Kong-Gateway` | `secure-api-platform` |
| `X-Gateway-Version` | `1.0.0` |
| `X-Request-Timestamp` | Unix timestamp |
| `X-Client-IP` | Real client IP |
| `X-RateLimit-Policy` | `10-per-minute` |
| `X-Forwarded-By` | `kong-gateway` |

**Response headers added (to Client):**

| Header | Value |
|--------|-------|
| `X-Kong-Gateway` | `secure-api-platform` |
| `X-API-Platform-Version` | `1.0.0` |
| `X-Powered-By` | `Kong-OSS-3.5` |
| `X-Validation-Timestamp` | Unix timestamp |

Applied on all routes.

---

## 🧪 Testing

### Run full test suite

```bash
./test-platform.sh
```

| Section | What it tests | Pass condition |
|---------|---------------|----------------|
| 0 | Pre-flight: 5 pods running | ≥5 Running |
| 1 | `/health`, `/verify`, Lua response headers | HTTP 200 + headers present |
| 2 | JWT login returns token with `iss` claim; wrong creds → 401 | token + 401 |
| 3 | `/users` with valid JWT, no JWT, fake JWT | 200 / 401 / 401 |
| 4 | `POST /users` create user (JWT protected) | HTTP 201 |
| 5 | Kong rate limiting — 12 rapid `/login` → 429 | ≥1 × 429 |
| 6 | **DDoS** — 25 burst requests → Envoy 429 | ≥1 × 429 |
| 7 | Envoy admin stats — `http_local_rate_limit` counter | counter present |

### Manual rate limit test

```bash
# Kong: 5/min on /login
for i in $(seq 1 8); do
  minikube ssh "curl -s -o /dev/null -w 'req $i: %{http_code}\n' \
    -X POST http://$(minikube ip):30082/login \
    -H 'Content-Type: application/json' \
    -d '{\"username\":\"testuser\",\"password\":\"testpassword\"}'"
done
```

### Manual DDoS test

```bash
# Envoy token bucket: 10/60s — burst 20 requests
for i in $(seq 1 20); do
  minikube ssh "curl -s -o /dev/null -w '%{http_code} ' http://$(minikube ip):30082/health"
done && echo
# Expected: 200 200 ... 200 429 429 ... 429
```

---

## 📊 Monitoring and Observability

### Envoy Admin (NodePort 30091)

```bash
ADMIN="http://$(minikube ip):30091"

# Rate limit counters
minikube ssh "curl -s $ADMIN/stats" | grep local_rate_limit

# Cluster connectivity
minikube ssh "curl -s $ADMIN/clusters"

# Circuit breaker stats
minikube ssh "curl -s $ADMIN/stats" | grep circuit_breakers
```

Key counters:
```
http_local_rate_limiter.http_local_rate_limit.enabled   → total requests
http_local_rate_limiter.http_local_rate_limit.ok        → allowed
http_local_rate_limiter.http_local_rate_limit.enforced  → blocked (429)
```

### Kong Admin (ClusterIP — port-forward required)

```bash
kubectl port-forward -n api-platform svc/kong-admin 8001:8001 &

curl http://localhost:8001/services
curl http://localhost:8001/routes
curl http://localhost:8001/plugins
curl http://localhost:8001/consumers
```

### Application logs

```bash
kubectl logs -n api-platform -l app.kubernetes.io/name=kong-gateway -f
kubectl logs -n api-platform -l app.kubernetes.io/name=user-service -f
kubectl logs -n api-platform -l app.kubernetes.io/name=envoy-ddos -f
```

---

## 🐛 Troubleshooting

### Kong pod CrashLoopBackOff

```bash
kubectl logs -n api-platform -l app.kubernetes.io/name=kong-gateway
```

- **Lua syntax error** — check `helm/kong/plugins/custom-token-validator.lua` ends with `return plugin` with no code after it
- **Invalid declarative config** — `helm template helm/kong/ | kubectl apply --dry-run=client -f -`

### JWT returns 401 "No mandatory 'iss' in claims"

The user-service image predates the `iss` claim fix. Rebuild:

```bash
eval $(minikube docker-env)
docker build -t user-service:latest microservice/
kubectl rollout restart deployment/user-service -n api-platform
```

### DDoS test shows no 429

The Envoy token bucket is per-replica and per-restart. Wait 60 seconds for the bucket to fill, then burst again. Check current state:

```bash
minikube ssh "curl -s http://$(minikube ip):30091/stats" | grep local_rate_limit
```

### Cleanup and full redeploy

```bash
helm uninstall envoy-ddos kong-gateway user-service -n api-platform
kubectl delete namespace api-platform
./scripts/deploy-all.sh
```

---

## 📄 License

Created as an educational project demonstrating secure API gateway patterns on Kubernetes.
