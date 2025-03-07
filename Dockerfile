# Use your existing Python 3.12 CentOS-based image
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

# ============================================================================
# GPU Setup
# ============================================================================
# These env vars are required so that when a GPU is attached at runtime the
# NVIDIA container runtime exposes it appropriately.
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Install CUDA runtime libraries from NVIDIA’s RHEL9 repo for GPU support.
RUN dnf -y install epel-release && \
    dnf config-manager --add-repo=https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    dnf clean all && \
    dnf -y install cuda-runtime-11-8 && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

# ============================================================================
# Build Arguments
# ============================================================================
ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

USER 0

# ============================================================================
# OS Layer
# ============================================================================
RUN --mount=type=bind,source=os-packages.txt,target=/tmp/os-packages.txt \
    dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf install -y $(cat /tmp/os-packages.txt) && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Copy UV binary tools from a known good image.
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

# ============================================================================
# Docling Layer
# ============================================================================
USER 1001

WORKDIR /opt/app-root/src

# Set thread count and locale/encoding settings.
ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# Install project dependencies (using cache mount for BuildKit)
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-install-project --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

# Download required models and fix permissions
RUN echo "Downloading models..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy application code with proper ownership/permissions
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

# Final dependency sync (using BuildKit cache mount)
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001

CMD ["docling-serve", "run"]