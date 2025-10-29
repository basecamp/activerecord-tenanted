FROM ghcr.io/rails/devcontainer/images/ruby:3.3.5

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends libmariadb-dev-compat \
  && rm -rf /var/lib/apt/lists/*
