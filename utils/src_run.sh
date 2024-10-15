#!/bin/sh
# run secret_tool from source without compiling it
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-$(realpath .)}
CONTAINER_TOOL=${CONTAINER_TOOL:-docker}
CONTAINER_FILE_PERMISSIONS=${CONTAINER_FILE_PERMISSIONS:-ro}
src_in=$SECRET_TOOL_DIR_SRC/src/secret_tool.ts

if command -v bun > /dev/null 2>&1; then
  # echo '  [INFO] Using bun installed locally ...'
  bun_runner=bun
else
  # echo "  [INFO] Using bun from a ${CONTAINER_TOOL} container ..."
  var_dump=$(printenv | while IFS='=' read -r name value; do
    # cleaning up some stuff (because variables are unquoted and that may cause errors)
    if echo "$name" | grep -Eq '^[a-zA-Z_][a-zA-Z0-9_]*$' && echo "$value" | grep -Eq '^[a-zA-Z0-9_@%+=:,/.-]*$'; then
      [ -n "$value" ] && echo " -e $name=$value"
    fi
  done)

  bun_runner="$CONTAINER_TOOL run -h '${CONTAINER_TOOL}-bun-runner' -u ${USER} \
    $var_dump \
      --rm -it -v $SECRET_TOOL_DIR_SRC/:/$SECRET_TOOL_DIR_SRC/:$CONTAINER_FILE_PERMISSIONS \
      -w /$SECRET_TOOL_DIR_SRC/ oven/bun:alpine bun"
fi

$bun_runner $src_in $@
