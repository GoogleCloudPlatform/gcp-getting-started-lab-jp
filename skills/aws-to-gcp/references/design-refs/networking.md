# Networking Services Design Rubric

**Applies to:** VPC, Security Groups, ALB/NLB, Route 53, CloudFront, AWS WAF, Direct Connect

**Quick lookup (no rubric):** Check `fast-path.md` first (VPC -> VPC Network, Security Group -> Firewall Rule, etc.)

## Companion skill (google/skills)

Before applying this rubric or shaping the GCP-side configuration:

- **VPC, subnets, Cloud Load Balancing, Cloud DNS, Cloud NAT, Cloud Interconnect, Cloud CDN, observability wiring:** read the latest version of **`google-cloud-networking-observability`** at `~/.claude/skills/google-cloud-networking-observability/SKILL.md` (fallback `~/.agents/skills/google-cloud-networking-observability/SKILL.md`). Use its canonical patterns for global VPC layout, regional subnets, load-balancing scheme selection (L4 vs L7, internal vs external, global vs regional), Cloud DNS zones, and the Cloud Monitoring + Cloud Logging integration that lights up observability for those resources.
- **AWS WAF -> Cloud Armor:** read the latest version of **`google-cloud-waf-security`** at the same paths. Use its security-policy templates (rate limiting, IP allow/deny, preconfigured WAF rules, bot management) as the source of truth for Cloud Armor configuration. _(Note: `google-cloud-waf-security` is the GCP **Well-Architected Framework** security pillar; it covers Cloud Armor among other security controls, despite the "waf" prefix.)_
- **IAM service accounts (when migrating `aws_iam_role`):** consult **`google-cloud-recipe-auth`** if installed for canonical service-account / Workload Identity Federation guidance.

This rubric is the AWS -> GCP **decision** layer for these resources. The google/skill is the **how** layer for the chosen GCP target. If a companion skill is not installed, fall back to this file and add a `warnings[]` entry per the protocol in `references/shared/companion-skills.md`.

## CRITICAL ARCHITECTURAL DIFFERENCE: GCP VPCs are GLOBAL

**AWS VPCs are regional. GCP VPCs are GLOBAL.** This is the single most important networking difference between the two clouds.

- In AWS: one VPC per region, subnets per AZ
- In GCP: one VPC spans ALL regions, subnets are regional (not zonal)

**Implications:**

- Multiple AWS regional VPCs often collapse into a single GCP VPC with regional subnets
- VPC peering in GCP is global-to-global (simpler than AWS cross-region peering)
- No need for Transit Gateway equivalent when workloads span regions -- a single VPC handles it
- Firewall rules in GCP are per-network (global), not per-instance like Security Groups
- CIDR ranges must be planned across all regional subnets to avoid overlap

## Eliminators (Hard Blockers)

| AWS Service    | GCP                    | Blocker                                                     |
| -------------- | ---------------------- | ----------------------------------------------------------- |
| Direct Connect | Cloud Interconnect     | Dedicated connection (4-12 weeks setup) -> use Cloud VPN as temp |
| ALB            | HTTP(S) Load Balancer  | SSL certificate passthrough -> use TCP Proxy Load Balancer  |
| NLB            | TCP/UDP Load Balancer  | Host/path-based routing required -> use HTTP(S) Load Balancer |

## Signals (Decision Criteria)

### VPC

- Always -> GCP VPC Network (1:1 deterministic, but **GLOBAL**)
- Preserve CIDR blocks as regional subnet CIDRs
- Multiple AWS regional VPCs -> consider collapsing into single GCP VPC with regional subnets

### Security Groups

- Always -> GCP Firewall Rules (1:1 deterministic)
- Convert direction (ingress/egress) and IP ranges
- **Key difference:** GCP firewall rules are network-level and use target tags/service accounts, not instance-level attachment like AWS Security Groups

### ALB / NLB (Elastic Load Balancing)

- **HTTP/HTTPS + hostname/path routing** -> External HTTP(S) Load Balancer (Layer 7, global)
- **TCP/UDP + high throughput** -> External TCP/UDP Network Load Balancer (Layer 4, regional)
- **TLS passthrough** -> TCP Proxy Load Balancer (Layer 4, global, no termination)
- **Internal load balancing** -> Internal HTTP(S) Load Balancer (L7) or Internal TCP/UDP Load Balancer (L4)
- **Key difference:** GCP HTTP(S) Load Balancer is GLOBAL by default (single anycast IP, Google's global network). AWS ALB is regional.

### Route 53

- Always -> Cloud DNS (1:1 deterministic)
- Preserve zone name, record types, TTLs
- Route 53 health checks -> Cloud DNS routing policies or Cloud Monitoring uptime checks

### CloudFront

- **CDN + edge caching** -> Cloud CDN (backed by HTTP(S) Load Balancer)
- **Static site hosting** -> Cloud CDN + Cloud Storage (GCS)
- **Lambda@Edge** -> No direct equivalent; use Cloud Run for regional serverless compute and Cloud CDN/Load Balancing features for edge behavior
- **Key difference:** Cloud CDN is tightly integrated with HTTP(S) Load Balancer. Enable it on existing backend services rather than creating a separate distribution.

### AWS WAF

- **DDoS protection + WAF rules** -> Cloud Armor + Cloud Armor DDoS protection (always-on at no extra cost)
- **Rate limiting** -> Cloud Armor rate-based rules
- **Bot management** -> Cloud Armor bot management (reCAPTCHA Enterprise integration)
- **IP allowlist/denylist** -> Cloud Armor security policy rules
- **Key difference:** Cloud Armor is attached to backend services on the load balancer, not a standalone resource.

### Direct Connect

- **Dedicated connection** -> Cloud Interconnect (Dedicated or Partner)
- **Temporary/dev connectivity** -> Cloud VPN (quicker setup, lower cost)

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does AWS config require GCP-unsupported features? If yes: switch
2. **Operational Model**: Managed (Cloud Load Balancing, Cloud DNS) vs Custom (Cloud VPN, custom routing)?
   - Prefer managed
3. **User Preference**: From `preferences.json`: `design_constraints.compliance`?
   - **PCI or HIPAA:** Neither framework mandates Cloud Interconnect. **Bias toward documented private connectivity** between sites and GCP (e.g. **Cloud Interconnect** or **Cloud VPN** with encryption, monitoring, and change control) -- choose with your **QSA / BAA / security team**; many compliant designs use VPN-only or no hybrid link when all workloads stay in GCP.
   - **FedRAMP:** Assured Workloads and federal boundary requirements dominate; **private connectivity** is often part of the approved architecture -- still **confirm with your authorizing official / security team**, not this advisor alone.
   - If none of the above: VPN or public-internet paths are commonly acceptable when encrypted and documented.
   - If `compliance` includes `"ccpa"` (CCPA / CPRA) -> VPN or Cloud Interconnect both acceptable; prioritize **documented data paths**, retention controls, and logging for consumer privacy workflows -- not a forced Cloud Interconnect gate
4. **Feature Parity**: Does AWS config require GCP-unsupported features?
   - Example: AWS Transit Gateway -> GCP does not need it (VPCs are global); use VPC Network Peering or Shared VPC instead
5. **Cluster Context**: Are other resources in cluster using specific load balancers? Match
6. **Simplicity**: Fewer resources = higher score

## Examples

### Example 1: VPC

- AWS: `aws_vpc` (cidr_block=10.0.0.0/16, region=us-east-1)
- Signals: Regional VPC, explicit CIDR
- Criterion 1 (Eliminators): PASS
- -> **GCP: VPC Network (GLOBAL, with subnet 10.0.0.0/16 in us-central1)**
- **Note:** GCP VPC is global. The CIDR becomes a regional subnet. If multiple AWS VPCs exist, consider consolidating into one GCP VPC.
- Confidence: `deterministic`

### Example 2: Security Group

- AWS: `aws_security_group` (ingress=[{from_port=443, to_port=443, protocol=tcp, cidr_blocks=["0.0.0.0/0"]}])
- Signals: HTTPS ingress, public
- -> **GCP: Firewall Rule (direction=INGRESS, allow=[tcp:443], source_ranges=[0.0.0.0/0], target_tags=["web"])**
- **Note:** GCP firewall rules use target tags or service accounts to scope which instances they apply to, rather than instance-level attachment.
- Confidence: `deterministic`

### Example 3: ALB (HTTP + path-based)

- AWS: `aws_lb` (load_balancer_type=application) + `aws_lb_listener` + `aws_lb_target_group` (path_pattern=["/api/*"])
- Signals: Path-based routing, HTTP/HTTPS
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): External HTTP(S) Load Balancer (managed, L7, global)
- -> **GCP: External HTTP(S) Load Balancer with URL map (path-based routing)**
- **Note:** GCP HTTP(S) LB is global with a single anycast IP. No need for multi-region ALBs.
- Confidence: `inferred`

### Example 4: Route 53 Zone

- AWS: `aws_route53_zone` (name="example.com")
- Signals: Public DNS zone
- -> **GCP: Cloud DNS Managed Zone (example.com)**
- Confidence: `deterministic`

### Example 5: CloudFront Distribution

- AWS: `aws_cloudfront_distribution` (origin=S3, default_cache_behavior, price_class=PriceClass_100)
- Signals: CDN, S3 origin, edge caching
- Criterion 1 (Eliminators): PASS
- -> **GCP: Cloud CDN (enabled on HTTP(S) Load Balancer with GCS backend bucket)**
- **Note:** Cloud CDN is enabled as a flag on existing backend services, not a separate resource.
- Confidence: `inferred`

### Example 6: AWS WAF

- AWS: `aws_wafv2_web_acl` (rules=[rate_limit, ip_blocklist, sql_injection])
- Signals: WAF rules, rate limiting, OWASP protection
- -> **GCP: Cloud Armor security policy (attached to backend service) with rate limiting, IP denylist, and preconfigured WAF rules**
- Confidence: `inferred`

## Output Schema

```json
{
  "aws_type": "aws_lb",
  "aws_address": "global-https-lb",
  "aws_config": {
    "load_balancer_type": "application",
    "scheme": "internet-facing"
  },
  "gcp_service": "External HTTP(S) Load Balancer",
  "gcp_config": {
    "load_balancing_scheme": "EXTERNAL_MANAGED",
    "protocol": "HTTPS",
    "global": true
  },
  "confidence": "inferred",
  "rationale": "Rubric: AWS ALB -> GCP External HTTP(S) Load Balancer (L7, global, path/host routing)"
}
```
