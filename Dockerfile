# syntax=docker/dockerfile:1.4
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s

FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

################################################################################
# Switch to root for system-level operations                                    #
################################################################################
USER 0

# ------------------------------------------------------------------------------
# 1) REQUIRED FOR GPU ON CLOUD RUN
#    Make sure Cloud Run sees that you want GPU access. The driver is on the host,
#    so you only need the user-mode CUDA libs inside the container.
# ------------------------------------------------------------------------------
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

################################################################################
# OS Layer
################################################################################

# We'll mount your existing os-packages.txt and install everything you need,
# including the CUDA toolkit. The RHEL 9 CUDA repo is below.
RUN --mount=type=bind,source=os-packages.txt,target=/tmp/os-packages.txt \
    dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    # Install all OS packages from your text file + the CUDA toolkit
    dnf install -y $(cat /tmp/os-packages.txt) cuda-toolkit-12-1 && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

# Tesseract environment variable from your original Dockerfile
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Copy uv binaries from the upstream container
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

################################################################################
# Docling layer
################################################################################

USER 1001

WORKDIR /opt/app-root/src

# On container environments, always set a thread budget to avoid undesired congestion.
ENV OMP_NUM_THREADS=4

# UTF-8 environment
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8

# UV environment variables
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root

# Where docling will store downloaded models
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy your project files (pyproject.toml, uv.lock, etc.)
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# First sync (no dev dependencies, no local install)
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-install-project --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

# Download Docling models
RUN echo "Downloading models..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy in your `docling_serve` directory
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

# Second sync (usually picks up anything introduced by docling_serve, if needed)
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001

CMD ["docling-serve", "run"]