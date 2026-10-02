# j2-three-tier-web — GCP reference (known-good migration target)

Hand-made GCP port of [`user-journey-tests/aws/j2-three-tier-web/`](../../../../user-journey-tests/aws/j2-three-tier-web/) (the online shop, `ttw-`). This is the answer key the harness compares agent migrations against — **never referenced from inside the journey directory**.

Project `aws-migration-501814` (override with `GCP_PROJECT`), region `asia-northeast1`, zone `asia-northeast1-b`. Every gcloud invocation passes `--project` explicitly.

## AWS → GCP mapping

| AWS (journey)                                             | GCP (this reference)                                                       |
| ---------------------------------------------------------- | --------------------------------------------------------------------------- |
| CloudFront `ttw-cdn` (cache `/static/*` only)               | Cloud CDN on the backend service (`CACHE_ALL_STATIC`)                        |
| ALB `ttw-alb` + target group `ttw-app-tg` (:8000, `/health`) | Global external Application LB: `ttw-fwd` :80 → `ttw-http-proxy` → `ttw-url-map` → `ttw-backend`, health check `ttw-hc` |
| EC2 ASG `ttw-asg` (2x t3.micro AL2023, UserData bootstrap)   | MIG `ttw-mig` (2x e2-micro Debian 12, `startup-script.sh` bootstrap) from template `ttw-app-tmpl` |
| RDS PostgreSQL 16.14 `ttw-postgres` (db.t3.micro)            | Cloud SQL `ttw-postgres` POSTGRES_16, `db-g1-small` (verified 2026-07), reached via Cloud SQL Auth Proxy v2 sidecar on 127.0.0.1:5432 |
| S3 `ttw-assets-<account>` (bundle + covers)                  | GCS `ttw-assets-<project>` (same layout: `app/app.tar.gz`, `covers/*.png`)   |
| Secrets Manager `ttw-db-password`, `ttw-legacy-api-key`      | Secret Manager, same names, same JSON payload shapes (incl. the untouched placeholder in the legacy key) |
| CloudWatch metric `OnlineShop/HealthPing`                   | Cloud Monitoring `custom.googleapis.com/online_shop/health_ping`            |
| IAM instance role `ttw-app-role`                             | Service account `ttw-app-sa` (objectViewer on the bucket, secretAccessor+viewer on the two secrets, metricWriter, cloudsql.client) |
| Security groups `ttw-alb-sg` / `ttw-app-sg` / `ttw-db-sg`    | Firewall rules `ttw-allow-health` + `ttw-allow-lb` (GFE ranges → tag `ttw-app` :8000); Cloud SQL has no open ingress — proxy only |
| STS `get_caller_identity` (on `/admin/aws-check`)            | Metadata-server service-account identity                                    |
| CloudWatch alarms `ttw-alb-5xx`, `ttw-unhealthy-hosts`       | Not scripted (smoke test does not assert alarms); the equivalents would be two Cloud Monitoring alert policies on LB 5xx and backend healthy-host count |
| Log group `/ttw/app` (empty — unfinished agent rollout)      | Faithfully reproduced by doing nothing: app logs stay in journald on the VMs |

## App overlay

`app-overlay/` holds ONLY the files that differ from the journey app; `build.sh` copies the journey `app/` and drops these on top:

| File               | Why it differs                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| `gcp_clients.py`   | The GCP funnel — same public surface as `aws_clients.py` (storage, secretmanager, monitoring, identity) |
| `aws_clients.py`   | Becomes a 1-line compatibility shim (`from gcp_clients import *`) so `app.py` runs with **zero** diffs |
| `db.py`            | `DB_HOST` defaults to `127.0.0.1` — the Cloud SQL Auth Proxy sidecar replaces the injected RDS endpoint |
| `requirements.txt` | `boto3` → `google-cloud-storage` / `-secret-manager` / `-monitoring`                                  |

`app.py`, `schema.sql`, templates, and the stylesheet ship byte-identical, and the catalog seed is the same 12 deterministic books.

## Deploy order

```bash
cd user-journey-tests/gcp-references/aws/j2-three-tier-web/deploy
./01-enable-apis.sh        # compute, sqladmin, secretmanager, storage, monitoring, iam, crm
./02-service-account.sh    # ttw-app-sa + project roles (metricWriter, cloudsql.client)
./03-secrets.sh            # both secrets; DB password generated straight into a version
./04-sql.sh                # Cloud SQL instance (~10-15 min) + online_shop + shop user
./05-bucket.sh             # gs://ttw-assets-<project> + objectViewer grant
./06-bundle.sh             # build.sh (journey app + overlay) -> upload bundle + covers
./07-firewall.sh           # ttw-allow-health + ttw-allow-lb (GFE ranges -> :8000)
./08-mig.sh                # template + 2-instance MIG, waits for stable
./09-lb.sh                 # IP, health check, CDN-enabled backend, url-map, proxy, :80 rule
```

Every step is idempotent (describe-or-create); re-running the sequence is safe. `08` is the one with a wrinkle: instance templates are immutable, so if `startup-script.sh` changes, delete `ttw-app-tmpl` first. After re-uploading a bundle (`06`), roll the fleet:

```bash
gcloud compute instance-groups managed rolling-action replace ttw-mig \
  --zone asia-northeast1-b --project aws-migration-501814
```

`09-lb.sh` prints `BASE_URL=http://<LB-IP>`. Fresh global LBs need a few minutes before they stop returning 404/502 from the GFE.

## Parity verification

The journey's smoke test must pass **unmodified** against the LB endpoint:

```bash
../../../../user-journey-tests/aws/j2-three-tier-web/scripts/smoke-test.sh http://<LB-IP>
```

All five checks map cleanly: `/health` (DB via proxy + bucket listing), `/books` (same 12 seeded titles), `/books/1`, `/covers/1.png` (streamed from GCS, byte-identical deterministic PNGs), and `/admin/aws-check` — whose six keys (`s3`, `secret_db`, `secret_legacy`, `database`, `cloudwatch`, `sts`) keep their AWS names on purpose: the dashboard is the parity contract, and on GCP each key is served by the mapped service.

## Teardown

```bash
./deploy/99-teardown.sh    # type "yes", or FORCE_TEARDOWN=1; reverse order, skip-if-absent
```
