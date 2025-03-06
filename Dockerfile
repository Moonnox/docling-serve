# syntax=docker/dockerfile:1.4

###############################################################################
# 1. Base & Build Args
###############################################################################
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS="--all-extras --skip=cpu"

###############################################################################
# 2. Become root
###############################################################################
USER 0

###############################################################################
# (A) -- If you want to install `uv` from PyPI
# Uncomment below, provide the correct package name:
RUN pip install uv

###############################################################################
# (B) -- If you want to copy `uv` from ghcr.io
# Make sure these paths actually exist in that image.
# COPY --from=ghcr.io/astral-sh/uv:0.6.1 /usr/local/bin/uv /usr/local/bin/uvx /bin/

###############################################################################
# 3. OS Packages (Tesseract, etc.)
###############################################################################
COPY os-packages.txt /tmp/os-packages.txt
RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf -y install $(cat /tmp/os-packages.txt) && \
    dnf clean all && \
    rm -rf /var/cache/dnf

###############################################################################
# 4. Tesseract data path
###############################################################################
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

###############################################################################
# 5. Switch to non-root, set working dir
###############################################################################
USER 1001
WORKDIR /opt/app-root/src

###############################################################################
# 6. Environment Variables
###############################################################################
ENV OMP_NUM_THREADS=4 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PYTHONIOENCODING=utf-8 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/app-root \
    DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

###############################################################################
# 7. Copy Project config (pyproject.toml, uv.lock, etc.)
###############################################################################
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

###############################################################################
# 8. uv sync: Install dependencies
###############################################################################
RUN uv sync --frozen --no-install-project --no-dev ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 9. Download docling models
###############################################################################
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

###############################################################################
# 10. Copy Application Code
###############################################################################
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

###############################################################################
# 11. (Optional) Final uv sync
###############################################################################
RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 12. Expose & Default CMD
###############################################################################
EXPOSE 5001
CMD ["docling-serve", "run"]