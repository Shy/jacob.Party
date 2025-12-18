# Build stage
FROM swift:6.2-noble AS builder

WORKDIR /app

# Copy Package files first for better caching
COPY Package.swift Package.resolved ./

# Resolve dependencies in separate layer with cache mount
RUN --mount=type=cache,target=/root/.swiftpm swift package resolve

# Copy source code
COPY Sources ./Sources

# Copy Resources directory for static files (HTML, etc.)
COPY Resources ./Resources

# Copy Public directory for service worker and static assets
COPY Public ./Public

# Build release with parallel compilation and cache mount
RUN --mount=type=cache,target=/root/.swiftpm \
    --mount=type=cache,target=/root/.cache \
    swift build -c release --jobs 2

# Runtime stage - much smaller base image
FROM ubuntu:24.04

# Install only runtime dependencies including Swift runtime and SSL libraries
RUN apt-get update && \
    apt-get install -y \
    curl \
    ca-certificates \
    libicu74 \
    libxml2 \
    libssl3 \
    libcurl4 \
    libatomic1 \
    libc6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Swift runtime libraries from builder (needed for Swift apps to run)
COPY --from=builder /usr/lib/swift /usr/lib/swift

# Copy the built binary from builder
COPY --from=builder /app/.build/release/App /app/App

# Copy Resources directory
COPY --from=builder /app/Resources /app/Resources

# Copy Public directory for service worker
COPY --from=builder /app/Public /app/Public

# Create non-root user for security (use UID 1001 to avoid conflicts)
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Set Swift runtime environment variables to improve stability
ENV SWIFT_DETERMINISTIC_HASHING=1
ENV SWIFT_BACKTRACE=enable=no
ENV LIBDISPATCH_COOPERATIVE_POOL_STRICT=0

EXPOSE 8080

# Add health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
