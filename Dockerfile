# Dockerfile

ARG BASE_IMAGE=quay.io/sclorg/python-312-c9s:c9s
FROM ${BASE_IMAGE}

# ... (dnf install steps, etc.) ...

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

# Copy config
COPY --chown=1001:0 pyproject.toml uv.lock README.md ./

# Option A: Install all extras but skip CPU explicitly
RUN uv sync --frozen --no-install-project --no-dev \
    --all-extras \
    --skip=cpu

# If the package calls the CPU extra "docling-serve[cpu]", do:
# RUN uv sync --frozen --no-install-project --no-dev \
#     --all-extras \
#     --skip=docling-serve[cpu]

# Download docling models
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" \
    layout tableformer picture_classifier easyocr && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

# Copy your application code
COPY --chown=1001:0 docling_serve docling_serve

# Optionally sync a second time
RUN uv sync --frozen --no-dev \
    --all-extras \
    --skip=cpu

EXPOSE 5001
CMD ["docling-serve", "run"]