# Lab04. Single-cluster Inference Gateway feature checks

This lab is optional and runs after Lab02. Use it when you want to test features that are easier to validate on a single GKE Inference Gateway before returning to the multi-cluster Gateway.

The default target is the Asia cluster:

```bash
export PROJECT_ID=$(gcloud config get-value project)
if [ -d "./inference-gw/lab-01" ]; then
  export LAB_DIR="$(pwd)/inference-gw"
elif [ -d "./lab-01" ]; then
  export LAB_DIR="$(pwd)"
else
  echo "inference-gw directory not found. Move to gcp-getting-started-lab-jp or inference-gw."
  exit 1
fi
cd "$LAB_DIR/lab-04"
export SINGLE_GATEWAY_REGION=asia-northeast1
export SINGLE_GATEWAY_ZONE=asia-northeast1-b
export SINGLE_GATEWAY_CLUSTER=gke-asia-northeast1
export SINGLE_CTX="gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}"
```

## Create the single-cluster Gateway

```bash
./configure-single-gateway.sh
./test-single-gateway-features.sh
```

This creates a regional internal Gateway with `gatewayClassName: gke-l7-rilb` and routes traffic to the local `InferencePool/qwen-pool`.

Expected output:

```text
=== Base request ===
Expected: HTTP 200 from Gateway -> InferencePool -> vLLM.
HTTP 200
{
  "model": "Qwen/Qwen3-8B",
  "choices": [...]
}
```

If you see `HTTP 503` immediately after creating the Gateway, wait 1-3 minutes and rerun the test. The regional internal Gateway sometimes needs a little time before backend health is reflected.

## Body-Based Routing

Body-Based Routing reads the OpenAI request body and injects routing headers such as `X-Gateway-Model-Name`. Enable it when creating the single Gateway:

```bash
ENABLE_BBR=true ./configure-single-gateway.sh
EXPECT_BBR=true ./test-single-gateway-features.sh
```

With BBR enabled, `single-qwen-route` only accepts requests whose body model is `Qwen/Qwen3-8B`. A bogus model name should fail before it reaches vLLM.

Expected negative check:

```text
=== Body-Based Routing negative check ===
Expected: HTTP 404 because the route only accepts X-Gateway-Model-Name=Qwen/Qwen3-8B.
HTTP 404
BBR fail-closed check passed.
```

## Prefix/KV cache behavior

The Inference Gateway endpoint picker can use request characteristics and backend metrics such as KV-cache usage to pick an endpoint. This lab exposes the relevant vLLM metrics and sends repeated-prefix prompts:

```bash
PREFIX_ROUNDS=8 ./test-single-gateway-features.sh
```

Expected output is mainly a health and observation signal:

```text
=== Repeated-prefix requests for KV/prefix-cache behavior ===
Expected: each round returns HTTP 200. Elapsed seconds are observational, not a strict pass/fail signal.
round=1 http=200 elapsed_seconds=1
round=2 http=200 elapsed_seconds=0
round=3 http=200 elapsed_seconds=0
```

For regional distribution on the multi-cluster Gateway, use:

```bash
cd "$LAB_DIR/lab-03"
REQUESTS_PER_REGION=10 MAX_TOKENS=16 ./regional-distribution-test.sh
```

That script compares per-pod vLLM counters before and after Gateway traffic.

Example distribution result:

```text
Cluster totals:
  asia-northeast1   delta=   10.00
  europe-west4      delta=   10.00
```

`delta` is the increase in successful vLLM requests during the run. A `kv=0.000000` value is fine for short prompts; the regional script is primarily checking that requests reach both backend pools.

## LoRA adapter checks

LoRA requires vLLM to start with LoRA support enabled and an adapter path that is visible inside the vLLM container. The base lab does not bundle an adapter.

Redeploy vLLM with runtime LoRA support:

```bash
cd "$LAB_DIR/lab-02"
export VLLM_EXTRA_ARGS="--enable-lora --max-loras 4 --max-lora-rank 64"
export VLLM_ALLOW_RUNTIME_LORA_UPDATING=True
envsubst '${PROJECT_ID} ${VLLM_EXTRA_ARGS} ${VLLM_ALLOW_RUNTIME_LORA_UPDATING}' < workload_template.yaml > workload.yaml
./deploy-workload.sh
```

Then load an adapter from a path mounted in the vLLM container:

```bash
cd "$LAB_DIR/lab-04"
export LORA_NAME="my-qwen-lora"
export LORA_PATH="/data/lora/my-qwen-lora"
./load-lora-adapter.sh
```

If you also enable BBR, add a route match for the adapter model name or temporarily return to the default `single-qwen-route` so that adapter requests can reach vLLM.
