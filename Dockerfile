# syntax=docker/dockerfile:1

# Set from .ruby-version, the single Ruby pin: by ontoportal_testkit for the
# test image, by docker-image.yml for the production one
ARG OPTK_RUBY_VERSION
ARG DISTRO_NAME=slim-bookworm

# OS, Java, Raptor and gems shared by both images, so CI tests the runtime we ship
FROM ruby:${OPTK_RUBY_VERSION}-${DISTRO_NAME} AS base

WORKDIR /srv/ontoportal/ontologies_api

# Set environment variables
ENV BUNDLE_PATH=/srv/ontoportal/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=5 \
    RAILS_ENV=production \
    DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        openjdk-17-jre-headless \
        raptor2-utils \
        wait-for-it \
        libraptor2-dev \
        build-essential \
         libxml2 \
         libxslt-dev \
         libmariadb-dev \
         git \
         curl \
         libffi-dev \
         file \
         pandoc \
     pkg-config && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN gem install bundler

COPY Gemfile* ./

# Install dependencies
RUN bundle install --jobs ${BUNDLE_JOBS} --retry ${BUNDLE_RETRY}

# Built by ontoportal_testkit (target: test in .ontoportal-testkit.yml).
# /app because the testkit mounts coverage at /app/coverage; gems stay in BUNDLE_PATH
FROM base AS test

WORKDIR /app

# Slice size the old CI ran with (config default: 500); small slices keep goo's sliced loading exercised
ENV GOO_SLICES=100

COPY . .

CMD ["bundle", "exec", "rake"]

# Published agroportal/ontologies_api image. Last, so builds without a target get it
FROM base AS production

# Copy application code
COPY . .

# Copy config files
RUN cp config/environments/config.rb.sample config/environments/development.rb && \
    cp config/environments/config.rb.sample config/environments/production.rb

# Expose port
EXPOSE 9393

# Start command
CMD ["bundle", "exec", "rackup", "-p", "9393", "--host", "0.0.0.0"]
