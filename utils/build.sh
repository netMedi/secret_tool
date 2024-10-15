#!/bin/sh
# build secret_tool's binary
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-$(realpath .)}
CONTAINER_TOOL=${CONTAINER_TOOL:-docker}
CONTAINER_FILE_PERMISSIONS=${CONTAINER_FILE_PERMISSIONS:-ro}
QUIET=${QUIET:-0}
src_in=$SECRET_TOOL_DIR_SRC/src/secret_tool.ts
bin_out=$SECRET_TOOL_DIR_SRC/dist/secret_tool

NODE_ENV=production

# remove the binary if it exists
[ -f "$bin_out" ] && rm "$bin_out"

# if -q argument is present, set QUIET=1
[ "$1" = "-q" ] || [ "$1" = "--quiet" ] && QUIET=1

bun_builder_cmd="bun install &> /dev/null && \
  bun build '$src_in' --compile --define 'COMPILE_TIME_DATE=\"$(date)\"' --define 'COMPILE_TIME_DIR_SRC=\"${SECRET_TOOL_DIR_SRC}\"' --define \"BUN_VERSION='\$(bun --version) (builder: ${USER}@\$(hostname))'\" --minify --sourcemap --outfile '$bin_out'"

if command -v bun > /dev/null 2>&1; then
  echo '  [INFO] Building with bun installed locally ...'
  sh -c "cd $SECRET_TOOL_DIR_SRC; $bun_builder_cmd" \
    || exit 1
else
  echo "  [INFO] Building with bun from a ${CONTAINER_TOOL} container ..."
  $CONTAINER_TOOL run -h "${CONTAINER_TOOL}-bun-builder" -u ${USER} \
    --rm -v $SECRET_TOOL_DIR_SRC/:/$SECRET_TOOL_DIR_SRC/:$CONTAINER_FILE_PERMISSIONS \
    -w /$SECRET_TOOL_DIR_SRC/ oven/bun:alpine \
    sh -c "$bun_builder_cmd" \
      || exit 1
fi

if [ -f "$bin_out" ]; then
  chmod +wx "$bin_out"
  echo "  [INFO] Binary has been built: $bin_out"

  # show the version
  if [ "$QUIET" = "0" ]; then
    echo
    echo 'Compiled binary info:'
    $bin_out --version
  fi
else
  echo '  [ERROR] Binary build failed'
  exit 1
fi
