# ==========================================
# Stage 1: Build Stage
# ==========================================
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package manifests first for layer caching
COPY package*.json ./

# Install dependencies cleanly
RUN npm ci --silent

# Copy application source
COPY . .

# Build production static bundle (dist/ or build/)
RUN npm run build

# ==========================================
# Stage 2: Production Runtime Stage (Minimal & Secure)
# ==========================================
FROM nginx:1.27-alpine-slim AS production

# Remove default nginx static assets and config
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/default.conf

# Install curl for lightweight healthcheck & remove apk cache
RUN apk add --no-cache curl && rm -rf /var/cache/apk/*

# Copy custom non-root Nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create non-root user and group (appuser:appgroup)
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Adjust permissions for non-root Nginx execution
RUN chown -R appuser:appgroup /usr/share/nginx/html /var/cache/nginx /var/log/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R appuser:appgroup /var/run/nginx.pid

# Copy only built artifacts from builder stage
# Supports Vite (dist) - if CRA (build), update source path to /app/build
COPY --from=builder --chown=appuser:appgroup /app/dist /usr/share/nginx/html

# Switch to non-root user
USER appuser

# Expose application port (unprivileged port 8080 or 3000)
EXPOSE 3000

# Container Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Run Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
