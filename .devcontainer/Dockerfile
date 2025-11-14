FROM ghcr.io/rails/devcontainer/images/ruby:3.3.5

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libmariadb-dev-compat \
    chromium \
    chromium-driver \
    libnss3 \
    libfontconfig1 \
  && rm -rf /var/lib/apt/lists/*

ENV CHROME_BIN=/usr/bin/chromium
ENV CHROMEDRIVER_PATH=/usr/bin/chromedriver
ENV SE_AVOID_STATS=true
