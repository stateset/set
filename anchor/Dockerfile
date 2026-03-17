# Set Chain Anchor Service Dockerfile

# Build stage
FROM rust:1.82-bookworm AS builder

WORKDIR /app

# Copy manifests first for dependency caching
COPY Cargo.toml Cargo.lock* ./

# Create dummy source for dependency caching
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

# Build dependencies only (cached unless Cargo.toml/lock change)
RUN cargo build --release 2>/dev/null || true

# Copy actual source and rebuild
COPY src ./src
RUN touch src/main.rs && cargo build --release

# Runtime stage — minimal image
FROM debian:bookworm-slim

# Single apt-get layer with all runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/set-anchor /app/set-anchor

# Create non-root user
RUN useradd -r -s /bin/false anchor
USER anchor

# Environment variables
ENV RUST_LOG=info,set_anchor=debug
ENV HEALTH_PORT=9090

# Expose health endpoint port
EXPOSE 9090

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:9090/health || exit 1

# Run the service
ENTRYPOINT ["/app/set-anchor"]
