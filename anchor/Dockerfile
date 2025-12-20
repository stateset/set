# Set Chain Anchor Service Dockerfile

# Build stage
FROM rust:1.82-bookworm AS builder

WORKDIR /app

# Copy manifests
COPY Cargo.toml Cargo.lock* ./

# Create dummy source for dependency caching
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

# Build dependencies only
RUN cargo build --release 2>/dev/null || true

# Copy actual source
COPY src ./src

# Build the application
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/set-anchor /app/set-anchor

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

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
