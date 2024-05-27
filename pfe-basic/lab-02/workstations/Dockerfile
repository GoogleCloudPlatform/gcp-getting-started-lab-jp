FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Install Maven
RUN apt-get update && apt-get install -y maven

# Spring Boot Extension
RUN wget https://open-vsx.org/api/VMware/vscode-boot-dev-pack/0.1.0/file/VMware.vscode-boot-dev-pack-0.1.0.vsix && \
    unzip VMware.vscode-boot-dev-pack-0.1.0.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-boot-dev-pack

# Spring Initializr Java Support
RUN wget https://open-vsx.org/api/vscjava/vscode-spring-initializr/0.11.2/file/vscjava.vscode-spring-initializr-0.11.2.vsix && \
    unzip vscjava.vscode-spring-initializr-0.11.2.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-spring-initializr

# Spring Boot Dashboard
RUN wget https://open-vsx.org/api/vscjava/vscode-spring-boot-dashboard/0.13.1/file/vscjava.vscode-spring-boot-dashboard-0.13.1.vsix && \
    unzip vscjava.vscode-spring-boot-dashboard-0.13.1.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-spring-boot-dashboard

# Extension pack for Java
RUN wget https://open-vsx.org/api/vscjava/vscode-java-pack/0.26.0/file/vscjava.vscode-java-pack-0.26.0.vsix && \
    unzip vscjava.vscode-java-pack-0.26.0.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-java-pack

# ESLint extension
RUN wget https://open-vsx.org/api/dbaeumer/vscode-eslint/2.4.4/file/dbaeumer.vscode-eslint-2.4.4.vsix && \
    unzip dbaeumer.vscode-eslint-2.4.4.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-eslint

# Docker Extension
RUN wget https://open-vsx.org/api/ms-azuretools/vscode-docker/1.25.2/file/ms-azuretools.vscode-docker-1.25.2.vsix && \
    unzip ms-azuretools.vscode-docker-1.25.2.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-docker

# yaml Extension
RUN wget https://open-vsx.org/api/redhat/vscode-yaml/1.14.0/file/redhat.vscode-yaml-1.14.0.vsix && \
    unzip redhat.vscode-yaml-1.14.0.vsix "extension/*" &&\
    mv extension /opt/code-oss/extensions/vscode-yaml