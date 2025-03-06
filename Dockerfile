# syntax=docker/dockerfile:1.4

ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS="--all-extras --skip=cpu"

USER 0

COPY os-packages.txt /tmp/os-packages.txt
RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf -y install $(cat /tmp/os-packages.txt) && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

# <-- Make sure these paths exist in the upstream image:
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /usr/local/bin/uv /usr/local/bin/uvx /bin/

USER 1001
WORKDIR /opt/app-root/src

ENV OMP_NUM_THREADS=4 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PYTHONIOENCODING=utf-8 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root \
    DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

RUN uv sync --frozen --no-install-project --no-dev ${UV_SYNC_EXTRA_ARGS}

RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

EXPOSE 5001
CMD ["docling-serve", "run"]