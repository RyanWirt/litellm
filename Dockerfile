# Base image for building
ARG LITELLM_BUILD_IMAGE=registry1.dso.mil/ironbank/redhat/ubi/ubi9:9.8

# Builder stage
FROM $LITELLM_BUILD_IMAGE AS builder

WORKDIR /app
USER root

RUN dnf module enable nodejs:20 -y && \
    dnf install -y --nodocs \
        bash \
        gcc \
        python3.12 \
        python3.12-devel \
        openssl \
        openssl-devel \
        nodejs \
        npm \
        libsndfile && \
    dnf clean all

RUN python3.12 -m ensurepip --upgrade && \
    pip3.12 install uv==0.11.7

ENV UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:${PATH}"

# Copy dependency metadata first for layer caching
COPY pyproject.toml uv.lock ./
COPY enterprise/pyproject.toml enterprise/
COPY litellm-proxy-extras/pyproject.toml litellm-proxy-extras/

# Install third-party dependencies (cached unless pyproject.toml/uv.lock change)
RUN uv sync --frozen --no-install-project --no-install-workspace --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3.12

# Copy full source tree
COPY . .

# Build Admin UI before final sync
RUN sed -i 's/\r$//' docker/build_admin_ui.sh && chmod +x docker/build_admin_ui.sh && ./docker/build_admin_ui.sh

# Install project and workspace packages (fast - deps already cached)
RUN uv sync --frozen --no-default-groups --no-editable \
    --extra proxy \
    --extra proxy-runtime \
    --extra extra_proxy \
    --extra semantic-router \
    --python python3.12

RUN prisma generate --schema=./schema.prisma

RUN sed -i 's/\r$//' docker/entrypoint.sh && chmod +x docker/entrypoint.sh && \
    sed -i 's/\r$//' docker/prod_entrypoint.sh && chmod +x docker/prod_entrypoint.sh

# Runtime stage
FROM $LITELLM_BUILD_IMAGE AS runtime

USER root

RUN dnf module enable nodejs:20 -y && \
    dnf install -y --nodocs bash openssl tzdata nodejs npm python3.12 libsndfile && \
    dnf clean all && \
    npm install -g npm@11.14.0 tar@7.5.11 glob@13.0.6 @isaacs/brace-expansion@5.0.1 brace-expansion@5.0.5 minimatch@10.2.4 diff@8.0.3 picomatch@4.0.4 && \
    GLOBAL="$(npm root -g)" && \
    for pkg in tar glob @isaacs/brace-expansion brace-expansion minimatch diff picomatch; do \
        name="${pkg##*/}"; \
        find "$GLOBAL/npm" -type d -name "$name" -path "*/node_modules/$pkg" | while read d; do \
            rm -rf "$d" && cp -rL "$GLOBAL/$pkg" "$d"; \
        done; \
    done && \
    npm cache clean --force && \
    { dnf remove -y npm 2>/dev/null || true; } && \
    dnf clean all

WORKDIR /app
ENV PATH="/app/.venv/bin:${PATH}"

COPY --from=builder /app /app
# Prisma binaries live in $HOME/.cache (default prisma-python location),
# which is /root/.cache here. Copy only the Prisma subdirs — copying the
# whole /root/.cache drags in the uv build cache (~660 MB, includes a
# setuptools wheel that surfaces as a CVE finding even though it's not
# on the runtime sys.path).
COPY --from=builder /root/.cache/prisma /root/.cache/prisma
COPY --from=builder /root/.cache/prisma-python /root/.cache/prisma-python

RUN find /app/.venv -type d -path "*/tornado/test" | xargs --no-run-if-empty rm -rf

EXPOSE 4000/tcp

ENTRYPOINT ["docker/prod_entrypoint.sh"]
CMD ["--port", "4000"]
