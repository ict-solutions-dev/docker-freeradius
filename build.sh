#!/bin/bash
#
# build.sh - Local builder for FreeRadius Docker image
#
# Usage:
#   ./build.sh                                        # Build image with default version (latest)
#   ./build.sh --build-arg FREERADIUS_VERSION=latest  # Build image for specific version
#   ./build.sh --no-cache                             # Build without cache
#   ./build.sh --build-arg ARG=VALUE                  # Pass additional build args to Docker
#
# The image will be tagged as:
#   ict-solutions-dev/freeradius:edge-freeradius-<VERSION>
#
# Example:
#   ./build.sh --build-arg FREERADIUS_VERSION=3.2.8
#   # Builds ict-solutions-dev/freeradius:edge-freeradius-3.2.8
#
# Author: Jozef Rebjak / ICT Solutions

IMAGE_NAME="ict-solutions-dev/freeradius"
DOCKERFILE="Dockerfile"
CONTEXT="."

# Optionally set version via argument, default to latest
FREERADIUS_VERSION=${1:-latest}
NO_CACHE=""
BUILD_ARGS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    --build-arg)
      if [[ $2 == DNSDIST_VERSION=* ]]; then
        DNSDIST_VERSION="${2#DNSDIST_VERSION=}"
      else
        BUILD_ARGS+=" --build-arg $2"
      fi
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

TAG="edge-${FREERADIUS_VERSION}"

echo "Building $IMAGE_NAME:$TAG with FREERADIUS_VERSION=$FREERADIUS_VERSION"
docker build $NO_CACHE --build-arg FREERADIUS_VERSION=$FREERADIUS_VERSION $BUILD_ARGS -f $DOCKERFILE -t $IMAGE_NAME:$TAG $CONTEXT
