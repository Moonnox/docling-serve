# Use BuildKit-specific syntax; ensure BuildKit is enabled during build (see cloudbuild.yaml)
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

USER 0

################################################################################
# OS Layer
################################################################################

# The --mount option here binds the os-packages.txt file.
# This requires Docker BuildKit. Make sure to build with DOCKER_BUILDKIT=1.
RUN --mount=type=bind,source=os-packages.txt,target=/tmp/os-packages.txt \
    dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf install -y $(cat /tmp/os-packages.txt) && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# Copy binaries from an external image
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

################################################################################
# Docling Layer
################################################################################
USER 1001
WORKDIR /opt/app-root/src

# Environment settings for containerized environments.
ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

# Copy project configuration files.
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# Use a cache mount to speed up dependency synchronization.
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-install-project --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

# Download required models.
RUN echo "Downloading models..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy the main application code.
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

# A second synchronization step using BuildKit cache.
RUN --mount=type=cache,target=/opt/app-root/src/.cache/uv,uid=1001 \
    uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001

CMD ["docling-serve", "run"]