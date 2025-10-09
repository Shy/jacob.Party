FROM swift:6.2

# Install system dependencies in a single layer
WORKDIR /app

# Copy package files first for better layer caching
COPY Package.swift Package.resolved ./

# Resolve dependencies (cached if package files unchanged)
RUN swift package resolve

# Copy source files
COPY Sources ./Sources
COPY Resources ./Resources

# Build in release mode with static linking to reduce runtime dependencies
RUN swift build -c release --static-swift-stdlib

# Expose the port
EXPOSE 8080

# Run the app
CMD [".build/release/App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
