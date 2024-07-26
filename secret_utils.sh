#!/bin/sh
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

    export FILE_NAME_BASE="$script_dir/.env"
    export SECRET_MAP="${SECRET_MAP:-$script_dir/secret_map.sample.yml}"
    "$script_dir/secret_tool.sh" sample

    # simple number
    if (cat "$script_dir/.env.sample" | grep ^TEST_VAR_NUMBER | wc -l | grep 1 > /dev/null); then
      echo '[OK] Numeric value is present'
    else
      echo '[ERROR] Numeric value is missing'
      errors=$((errors + 1))
    fi

    # simple string
    if (cat "$script_dir/.env.sample" | grep ^TEST_VAR_STRING | wc -l | grep 1 > /dev/null); then
      echo '[OK] String value is present'
    else
      echo '[ERROR] String value is missing'
      errors=$((errors + 1))
    fi

    # verify base profile values has been inherited
    if (cat "$script_dir/.env.sample" | grep ^TEST_VAR_YAML_INHERITANCE_PASSED | wc -l | grep 1 > /dev/null); then
      echo '[OK] YAML inheritance test passed'
    else
      echo '[ERROR] YAML inheritance test failed'
      errors=$((errors + 1))
    fi

    # verify 1password integration is working
    if [ "$SKIP_OP_USE" = "1" ]; then
      echo '[INFO] 1password reference is missing (skipped)'
    else
      if (cat "$script_dir/.env.sample" | grep ^TEST_VAR_1PASSWORD_REF | wc -l | grep 1 > /dev/null); then
        echo '[OK] 1password reference is present'
      else
        echo '[ERROR] 1password reference is missing'
        errors=$((errors + 1))
      fi
    fi

    # clean up unless debugging is enabled
    [ "$DEBUG" = "0" ] && rm "$script_dir/.env.sample"
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
