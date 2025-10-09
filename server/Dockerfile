FROM swift:6.2-noble

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy package files first (for better caching)
COPY Package.swift ./

# Fetch dependencies (will create new Package.resolved)
RUN swift package resolve

# Copy source code
COPY Sources ./Sources
COPY Resources ./Resources

# Build the application in release mode
RUN swift build -c release

# Create non-root user for security
RUN useradd -m -u 1001 appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose the port
EXPOSE 8080

# Run the app
CMD [".build/release/App"]
