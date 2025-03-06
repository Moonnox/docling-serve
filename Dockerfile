# syntax=docker/dockerfile:1.4

###############################################################################
# 1. Base Image
###############################################################################
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

###############################################################################
# 2. Build Arguments
###############################################################################
# MODELS_LIST: which Docling models to download
# UV_SYNC_EXTRA_ARGS: additional arguments passed to `uv sync` (e.g. --skip=cpu)
ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS=""

###############################################################################
# 3. Become root to install OS packages
###############################################################################
USER 0

###############################################################################
# 4. Copy & Install OS Dependencies
###############################################################################
COPY os-packages.txt /tmp/os-packages.txt

RUN dnf -y install --best --nodocs --setopt=install_weak_deps=False dnf-plugins-core && \
    dnf config-manager --best --nodocs --setopt=install_weak_deps=False --save && \
    dnf config-manager --enable crb && \
    dnf -y update && \
    dnf install -y $(cat /tmp/os-packages.txt) && \
    dnf -y clean all && \
    rm -rf /var/cache/dnf

# Tesseract data path
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

###############################################################################
# 5. Copy uv binaries from external image (optional)
###############################################################################
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

###############################################################################
# 6. Switch back to non-root user
###############################################################################
USER 1001
WORKDIR /opt/app-root/src

###############################################################################
# 7. Environment Variables
###############################################################################
ENV OMP_NUM_THREADS=4
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PYTHONIOENCODING=utf-8
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/opt/app-root
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models

###############################################################################
# 8. Copy Project Config Files
###############################################################################
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

###############################################################################
# 9. Install Python Dependencies with uv
###############################################################################
# Using --skip=cpu (passed in UV_SYNC_EXTRA_ARGS) to allow cu124 (GPU) to be installed
RUN uv sync --frozen --no-install-project --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 10. Download Docling Models
###############################################################################
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

###############################################################################
# 11. Copy Application Code
###############################################################################
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

###############################################################################
# 12. Final uv sync (If needed)
###############################################################################
RUN uv sync --frozen --no-dev --all-extras ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 13. Expose Port and Set Default CMD
###############################################################################
EXPOSE 5001
CMD ["docling-serve", "run"]