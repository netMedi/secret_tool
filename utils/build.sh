#!/bin/sh
# build secret_tool's binary

FALLBACK=$(ps -p $$ -o comm=)

[ -z "SHELL_NAME" ] && SHELL_NAME=$([ -f "/proc/$$/exe" ] && basename "$(readlink -f /proc/$$/exe)" || echo "$FALLBACK")

if [ -z "$BEST_CHOICE" ]; then
	if [ "$SHELL_NAME" = "dash" ]; then
		BEST_CHOICE=1
	elif command -v dash >/dev/null 2>&1; then
		SHELL_NAME="dash"
	elif [ "$SHELL_NAME" = "ash" ]; then
		:
	elif command -v ash >/dev/null 2>&1; then
		SHELL_NAME="ash"
	elif [ "$POSIXLY_CORRECT" = "1" ]; then
		BEST_CHOICE=1
	fi

	# restart script with a POSIX compliant shell
	[ "$BEST_CHOICE" = "1" ] || {
	  export POSIXLY_CORRECT=1
  	export SHELL_NAME
	  export BEST_CHOICE=1

	  exec $SHELL_NAME "$0" "$@"
	}
fi
# --- SHELLCHECK BELOW ---

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

bun_builder_cmd="bun install && \
  bun build '$src_in' --compile --define 'COMPILE_TIME_DATE=\"$(date)\"' --define 'COMPILE_TIME_DIR_SRC=\"${SECRET_TOOL_DIR_SRC}\"' --define \"BUN_VERSION='\$(bun --version) (builder: ${USER}@\$(hostname))'\" --minify --sourcemap --outfile '$bin_out'"

if [ "$CONTAINER_BUILD" = "1" ]; then
  echo "  [INFO] Building with bun from a ${CONTAINER_TOOL} container ..."
  $CONTAINER_TOOL run -h "${CONTAINER_TOOL}-bun-builder" \
    --rm -v $SECRET_TOOL_DIR_SRC/:/$SECRET_TOOL_DIR_SRC/:$CONTAINER_FILE_PERMISSIONS \
    -w /$SECRET_TOOL_DIR_SRC/ oven/bun:alpine \
    sh -c "$bun_builder_cmd" \
      || exit 1
elif command -v bun > /dev/null 2>&1; then
  echo '  [INFO] Building with bun installed locally ...'
  sh -c "cd $SECRET_TOOL_DIR_SRC; $bun_builder_cmd" \
    || exit 1
else
  echo '  [ERROR] bun could not be detected. If you just installed it, please, restart your shell (close terminal and open a fresh one) and try again.'
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
