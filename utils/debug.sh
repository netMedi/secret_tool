#!/bin/sh
# try secret_tool before installing
STOOL_ROOT_DIR=${STOOL_ROOT_DIR:-.}
CONTAINER_TOOL=${CONTAINER_TOOL:-podman}
SRC_IN=$STOOL_ROOT_DIR/src/secret_tool.ts

if command -v bun > /dev/null 2>&1; then
  bun_runner=bun
else
  bun_runner="$CONTAINER_TOOL run \
    $(env | while read -r line; do echo "--env $line"; done) \
      --rm -it -v $(pwd):/app -w /app oven/bun:alpine bun"
fi

$bun_runner $SRC_IN $@
