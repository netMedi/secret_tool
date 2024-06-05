#!/usr/bin/env bash
: "
  Script: secret_utils.sh
  Purpose: Configuration utils for secret_tool

  Usage: [OVERRIDES] ./secret_utils.sh [ROUTINE_NAME]
  (if any dashed arguments are present, all other arguments are ignored)
    ./secret_utils.sh install   # create secret_tool's symlink
    ./secret_utils.sh uninstall # delete secret_tool's symlink
    ./secret_utils.sh test      # verify secret_tool's functionality
    ./secret_utils.sh update    # perform secret_tool's update
"
HELP_LINES=${LINENO} # all lines above this one are considered help text

# Prerequisites:
declare -A command_from_package=(
  ['1password']='1password'
  ['git']='git'
  ['op']='1password-cli'
  ['bash']='bash'
  ['yq']='yq'
)

routine=$1

actual_path=$(readlink -f "${BASH_SOURCE[0]}")
script_dir=$(dirname "$actual_path")

case $routine in
  test)
    ### self-test; also accepts custom maps (consider making the tests more universal)
    DEBUG=${DEBUG:-0}

    export FILE_NAME_BASE=$script_dir/.env
    export SECRET_MAP=${SECRET_MAP:-$script_dir/secret_map.sample.yml}
    $script_dir/secret_tool.sh sample

    # simple number
    cat $script_dir/.env.sample | grep ^TEST_VAR_NUMBER | wc -l | grep 1 &> /dev/null && echo '[OK] Numeric value is present' || echo '[ERROR] Numeric value is missing'

    # simple string
    cat $script_dir/.env.sample | grep ^TEST_VAR_STRING | wc -l | grep 1 &> /dev/null && echo '[OK] String value is present' || echo '[ERROR] String value is missing'

    # verify base profile values has been inherited
    cat $script_dir/.env.sample | grep ^TEST_VAR_YAML_INHERITANCE_PASSED | wc -l | grep 1 &> /dev/null && echo '[OK] YAML inheritance test passed' || echo '[ERROR] YAML inheritance test failed'

    # verify varible expansion is working
    [ $(dotenvx run -f $script_dir/.env.sample -- sh -c '\
      echo "$TEST_VAR_INTERPOLATION"; \
    ' | wc -l) -gt 1 ] && echo '[OK] Interpolation is working' || echo '[ERROR] Interpolation is not working'

    # verify 1password integration is working
    cat $script_dir/.env.sample | grep ^TEST_VAR_1PASSWORD_REF | wc -l | grep 1 &> /dev/null && echo '[OK] 1password reference is present' || echo '[ERROR] 1password reference is missing'

    # clean up unless debugging is enabled
    [ "$DEBUG" = "0" ] && rm $script_dir/.env.sample
    ;;

  update)
    ### perform update from git
    git -C $script_dir stash &> /dev/null # this may produce stashes, maybe reset instead?
    git -C $script_dir checkout main &> /dev/null # switch to main branch for update
    git -C $script_dir pull
    ;;

  install)
    ### create symlink if missing
    command -v secret_tool &> /dev/null && echo '[INFO] Secret tool is already symlinked' && exit 0

    echo 'Creating global secret_tool symlink'
    sudo sh -c "ln -s $script_dir/secret_tool.sh ${SYMLINK_DIR:-/usr/local/bin}/secret_tool && chmod +x ${SYMLINK_DIR:-/usr/local/bin}/secret_tool" && echo '[DONE] Secret tool has been installed. Restart terminal to recognise changes' || echo '[ERROR] Failed to install secret tool'
    ;;
  uninstall)
    ### remove symlink if present
    symlink_path=$(command -v secret_tool 2> /dev/null)
    if [ -z "$symlink_path" ]; then
      echo '[INFO] Secret tool is not symlinked' && exit 0
    fi

    echo 'Removing global secret_tool symlink'
    sudo rm ${SYMLINK_DIR:-/usr/local/bin}/secret_tool && echo '[DONE] Secret tool has been uninstalled' || echo '[ERROR] Failed to uninstall secret tool'
    ;;

  *)
    ### help
    cat "$actual_path" | head -n $HELP_LINES | tail -n +3 | head -n -2
    ;;
esac
