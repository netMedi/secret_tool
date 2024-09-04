#!/bin/sh
CONTAINER_TOOL=podman
SRC_IN=./src/secret_tool.ts
BIN_OUT=./dist/secret_tool

NODE_ENV=production

command_line="bun install && \
  bun build '$SRC_IN' --compile --minify --sourcemap --outfile '$BIN_OUT'"

if command -v bun > /dev/null 2>&1; then
  sh -c "$command_line" \
    || exit 1
else
  $CONTAINER_TOOL run --rm -v $(pwd):/app -w /app oven/bun:alpine \
    sh -c "$command_line" \
      || exit 1
fi

chmod +x "$BIN_OUT"
