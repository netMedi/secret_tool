#!/bin/sh

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

help_text="
  Script: secret_utils.sh
  Purpose: Configuration utils for secret_tool

  Usage: [OVERRIDES] ./secret_utils.sh [ROUTINE_NAME]
  (if any dashed arguments are present, all other arguments are ignored)
    ./secret_utils.sh install   # create secret_tool's symlink
    ./secret_utils.sh uninstall # delete secret_tool's symlink
    ./secret_utils.sh test      # verify secret_tool's functionality
    ./secret_utils.sh update    # perform secret_tool's update
    ./secret_utils.sh help      # show this help text
"

routine=$1

actual_path=$(readlink -f "$0")
script_dir=$(dirname "$actual_path")

SYMLINK_DIR=${SYMLINK_DIR:-/usr/local/bin}

case $routine in
  test)
    ### self-test; also accepts custom maps (consider making the tests more universal)
    DEBUG=${DEBUG:-0}
    errors=0

    echo "Running secret_tool's self-tests"
    echo

    if [ "$SKIP_OP_USE" = "1" ]; then
      echo '[DEBUG] Skipping 1password tests'
    else
      echo '[INFO] Trying to log in to 1password...'
      op whoami > /dev/null 2>&1 \
        || eval "$(op signin --account netmedi)"
    fi

    export FILE_NAME_BASE="$script_dir/tests/.env"
    SECRET_MAP="${SECRET_MAP:-$script_dir/tests/secret_map.yml}"  TEST_VAR_LOCAL_OVERRIDE=overridden "$script_dir/secret_tool.sh" 'simple' 'inherit2'

    FORMAT=json "$script_dir/secret_tool.sh" -- "$script_dir/tests/configmap.env" > "$FILE_NAME_BASE.configmap.json"

    FORMAT=yml "$script_dir/secret_tool.sh" -- "$script_dir/tests/configmap.env" > "$FILE_NAME_BASE.configmap.yml"

    dotenvx_version=$(npm list -g | grep @dotenvx/dotenvx | cut -d'@' -f2-)
    if [ -n "$dotenvx_version" ]; then
      echo "[OK] Dotenvx is installed globally: $dotenvx_version"
    else
      echo '[ERROR] Dotenvx is NOT installed globally'
      errors=$((errors + 1))
    fi

    # local env override
    if (grep -q "^TEST_VAR_LOCAL_OVERRIDE='overridden'" "$FILE_NAME_BASE.simple"); then
      echo '[OK] Locally overridden value was used'
    else
      echo '[ERROR] Locally overridden value was ignored'
      errors=$((errors + 1))
    fi

    # simple number
    if (grep -q ^TEST_VAR_NUMBER "$FILE_NAME_BASE.simple"); then
      echo '[OK] Numeric value is present'
    else
      echo '[ERROR] Numeric value is missing'
      errors=$((errors + 1))
    fi

    # simple string
    if (grep -q ^TEST_VAR_STRING "$FILE_NAME_BASE.simple"); then
      echo '[OK] String value is present'
    else
      echo '[ERROR] String value is missing'
      errors=$((errors + 1))
    fi

    # verify base profile values has been inherited
    if (grep -q ^TEST_VAR_INHERITANCE_1=1 "$FILE_NAME_BASE.inherit2"); then
      echo '[OK] YAML inheritance test passed'
    else
      echo '[ERROR] YAML inheritance test failed'
      errors=$((errors + 1))
    fi

    # verify 1password integration is working
    if [ "$SKIP_OP_USE" = "1" ]; then
      echo '[INFO] 1password reference is missing (skipped)'
    else
      if (grep -q ^TEST_VAR_1PASSWORD_REF "$FILE_NAME_BASE.simple"); then
        echo '[OK] 1password reference is present'
      else
        echo '[ERROR] 1password reference is missing'
        errors=$((errors + 1))
      fi
    fi

    # verify yq is working (configmap generation)
    if cmp -s "$script_dir/tests/validator.env.configmap.json" "$FILE_NAME_BASE.configmap.json"; then
      echo '[OK] JSON configmap generated correctly'
    else
      echo '[ERROR] JSON configmap generated with errors'
      [ "$DEBUG" != "0" ] && diff "$script_dir/tests/validator.env.configmap.json" "$FILE_NAME_BASE.configmap.json"
    fi

    if cmp -s "$script_dir/tests/validator.env.configmap.yml" "$FILE_NAME_BASE.configmap.yml"; then
      echo '[OK] YAML configmap generated correctly'
    else
      echo '[ERROR] YAML configmap generated with errors'
      [ "$DEBUG" != "0" ] && diff "$script_dir/tests/validator.env.configmap.yml" "$FILE_NAME_BASE.configmap.yml"
    fi

    # verify that secret_tool is available in PATH
    if (command -v secret_tool > /dev/null); then
      echo '[OK] secret_tool is available in PATH'
    else
      echo '[ERROR] secret_tool is NOT available in PATH'
      errors=$((errors + 1))
    fi

    echo
    "$script_dir/secret_tool.sh" --version

    # clean up unless debugging is enabled
    [ "$DEBUG" = "0" ] && rm "$FILE_NAME_BASE"*
    [ "$errors" -eq "0" ] && exit 0 || exit 1
    ;;

  update)
    ### perform update from git
    git -C "$script_dir" stash > /dev/null # this may produce stashes, maybe reset instead?
    git -C "$script_dir" checkout main > /dev/null # switch to main branch for update
    git -C "$script_dir" pull
    ;;

  install)
    ### create symlink if missing
    command -v secret_tool > /dev/null && echo '[INFO] Secret tool is already symlinked' && exit 0

    echo 'Creating global secret_tool symlink'
    sudo sh -c "mkdir -p $SYMLINK_DIR; ln -s $script_dir/secret_tool.sh $SYMLINK_DIR/secret_tool && chmod +x $SYMLINK_DIR/secret_tool" && echo '[DONE] Secret tool has been installed. You may need to restart terminal, if the "secret_tool" command is not immediately available' || echo '[ERROR] Failed to install secret tool'
    ;;
  uninstall)
    ### remove symlink if present
    symlink_path=$(command -v secret_tool 2> /dev/null)
    if [ -z "$symlink_path" ]; then
      echo '[INFO] Secret tool is not symlinked' && exit 0
    fi

    echo 'Removing global secret_tool symlink'
    sudo rm "${SYMLINK_DIR:-/usr/local/bin}/secret_tool" && echo '[DONE] Secret tool has been uninstalled' || echo '[ERROR] Failed to uninstall secret tool'
    ;;

  *)
    ### help
    echo "$help_text" | head -n -1 | tail -n +2
    ;;
esac
