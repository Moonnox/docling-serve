# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

# Switch to root
USER 0

# Copy & install OS packages
COPY os-packages.txt /tmp/os-packages.txt
RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf -y install $(cat /tmp/os-packages.txt) && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Copy uv binaries (optional)
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

# Switch back to non-root
USER 1001
WORKDIR /opt/app-root/src

ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy config
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# **GPU-only** `uv sync` (no `--all-extras`)
# - We skip default extras & explicitly add `cu124`
RUN uv sync --frozen --no-install-project --no-dev \
    --no-default-extras \
    --extra=cu124

# Download docling models
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" \
    layout tableformer picture_classifier easyocr && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy app code
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

# Final sync if needed:
RUN uv sync --frozen --no-dev --no-default-extras --extra=cu124

EXPOSE 5001
CMD ["docling-serve", "run"]