# syntax=docker/dockerfile:1.4
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

################################################################################
# 1) Install system packages as root, including CUDA libraries
################################################################################
USER 0

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

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

# Copy uv binaries
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

################################################################################
# 2) Copy in your docling_serve code as root, then fix ownership to user=1001
################################################################################
WORKDIR /opt/app-root/src

COPY docling_serve ./docling_serve

# Now we can safely chown and chmod as root
RUN chown -R 1001:0 docling_serve && chmod -R 664 docling_serve

################################################################################
# 3) Switch to user 1001 for the rest of the container
################################################################################
USER 1001

ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy your pyproject.toml, uv.lock, etc.
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

RUN uv sync --frozen --no-install-project --no-dev ${UV_SYNC_EXTRA_ARGS}

RUN echo "Downloading models..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001

CMD ["docling-serve", "run"]