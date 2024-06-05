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
    DEBUG=${DEBUG:-0}

    FILE_NAME_BASE=$script_dir/.env SECRET_MAP=$script_dir/secret_map.sample.yml $script_dir/secret_tool.sh sample

    cat $script_dir/.env.sample | grep ^SIMPLE_NUMERIC_VALUE | wc -l | grep 1 &> /dev/null && echo '[INFO] Numeric value is present' || echo '[ERROR] Numeric value is missing'
    cat $script_dir/.env.sample | grep ^SIMPLE_STRING_VALUE | wc -l | grep 1 &> /dev/null && echo '[INFO] String value is present' || echo '[ERROR] String value is missing'
    cat $script_dir/.env.sample | grep ^SIMPLE_YAML_TEST_PASSED | wc -l | grep 1 &> /dev/null && echo '[INFO] YAML test passed' || echo '[ERROR] YAML test failed'
    cat $script_dir/.env.sample | grep ^SIMPLE_1PASSWORD_REF | wc -l | grep 1 &> /dev/null && echo '[INFO] 1password reference is present' || echo '[ERROR] 1password reference is missing'

    [ "$DEBUG" = "0" ] && rm $script_dir/.env.sample
    ;;
  update)
    git -C $script_dir stash &> /dev/null
    git -C $script_dir checkout main &> /dev/null
    git -C $script_dir pull
    ;;

  install)
    command -v secret_tool &> /dev/null && echo '[INFO] Secret tool is already symlinked' && exit 0

    echo 'Creating global secret_tool symlink'
    sudo ln -s $script_dir/secret_tool.sh ${SYMLINK_DIR:-/usr/local/bin}/secret_tool && echo '[DONE] Secret tool has been installed' || echo '[ERROR] Failed to install secret tool'
    ;;
  uninstall)
    symlink_path=$(command -v secret_tool 2> /dev/null)
    if [ -z "$symlink_path" ]; then
      echo '[INFO] Secret tool is not symlinked' && exit 0
    fi

    echo 'Removing global secret_tool symlink'
    sudo rm ${SYMLINK_DIR:-/usr/local/bin}/secret_tool && echo '[DONE] Secret tool has been uninstalled' || echo '[ERROR] Failed to uninstall secret tool'
    ;;

  *)
    ### help or unknown
    cat "$actual_path" | head -n $HELP_LINES | tail -n +3 | head -n -2
    ;;
esac
