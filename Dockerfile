# syntax=docker/dockerfile:1.4
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s

FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr tesseract"
# If you're installing GPU extras for docling (or any other library),
# set them here. If you want CPU-only, remove or change to --extra=cpu
ARG UV_SYNC_EXTRA_ARGS="--extra=cu124"

###############################################################################
# 1) We start as root to install OS packages + fix permissions
###############################################################################
# Root user
USER 0

# Enable GPU usage in Cloud Run (no driver needed, just the user-mode libs)
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Copy + install OS packages & CUDA
COPY os-packages.txt /tmp/os-packages.txt
RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
    dnf install -y $(cat /tmp/os-packages.txt) cuda-toolkit-12-1 && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Pull in uv binaries from the external image
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

###############################################################################
# 2) Copy your application code as root, fix ownership/permissions
###############################################################################
WORKDIR /opt/app-root/src

# Copy the docling_serve directory
COPY docling_serve ./docling_serve

# Ensure directories have the +x bit, and files are readable.
# Then chown them to the docling user (1001)
RUN chown -R 1001:0 docling_serve && \
    find docling_serve -type d -exec chmod 755 {} \; && \
    find docling_serve -type f -exec chmod 644 {} \;

###############################################################################
# 3) Switch to non-root user for app environment & Python steps
###############################################################################
USER 1001

# Common environment variables
ENV OMP_NUM_THREADS=4 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PYTHONIOENCODING=utf-8 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root \
    DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy your pyproject, lockfile, etc. with correct ownership
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# 4) Install docling (and your other Python deps) in editable mode, with GPU extras
RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

# 5) Download Docling models
RUN echo "Downloading models..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# 6) If docling_serve introduced new deps, sync again
RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

RUN uv sync --extra tesserocr
RUN uv sync --extra ui

# 7) Expose whichever port your app uses (Cloud Run will forward it)
# EXPOSE 5001

# 8) Final command
CMD ["docling-serve", "run", "--host=0.0.0.0", "--port", "8080", "--workers", "5"]