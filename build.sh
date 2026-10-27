#!/bin/bash
set -e

DOCKER_RUN_IMAGE=nagios

# Pull latest base image and build with current Dockerfile defaults (or pass extra docker build args)
docker build --pull -t "${DOCKER_RUN_IMAGE}" "$@" .

docker images
docker run -d --rm --name "${DOCKER_RUN_IMAGE}" -p 8080:80 -t "${DOCKER_RUN_IMAGE}"
