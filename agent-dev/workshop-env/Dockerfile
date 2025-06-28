FROM asia-northeast1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Install system dependencies and Terraform
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3-venv \
    make \
    jq \
    gnupg \
    software-properties-common \
    curl \
    && curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - \
    && apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    && apt-get update && apt-get install -y terraform \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a global virtual environment and install Python packages
RUN python3 -m venv /opt/global-venv \
    && /opt/global-venv/bin/pip install --no-cache-dir uv \
    && /opt/global-venv/bin/pip install --no-cache-dir --upgrade agent-starter-pack

# Activate the global venv for all users by default and install project packages
ENV VIRTUAL_ENV="/opt/global-venv"
# Prepend venv's bin to the PATH
ENV PATH="/opt/global-venv/bin:${PATH}"

# Install VSCode Extensions
RUN mkdir -p /tmp/extensions \
    && cd /tmp/extensions \
    # Python Extension
    && wget -q https://open-vsx.org/api/ms-python/python/2025.4.0/file/ms-python.python-2025.4.0.vsix \
    && unzip -q ms-python.python-2025.4.0.vsix "extension/*" \
    && mv extension /opt/code-oss/extensions/ms-python \
    && rm -rf extension ms-python.python-2025.4.0.vsix \
    # Jupyter Extension
    && wget -q https://open-vsx.org/api/ms-toolsai/jupyter/2025.5.0/file/ms-toolsai.jupyter-2025.5.0.vsix \
    && unzip -q ms-toolsai.jupyter-2025.5.0.vsix "extension/*" \
    && mv extension /opt/code-oss/extensions/ms-toolsai \
    && rm -rf extension ms-toolsai.jupyter-2025.5.0.vsix \
    # Terraform Extension
    && wget https://open-vsx.org/api/hashicorp/terraform/linux-x64/2.34.5/file/hashicorp.terraform-2.34.5@linux-x64.vsix \
    && unzip hashicorp.terraform-2.34.5@linux-x64.vsix "extension/*" \
    && mv extension /opt/code-oss/extensions/hashicorp-terraform \
    && rm -rf extension hashicorp.terraform-2.34.5@linux-x64.vsix \
    && cd / \
    && rmdir /tmp/extensions

