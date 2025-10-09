FROM swift:6.2-noble AS builder

# Install system dependencies in a single layer
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set working directory
WORKDIR /app

# Copy package manifest files for dependency resolution
# This layer will be cached unless Package.swift or Package.resolved changes
COPY Package.swift ./
COPY Package.resolved ./

# Fetch dependencies (cached if Package files unchanged)
# Use --configuration release for optimized dependency builds
RUN swift package resolve

# Copy source code
COPY Sources ./Sources
COPY Resources ./Resources

# Build the application in release mode with optimizations
# - Use all available CPU cores for faster builds
# - Enable whole-module optimization
# - Strip debug symbols to reduce binary size
RUN swift build \
    -c release \
    -Xswiftc -g0 \
    -Xswiftc -cross-module-optimization \
    -Xswiftc -enforce-exclusivity=unchecked \
    --build-tests disable

# Runtime stage - much smaller image
FROM ubuntu:noble-20241009

# Install only runtime dependencies
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libxml2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security
RUN useradd -m -u 1001 -s /bin/bash appuser

# Set working directory
WORKDIR /app

# Copy built application from builder stage
# Use --chown to set ownership in one step
COPY --from=builder --chown=appuser:appuser /app/.build/release/App ./App
COPY --from=builder --chown=appuser:appuser /app/Resources ./Resources

# Switch to non-root user
USER appuser

# Expose the port
EXPOSE 8080

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the app
CMD ["./App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
