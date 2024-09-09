#!/bin/sh
# build secret_tool's binary
STOOL_ROOT_DIR=${STOOL_ROOT_DIR:-.}
SRC_IN=$STOOL_ROOT_DIR/src/secret_tool.ts
BIN_OUT=$STOOL_ROOT_DIR/dist/secret_tool

NODE_ENV=production

command_line="bun install &> /dev/null && \
  bun build '$SRC_IN' --compile --minify --sourcemap --outfile '$BIN_OUT.tmp'"

if command -v bun > /dev/null 2>&1; then
  sh -c "$command_line" \
    || exit 1
else
  ${CONTAINER_TOOL:-docker} run --rm -v $(pwd):/app -w /app oven/bun:alpine \
    sh -c "$command_line" \
      || exit 1
fi

if [ -f "$BIN_OUT.tmp" ]; then
  mv -f "$BIN_OUT.tmp" "$BIN_OUT"
  chmod +wx "$BIN_OUT"
else
  echo '[ERROR] Failed to make binary'
  exit 1
fi
