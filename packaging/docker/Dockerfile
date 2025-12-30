# Multi-stage build for jake
# Build: docker build -t jake -f packaging/docker/Dockerfile .
# Run:   docker run --rm -v $(pwd):/work jake [recipe]

# Stage 1: Build
FROM alpine:3.19 AS builder

# Install Zig
RUN apk add --no-cache zig

WORKDIR /src
COPY . .

# Build with release optimizations
RUN zig build -Doptimize=ReleaseSafe

# Stage 2: Runtime
FROM alpine:3.19

# Install common tools that Jakefiles might need
RUN apk add --no-cache \
    bash \
    coreutils \
    git \
    curl \
    && rm -rf /var/cache/apk/*

# Copy binary from builder
COPY --from=builder /src/zig-out/bin/jake /usr/local/bin/jake

# Set working directory
WORKDIR /work

# Default entrypoint
ENTRYPOINT ["jake"]

# Show help by default
CMD ["--help"]
