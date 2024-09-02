#!/bin/sh
CONTAINER_TOOL=podman
SRC_IN=./src/secret_tool.ts

if command -v bun > /dev/null 2>&1; then
  bun_runner=bun
else
  bun_runner="$CONTAINER_TOOL run \
    -e FORMAT \
    -e OUTPUT_PATH \
    -e SECRET_MAP \
      --rm -it -v $(pwd):/app -w /app oven/bun:alpine bun"
fi

$bun_runner $SRC_IN $@
