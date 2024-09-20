#!/bin/sh

FALLBACK=$(ps -p $$ -o comm= 2> /dev/null || cat /proc/$$/comm 2> /dev/null)
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

actual_path=$(readlink -f "$0")
script_dir=$(dirname "$actual_path")
SECRET_UTILS=${SECRET_UTILS:-$(basename "$0")}

whitelist="help"
for fn in "$script_dir"/utils/*.sh; do
  name=$(basename "$fn")
  name="${name%.*}"
  whitelist="$whitelist $name"
done

if echo "$whitelist" | grep -wq "$1"; then
  routine=$1
else
  routine='help'
fi

case $routine in
  help)
    ### help
    commands=""
    for fn in "$script_dir"/utils/*.sh; do
      name=$(basename "$fn")
      name="${name%.*}"
      commands="$commands    ${SECRET_UTILS} $name $(head -n 2 $fn | tail -n 1)\n"
    done
    commands="$commands    ${SECRET_UTILS} help # show this help text"
    printf "  Script: ${SECRET_UTILS}\n  Purpose: Configuration utils for secret_tool\n\n  Usage: [OVERRIDES] ${SECRET_UTILS} [ROUTINE_NAME]\n"
    echo "$commands" | column -t -s '#'
    ;;
  *)
    ### execute util script
    shift # discard $1
    . "$script_dir/utils/$routine.sh" $@
    ;;
esac
