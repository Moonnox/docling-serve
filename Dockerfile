# syntax=docker/dockerfile:1.4

###############################################################################
# 1. Base Image & Build Args
###############################################################################
ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

# You can define which docling models to download:
ARG MODELS_LIST="layout tableformer picture_classifier easyocr"
ARG UV_SYNC_EXTRA_ARGS="--all-extras --skip=cpu"

###############################################################################
# 2. Switch to root (to install packages)
###############################################################################
USER 0

###############################################################################
# 3. Copy and install OS packages
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
# 4. Tesseract data path (for docling-serve OCR)
###############################################################################
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

###############################################################################
# 5. Copy uv binaries from an external image
#    Make sure this step is before we call "uv sync," so the 'uv' command exists.
###############################################################################
COPY --from=ghcr.io/astral-sh/uv:0.6.1 /uv /uvx /bin/

###############################################################################
# 6. Switch to non-root user, set working directory
###############################################################################
USER 1001
WORKDIR /opt/app-root/src

###############################################################################
# 7. Environment Variables
#    - Tuning for docling / Python
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
# 8. Copy in project config: pyproject.toml, uv.lock, etc.
###############################################################################
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

###############################################################################
# 9. Install Python dependencies with uv
#    - Skipping the CPU extra so that GPU (cu124) can be used
###############################################################################
RUN uv sync --frozen --no-install-project --no-dev ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 10. Download docling models into .cache/docling/models
###############################################################################
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

###############################################################################
# 11. Copy your actual application code
###############################################################################
COPY --chown=1001:0 --chmod=664 ./docling_serve ./docling_serve

###############################################################################
# 12. (Optional) Final uv sync step if you install more dependencies
###############################################################################
RUN uv sync --frozen --no-dev ${UV_SYNC_EXTRA_ARGS}

###############################################################################
# 13. Expose port & set default command
###############################################################################
EXPOSE 5001
CMD ["docling-serve", "run"]