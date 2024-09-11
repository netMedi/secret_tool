#!/bin/sh
# run secret_tool from source without compiling it
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-.}
CONTAINER_TOOL=${CONTAINER_TOOL:-podman}
CONTAINER_FILE_PERMISSIONS=${CONTAINER_FILE_PERMISSIONS:-z}
src_in=$SECRET_TOOL_DIR_SRC/src/secret_tool.ts

if command -v bun > /dev/null 2>&1; then
  echo '  [INFO] Using bun directly'
  bun_runner=bun
else
  echo "  [INFO] Running from a ${CONTAINER_TOOL} container"

  var_dump=$(printenv | while IFS='=' read -r name value; do
    # cleaning up some stuff (because variables are unquoted and that may cause errors)
    if echo "$name" | grep -Eq '^[a-zA-Z_][a-zA-Z0-9_]*$' && echo "$value" | grep -Eq '^[a-zA-Z0-9_@%+=:,/.-]*$'; then
      [ -n "$value" ] && echo " -e $name=$value"
    fi
  done)

  bun_runner="$CONTAINER_TOOL run \
    $var_dump \
      --rm -it -v $(pwd)/:/app:$CONTAINER_FILE_PERMISSIONS -w /app oven/bun:alpine bun"
fi

$bun_runner $src_in $@