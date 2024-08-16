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
  update)
    ### perform update from git
    git -C "$script_dir" stash > /dev/null # this may produce stashes, maybe reset instead?

    [ -n "$VERSION" ] && {
      git -C "$script_dir" fetch --tags > /dev/null
      if [ "$VERSION" = "stable" ] || [ "$VERSION" = "latest" ]; then
        VERSION=$(git ls-remote --tags origin | cut --delimiter='/' --fields=3 | sort -r | grep "^v" | head -n 1)
      fi
      git -C "$script_dir" checkout "$VERSION" > /dev/null
    } || {
      git -C "$script_dir" checkout main > /dev/null # switch to main branch for update
    }
    git -C "$script_dir" pull > /dev/null
    echo

    "$script_dir/secret_tool.sh" --version
    exit 0
    ;;

  install)
    echo '[INFO] Trying to log in to 1password...'
      op whoami > /dev/null 2>&1 \
        || eval "$(op signin --account netmedi)"

    token_name='GITHUB_TOKEN'
    if $(op read "op://Employee/$token_name/credential" 2> /dev/null | wc -l | grep -q 0); then
      echo 'Create Github token: https://github.com/settings/tokens'
      printf 'Enter your GitHub [read:packages] token: '
      read -r token \
        && sh -c "op item create \
          --vault Private \
          --title '$token_name' \
          --tags guthub,secret_tool \
          --category 'API Credential' \
            'credential=$token' \
            'expires=2999-12-31' \
        " > /dev/null \
        || echo "[ERROR] Failed to create '$token_name' in 1password"
    else
      echo "[INFO] '$token_name' already exists in 1password"
    fi

    ### create symlink if missing
    command -v secret_tool > /dev/null \
      && {
        echo '[INFO] Secret tool is already symlinked'
        secret_tool --version > /dev/null 2>&1 && exit 0
      }

    echo 'Creating global secret_tool symlink'
    sudo sh -c "mkdir -p $SYMLINK_DIR; ln -sf '$script_dir/secret_tool.sh' '$SYMLINK_DIR/secret_tool' && chmod +x $SYMLINK_DIR/secret_tool" \
      && echo '[DONE] Secret tool has been installed. You may need to restart terminal, if the "secret_tool" command is not immediately available' \
      || echo '[ERROR] Failed to install secret tool'
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
  test)
    ### self-test; also accepts custom maps (consider making the tests more universal)
    DEBUG=${DEBUG:-0}
    errors=0

    echo "Running secret_tool's self-tests"
    echo

    export FILE_NAME_BASE="$script_dir/tests/.env."
    export SECRET_MAP="${SECRET_MAP:-$script_dir/tests/secret_map.yml}"
    export SKIP_OP_MARKER="$script_dir/tests/.env.SKIP_OP_MARKER"
    rm "$SKIP_OP_MARKER" 2> /dev/null

    SKIP_OP_MARKER_WRITE=1 \
    TEST_VAR_LOCAL_OVERRIDE=overridden \
      "$script_dir/secret_tool.sh" \
        --all

    if [ "$SKIP_OP_USE" = "1" ] || [ -f "$SKIP_OP_MARKER" ]; then
      echo '[DEBUG] Skipping 1password tests'
    fi

    export SKIP_HEADERS_USE=1
    export VERBOSITY=0
    export SKIP_OP_USE=1

    # configmap dump with nested array
    FORMAT=json \
      "$script_dir/secret_tool.sh" \
        'nested_array'
    FORMAT=yml \
      "$script_dir/secret_tool.sh" \
        'nested_array'

    export SECRET_MAP=''

    # configmap generation (express command)
    FORMAT=json \
      "$script_dir/secret_tool.sh" -- "$script_dir/tests/configmap.env" > "${FILE_NAME_BASE}configmap.json"
    FORMAT=yml \
      "$script_dir/secret_tool.sh" -- "$script_dir/tests/configmap.env" > "${FILE_NAME_BASE}configmap.yml"

    # --- beginning of tests ---

    # verify that secret_tool is available in PATH
    if (command -v secret_tool > /dev/null); then
      echo '[OK] secret_tool is available in PATH'
    else
      echo '[ERROR] secret_tool is NOT available in PATH'
      errors=$((errors + 1))
    fi

    # verify that dotenvx is installed globally
    dotenvx_version=$(npm list -g | grep @dotenvx/dotenvx | cut -d'@' -f2-)
    if [ -n "$dotenvx_version" ]; then
      echo "[OK] Dotenvx is installed globally: $dotenvx_version"
    else
      echo '[ERROR] Dotenvx is NOT installed globally'
      errors=$((errors + 1))
    fi

    # verify that correct yq is installed
    yq_version=$(yq --version | grep mikefarah/yq)
    if [ -n "$yq_version" ]; then
      echo "[OK] YQ is installed correctly"
    else
      echo '[ERROR] YQ is NOT installed correctly'
      errors=$((errors + 1))
    fi

    # local env override
    if (grep -q "^TEST_VAR_LOCAL_OVERRIDE='overridden'" "${FILE_NAME_BASE}simple"); then
      echo '[OK] Locally overridden value was used'
    else
      echo '[ERROR] Locally overridden value was ignored'
      errors=$((errors + 1))
    fi

    # simple number
    if (grep -q ^TEST_VAR_NUMBER "${FILE_NAME_BASE}simple"); then
      echo '[OK] Numeric value is present'
    else
      echo '[ERROR] Numeric value is missing'
      errors=$((errors + 1))
    fi

    # simple string
    if (grep -q ^TEST_VAR_STRING "${FILE_NAME_BASE}simple"); then
      echo '[OK] String value is present'
    else
      echo '[ERROR] String value is missing'
      errors=$((errors + 1))
    fi

    # verify base profile values has been inherited
    if (grep -q ^TEST_VAR_INHERITANCE_1=1 "${FILE_NAME_BASE}inherit2"); then
      echo '[OK] YAML inheritance test passed'
    else
      echo '[ERROR] YAML inheritance test failed'
      errors=$((errors + 1))
    fi

    # verify "nested_array" profile: JSON
    if cmp -s "$script_dir/tests/validator.env.nested_array.json" "${FILE_NAME_BASE}nested_array.json"; then
      echo '[OK] Nested array generated correctly (JSON)'
    else
      echo '[ERROR] Nested array generated with errors (JSON)'
      errors=$((errors + 1))
    fi

    # verify "nested_array" profile: YAML
    if cmp -s "$script_dir/tests/validator.env.nested_array.yml" "${FILE_NAME_BASE}nested_array.yml"; then
      echo '[OK] Nested array generated correctly (YAML)'
    else
      echo '[ERROR] Nested array generated with errors (YAML)'
      errors=$((errors + 1))
    fi

    # verify configmap generation from express command: JSON
    if cmp -s "$script_dir/tests/validator.env.configmap.json" "${FILE_NAME_BASE}configmap.json"; then
      echo '[OK] JSON configmap generated correctly'
    else
      echo '[ERROR] JSON configmap generated with errors'
      errors=$((errors + 1))
    fi

    # verify configmap generation from express command: YAML
    if cmp -s "$script_dir/tests/validator.env.configmap.yml" "${FILE_NAME_BASE}configmap.yml"; then
      echo '[OK] YAML configmap generated correctly'
    else
      echo '[ERROR] YAML configmap generated with errors'
      errors=$((errors + 1))
    fi

    # verify 1password integration is working
    if [ -f "$SKIP_OP_MARKER" ]; then
      echo '[INFO] 1password reference is missing (skipped)'
    else
      if (grep -q ^TEST_VAR_1PASSWORD_REF "${FILE_NAME_BASE}simple"); then
        echo '[OK] 1password reference is present'
      else
        echo '[ERROR] 1password reference is missing'
        errors=$((errors + 1))
      fi
    fi

    # verify 1password integration is working
    if [ -f "$SKIP_OP_MARKER" ]; then
      echo '[INFO] 1password reference is missing (skipped)'
    else
      if (grep -q ^TEST_VAR_1PASSWORD_REF "${FILE_NAME_BASE}simple"); then
        echo '[OK] GITHUB_TOKEN (1password) is present'
      else
        echo '[ERROR] GITHUB_TOKEN (1password) is missing'
        echo '  Refer to installation instructions:'
        echo '    https://github.com/netMedi/Holvikaari/blob/master/docs/holvikaari-dev-overview.md#installation'
        errors=$((errors + 1))
      fi
    fi

    # --- end of tests ---

    echo
    "$script_dir/secret_tool.sh" --version
    echo

    # clean up unless debugging is enabled
    stty -echo
    printf '[ Press any key to clean up and exit... ]'
    char=$(dd bs=1 count=1 2>/dev/null)
    stty echo
    printf "\n"

    [ "$DEBUG" = "0" ] && rm "$FILE_NAME_BASE"*
    [ "$errors" -eq "0" ] && exit 0 || exit 1
    ;;
  *)
    ### help
    echo "$help_text" | head -n -1 | tail -n +2
    ;;
esac
