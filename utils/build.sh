#!/bin/sh
# build secret_tool's binary
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-$(realpath .)}
CONTAINER_TOOL=${CONTAINER_TOOL:-podman}
CONTAINER_FILE_PERMISSIONS=${CONTAINER_FILE_PERMISSIONS:-z}
src_in=$SECRET_TOOL_DIR_SRC/src/secret_tool.ts
bin_out=$SECRET_TOOL_DIR_SRC/dist/secret_tool

NODE_ENV=production

command_line="bun install &> /dev/null && \
  bun build '$src_in' --compile --minify --sourcemap --outfile '$bin_out'"

if command -v bun > /dev/null 2>&1; then
  sh -c "$command_line" \
    || exit 1
else
  $CONTAINER_TOOL run --rm -v $(pwd)/:/app:$CONTAINER_FILE_PERMISSIONS -w /app oven/bun:alpine \
    sh -c "$command_line" \
      || exit 1
fi

if [ -f "$bin_out" ]; then
  chmod +wx "$bin_out"
else
  echo '[ERROR] Failed to make binary'
  exit 1
fi
