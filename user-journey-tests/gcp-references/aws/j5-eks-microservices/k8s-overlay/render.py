#!/usr/bin/env python3
"""Render the journey's k8s manifests for GKE.

Reads user-journey-tests/aws/j5-eks-microservices/k8s/*.yaml and writes k8s-build/ with:
  - image registry placeholders resolved to Artifact Registry paths
  - the IRSA annotation replaced by the Workload Identity annotation
  - FIRESTORE_DB/GCP_PROJECT env added to booking-api (funnel overlay reads them)
Everything else ships unchanged — that IS the migration story.

Env: AR_PREFIX (e.g. asia-northeast1-docker.pkg.dev/<project>/ems),
     IMAGE_TAG, GSA_EMAIL, GCP_PROJECT, FIRESTORE_DB.
"""

import os
import pathlib
import sys

import yaml

HERE = pathlib.Path(__file__).resolve().parent
JOURNEY_K8S = HERE / "../../../../../user-journey-tests/aws/j5-eks-microservices/k8s"
OUT = HERE / "../k8s-build"

AR_PREFIX = os.environ["AR_PREFIX"]
IMAGE_TAG = os.environ.get("IMAGE_TAG", "latest")
GSA_EMAIL = os.environ["GSA_EMAIL"]
GCP_PROJECT = os.environ["GCP_PROJECT"]
FIRESTORE_DB = os.environ.get("FIRESTORE_DB", "ems-bookings")


def transform(doc):
    if not isinstance(doc, dict):
        return doc
    kind = doc.get("kind")
    name = doc.get("metadata", {}).get("name", "")

    if kind == "ServiceAccount" and name == "booking-api":
        annotations = doc["metadata"].setdefault("annotations", {})
        annotations.pop("eks.amazonaws.com/role-arn", None)
        annotations["iam.gke.io/gcp-service-account"] = GSA_EMAIL

    if kind == "Deployment":
        for container in doc["spec"]["template"]["spec"]["containers"]:
            image = container.get("image", "")
            # ${ECR_REGISTRY}/ems-x:${IMAGE_TAG} -> <AR_PREFIX>/ems-x:<tag>
            if "ems-" in image:
                repo = image.split("/")[-1].split(":")[0]
                container["image"] = f"{AR_PREFIX}/{repo}:{IMAGE_TAG}"
            if name == "booking-api":
                env = container.setdefault("env", [])
                env = [e for e in env if e.get("name") not in ("AWS_REGION",)]
                env.extend([
                    {"name": "GCP_PROJECT", "value": GCP_PROJECT},
                    {"name": "FIRESTORE_DB", "value": FIRESTORE_DB},
                ])
                container["env"] = env

    if kind == "Service" and doc.get("spec", {}).get("type") == "LoadBalancer":
        # the NLB annotation is AWS-specific; GKE provisions a passthrough
        # network LB from the bare Service type
        doc["metadata"].get("annotations", {}).pop(
            "service.beta.kubernetes.io/aws-load-balancer-type", None)

    return doc


def main():
    OUT.mkdir(exist_ok=True)
    for path in sorted(JOURNEY_K8S.glob("*.yaml")):
        if path.name == "kustomization.yaml":
            continue
        docs = [transform(d) for d in yaml.safe_load_all(path.read_text()) if d is not None]
        (OUT / path.name).write_text(yaml.safe_dump_all(docs, sort_keys=False))
        print(f"rendered {path.name}")
    print(f"manifests written to {OUT}")


if __name__ == "__main__":
    sys.exit(main())
