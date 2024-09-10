#!/bin/sh
# prepare secret_tool's dependencies
op --version > /dev/null 2>&1 || {
  echo "op is not installed. Please install it from https://1password.com/downloads/command-line/."
  exit 1
}

# check that either bun, docker, or podman is installed
if ! command -v bun > /dev/null 2>&1 \
  && ! command -v docker > /dev/null 2>&1 \
  && ! command -v podman > /dev/null 2>&1
then
  echo "Either bun, docker, or podman must be installed."
  exit 1
fi