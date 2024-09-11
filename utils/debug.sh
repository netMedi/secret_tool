#!/bin/sh
# try secret_tool before installing
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-.}
CONTAINER_TOOL=${CONTAINER_TOOL:-podman}
src_in=$SECRET_TOOL_DIR_SRC/src/secret_tool.ts

if command -v bun > /dev/null 2>&1; then
  bun_runner=bun
else
  bun_runner="$CONTAINER_TOOL run \
    $(env | while read -r line; do echo "--env $line"; done) \
      --rm -it -v $(pwd):/app -w /app oven/bun:alpine bun"
fi

$bun_runner $src_in $@
