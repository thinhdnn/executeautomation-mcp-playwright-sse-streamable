# Playwright automation Dockerfile for Ubuntu 24.04
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Install all Playwright browser dependencies (minimal, up-to-date for Ubuntu 24.04)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    xvfb \
    x11vnc \
    git \
    novnc \
    websockify \
    supervisor \
    libnss3 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libcups2t64 \
    libdbus-glib-1-2 \
    libdrm2 \
    libegl1 \
    libenchant-2-2 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-3-0t64 \
    libgtk-4-1 \
    libharfbuzz-icu0 \
    libnotify4 \
    libopus0 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libsecret-1-0 \
    libvulkan1 \
    libwebp7 \
    libwebpdemux2 \
    libwoff1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxslt1.1 \
    libasound2t64 \
    libatspi2.0-0t64 \
    libgudev-1.0-0 \
    libhyphen0 \
    libcairo2 \
    libcairo-gobject2 \
    libgles2 \
    libgraphene-1.0-0 \
    libmanette-0.2-0 \
    libnotify4 \
    libnspr4 \
    libvpx9 \
    libavif16 \
    libwebpmux3 \
    libevent-2.1-7t64 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-gl \
    gstreamer1.0-alsa \
    gstreamer1.0-pulseaudio \
    flite \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 20 and update npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest typescript

# Copy app code and lockfile
COPY mcp-playwright/dist/ ./dist/
COPY mcp-playwright/package.json ./
COPY mcp-playwright/package-lock.json ./

COPY scripts/supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# Install only production dependencies
RUN npm install --only=production --ignore-scripts

# Install Playwright browsers for appuser
RUN npx playwright install

EXPOSE 9300
EXPOSE 5900 6080
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]