# j5-eks-microservices — GCP reference implementation

Hand-built, known-good migration target for `user-journey-tests/aws/j5-eks-microservices` (the equipment marketplace, fictional: two microservices on EKS). Agents under test must NOT be shown this directory.

## AWS → GCP mapping

| AWS (journey) | GCP (this reference) | Notes |
|---|---|---|
| EKS cluster `ems-cluster` (1.35, 2×t3.medium) | GKE **Autopilot** regional `ems-cluster` | no node management; pods billed by request |
| ECR `ems-catalog-api` / `ems-booking-api` | Artifact Registry repo `ems` | same image names/tags |
| k8s manifests (`k8s/`) | **same manifests**, rendered by `k8s-overlay/render.py` | only images, pod-identity annotation, and two env vars change |
| IRSA (`eks.amazonaws.com/role-arn` on KSA) | Workload Identity (`iam.gke.io/gcp-service-account` → `ems-booking-gsa`) | the classic hard translation; wiring in `deploy/04` |
| DynamoDB `ems-bookings` | Firestore Native, **named DB `ems-bookings`** | funnel swap only; `server.mjs` byte-identical |
| Service type=LoadBalancer (NLB annotation) | Service type=LoadBalancer (passthrough NLB) | AWS-specific annotation dropped at render |
| catalog-api (Go, stdlib) | unchanged image | zero cloud SDK calls — ships verbatim |

## Deploy

```bash
cd deploy
./00-vars.sh && ./01-cluster.sh      # ~10-15 min (Autopilot regional)
./02-artifact-registry.sh && ./03-firestore.sh && ./04-workload-identity.sh
./05-build-push.sh                   # docker build+push both images
./06-kubectl-apply.sh && ./07-wait-lb.sh   # prints BASE_URL
```

## Parity check

```bash
../../../../user-journey-tests/aws/j5-eks-microservices/scripts/smoke-test.sh "$BASE_URL"
```

Unmodified journey smoke test: health, catalog via gateway, booking round-trip, `/admin/aws-check` (whose `sts` check proves Workload Identity the way it proved IRSA).

## Teardown

```bash
./deploy/99-teardown.sh   # gated; FORCE_TEARDOWN=1 to skip prompt
```
