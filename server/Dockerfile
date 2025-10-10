FROM swift:6.2-noble

WORKDIR /app

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy Package files first for better caching
COPY Package.swift Package.resolved ./

# Resolve dependencies in separate layer with cache mount
RUN --mount=type=cache,target=/root/.swiftpm swift package resolve

# Copy source code
COPY Sources ./Sources

# Copy Resources directory for static files (HTML, etc.)
COPY Resources ./Resources

# Build release with memory-conscious settings and cache mount
RUN --mount=type=cache,target=/root/.swiftpm \
    --mount=type=cache,target=/root/.cache \
    swift build -c release --jobs 1

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

CMD [".build/release/App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
