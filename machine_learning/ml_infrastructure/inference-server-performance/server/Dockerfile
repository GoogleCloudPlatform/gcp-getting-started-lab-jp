FROM nvcr.io/nvidia/tensorflow:19.05-py3

COPY tensorrt-optimization.py tensorrt-optimization.py

# This script assumes host directory is mounted in models/resnet/...
ENTRYPOINT ["python3", "tensorrt-optimization.py"]