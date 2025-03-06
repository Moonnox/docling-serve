# syntax=docker/dockerfile:1.4
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

USER 0

# Copy in os-packages.txt
COPY os-packages.txt /tmp/os-packages.txt

RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf install -y $(cat /tmp/os-packages.txt) && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Copy uv binaries from external image
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

USER 1001
WORKDIR /opt/app-root/src

ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy config files
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# Sync dependencies (no BuildKit --mount usage)
RUN uv sync --frozen --no-install-project --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

# Download models
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy application code
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

# Second sync if needed
RUN uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001

CMD ["docling-serve", "run"]