#!/bin/sh
# prepare secret_tool's dependencies
command -v op > /dev/null 2>&1 || {
  echo "[ERROR] op is not installed. Please install it from https://1password.com/downloads/command-line/."
}

# check that either bun, docker, or podman is installed
if ! command -v bun > /dev/null 2>&1 \
  && ! command -v docker > /dev/null 2>&1 \
  && ! command -v podman > /dev/null 2>&1
then
  echo "[ERROR] No executor is present. Either bun, docker, or podman must be installed."
fi
