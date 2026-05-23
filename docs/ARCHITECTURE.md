# Architecture

## Overview

Three EC2 instances in a single-AZ AWS VPC run the Alchemyst quickstart mesh:

| Instance | Subnet | Software | Exposure |
|----------|--------|----------|----------|
| API gateway | Public | iii engine, iii-http, observability/state/queue workers | HTTP **3111** public; WebSocket **49134** from private subnet only |
| inference-worker | Private | Python worker (`inference::run_inference`) | No public IP |
| caller-worker | Private | TypeScript worker (`inference::get_response`, HTTP trigger registration) | No public IP |

## Network

- **VPC**: `10.0.0.0/16`
- **Public subnet**: `10.0.1.0/24` — Internet Gateway route, API gateway, NAT Gateway
- **Private subnet**: `10.0.2.0/24` — NAT route for outbound only (packages, Hugging Face model download)

## Request flow

```
Client
  │  POST http://<public-ip>:3111/v1/chat/completions
  ▼
iii-http (on API gateway)
  │  triggers http::run_inference_over_http
  ▼
caller-worker (private VM, III_URL → ws://<api-private-ip>:49134)
  │  inference::get_response → inference::run_inference
  ▼
inference-worker (private VM)
  │  gemma-3-270m inference
  ▼
JSON HTTP response
```

RPC is **not** direct HTTP between VMs. Workers connect to the shared **iii engine** over WebSocket (`ws://<api-gateway-private-ip>:49134`). The engine routes function calls.

## Security groups

**API gateway**

- Ingress: TCP 3111 from `0.0.0.0/0` (HTTP API)
- Ingress: TCP 49134 from private subnet CIDR (worker mesh)
- Ingress: TCP 22 from `var.ssh_cidr`
- Egress: all (bootstrap, updates)

**Workers**

- No ingress from the internet
- Egress: all (NAT for git, pip, npm, model weights)
- Optional SSH from API gateway security group

## Bootstrap

Terraform `templatefile()` injects the API gateway private IP into worker user-data. Scripts:

1. Install dependencies and clone this repository
2. API host: install iii CLI, start `iii-engine.service` with `deploy/engine-config.yaml`
3. Workers: wait for TCP 49134, set `III_URL`, start `inference-worker` / `caller-worker` systemd units

## Instance sizing

- API gateway / caller: `t3.small` (default)
- Inference: `t3.medium` (default) — model needs more RAM than 2 GiB

## State & observability

- iii state: file-based KV under `/opt/alchemyst/data/`
- Logs: `journalctl -u iii-engine|inference-worker|caller-worker`
- Debug access: SSH from the API host to workers (workers SG allows port 22 from API SG). Optional IAM/SSM can be added in accounts that allow `iam:CreateRole`.
