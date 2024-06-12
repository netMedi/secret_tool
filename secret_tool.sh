#!/usr/bin/env bash
: '
  Script: secret_tool.sh
  Purpose: Dump secrets from 1password and secret map to .env file

  Usage: [OVERRIDES] ./secret_tool.sh [PROFILE_NAME(S)]
  (if any dashed arguments are present, all other arguments are ignored)
    ./secret_tool.sh --help                           # print help and exit
    ./secret_tool.sh --profiles                       # list all available profiles and exit (ignores all other arguments)

  Examples:
    ./secret_tool.sh staging                          # dump secrets for this profile
    ./secret_tool.sh dev test                         # dump secrets for these two profiles
    VAR123='' ./secret_tool.sh                        # ignore local override of this variable
    SECRET_MAP="~/alt-map.yml" ./secret_tool.sh test  # use this map file
    INCLUDE_BLANK=1 ./secret_tool.sh dev              # dump all, also empty values
    FILE_NAME_BASE="/tmp/.env" ./secret_tool.sh dev   # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX=".sh" ./secret_tool.sh prod          # append this to file name end (.env.prod.sh)
    PROFILES="ci test" ./secret_tool.sh               # set target profiles via variable (same as `./secret_tool.sh ci test`)
    SKIP_OP=1 ./secret_tool.sh ci                     # do not use 1password
'
HELP_LINES=${LINENO} # all lines above this one are considered help text

actual_path=$(readlink -f "${BASH_SOURCE[0]}")
script_dir=$(dirname "$actual_path")


function get_file_modified_date {
  {
    # try grabbing info from git
    file_date=$(git log -1 --pretty="format:%cI" -- $1 2> /dev/null)
    comment=$(git log -1 --pretty="commit %H" -- $1 2> /dev/null)
  } || {
    # fallback to file modification date
    file_date=$(date +'%Y-%m-%d at %H:%M:%S%:z' -r $1)
    comment="(not from git)"
  }
  echo "$file_date ($comment)"
}


if [ "$1" = "--version" ]; then
  if [ ! -f "$script_dir/.version" ]; then
    echo '[WARN] Standalone installation (version file is not available).'
    echo '0.0 (detached HEAD)'
    exit 1
  fi

  ST_VERSION="v$(cat $script_dir/.version | xargs) $(get_file_modified_date $script_dir/secret_tool.sh)" || exit 1

  ST_VERSION=${ST_VERSION/T/ at }
  echo $ST_VERSION
  exit 0
fi

if [ "$1" = "--test" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    echo '[WARN] Standalone installation (secret_utils.sh is not available). Skipping tests.'
    exit 1
  fi
  $script_dir/secret_utils.sh test || exit 1
  exit 0
fi

if [ "$1" = "--update" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    echo '[WARN] Standalone installation (secret_utils.sh is not available). Self update is not possible.'
    exit 1
  fi
  $script_dir/secret_utils.sh update || exit 1
  exit 0
fi

# BASH 4+ required, skip for now
# Prerequisites:
# declare -A command_from_package=(
#   ['1password']='1password'
#   ['op']='1password-cli'
#   ['bash']='bash'
#   ['yq']='yq'
# )

## 100% opinionated JSON only:
allowed_boolean_regexp='^(true|false)$'

## All that YAML supports (https://yaml.org/type/bool.html):
# allowed_boolean_regexp='^(y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF)$'

[[ "$*" == *"--help"* ]] && SHOW_HELP=1

SECRET_MAP=${SECRET_MAP:-./secret_map.yml}
FILE_NAME_BASE=${FILE_NAME_BASE:-./.env} # this can be also be path
FILE_POSTFIX=${FILE_POSTFIX:-''} # this can be also be file extension

if [ -n "$PROFILES" ]; then
  target_environments=$PROFILES
else
  target_environments=${@:-''}
fi

# print help (head of current file) if no arguments are provided
if [ "$SHOW_HELP" = "1" ] || [ -z "$target_environments" ]; then
  cat "${BASH_SOURCE[0]}" | head -n $HELP_LINES | tail -n +3 | sed '$d' | sed '$d'
  exit 0
fi

if [ -n "$SECRET_MAP" ] && [ ! -f "$SECRET_MAP" ]; then
  echo "[ERROR] Secret map file not found: $SECRET_MAP"
  echo "[INFO] Please, change path or submit correct value via a SECRET_MAP variable"
  exit 1
fi

if [[ "$*" == *"--profiles"* ]]; then
  yq e ".profiles | keys | .[]" $SECRET_MAP | tail -n +1 | grep -v '^--'
  exit 0
fi

if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ]; then
  export PROFILES="ci"
fi

if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ] || [ "$SKIP_OP_USE" = "1" ] || [[ "$*" == *"--help"* ]] || [[ "$*" == *"--profiles"* ]]; then
  export SKIP_OP_USE=1
else
  # BASH 4+ required, skip for now
  # verify installed packages via command presence
  # for cmnd in ${!command_from_package[@]}; do
  #   if ! command -v $cmnd &> /dev/null; then
  #     echo "[ERROR] '${command_from_package[${cmnd}]}' is required but not installed. Aborting..."
  #     exit 1
  #   fi
  # done

  # will also trigger if dev is using 1password-cli without gui
  if ! pgrep 1password &> /dev/null; then
    echo "[WARN] 1password is not running. You will get empty values for OP secrets."
  else
    # signin manually if 1password GUI is a Flatpak app
    op whoami 2> /dev/null &> /dev/null || eval $(op signin) || exit 1
    echo '[INFO] Extracting values...'
  fi
fi

for target_profile in $target_environments; do
  # verify that target profile exists
  if yq e ".profiles | keys | .[] | select(. == \"${target_profile}\" )" $SECRET_MAP | wc -l | grep "0" &> /dev/null; then
    echo "[ERROR] Profile validation failed: profile '${target_profile}' was not found in $SECRET_MAP"
    FAILED=1
  fi
done
[ "$FAILED" = "1" ] && exit 1

# BASH 4+ required, skip for now
# ensure blocks have 1 instance of each key
# function duplicates_check {
#   input_array=("$@")
#   declare -A detected_instances
#   for i in "${input_array[@]}"; do
#     if [[ -n ${detected_instances["$i"]} ]]; then # avoid duplicates (from defaults)
#       echo "[ERROR] Secret map validation failed. Duplicate keys detected: ${i}"
#       exit 1
#     fi
#     detected_instances["$i"]=1
#   done
# }

function duplicates_check {
  input_array=("$@")
  for ((i=0; i<${#input_array[@]}; i++)); do
    for ((j=i+1; j<${#input_array[@]}; j++)); do
      if [[ "${input_array[i]}" == "${input_array[j]}" ]]; then
        echo "[ERROR] Secret map validation failed. Duplicate keys detected: ${input_array[i]}"
        exit 1
      fi
    done
  done
}

# block of overridable defaults
readarray env_variables_defaults < <( yq -r ".profiles.--defaults | to_entries | .[] | .key" $SECRET_MAP )
duplicates_check "${env_variables_defaults[@]}"

for target_profile in $target_environments; do
  output_file_path="${FILE_NAME_BASE}.${target_profile}${FILE_POSTFIX}"

  # block of target environment
  readarray env_variables < <( yq -r ".profiles.$target_profile | to_entries | .[] | .key" $SECRET_MAP )
  duplicates_check "${env_variables[@]}"


  # list of all env variables sorted alphabetically
  env_variables=( ${env_variables_defaults[@]} ${env_variables[@]} )
  # declare -A skip_vars=(['<<']=1)
  clean_env=()
  for i in "${env_variables[@]}"; do
    if ! [ "$i" = '<<' ]; then
      clean_env+=("$i")
    fi
    # skip_vars["$i"]=1
  done
  readarray -td '' env_variables < <(printf '%s\0' "${clean_env[@]}" | sort -z)


  # uncomment next line for debugging
  # echo "All env variables: ${env_variables[@]}"

  SECRET_MAP_RELEASE_ISO=$(git log -1 --pretty="format:%cI (commit %H)" $SECRET_MAP 2> /dev/null || date +'%Y-%m-%d at %H:%M:%S%:z (not from git)' -r $SECRET_MAP)
  SECRET_MAP_RELEASE=${SECRET_MAP_RELEASE_ISO/T/ at }

  # headers
  echo '# Content type: environment variables and secrets' > $output_file_path
  echo "# File path: $(realpath $output_file_path)" >> $output_file_path
  echo "# Map path: $(realpath $SECRET_MAP)" >> $output_file_path
  echo "# Profile: ${target_profile}" >> $output_file_path
  echo "# Generated via secret_tool on $(date +'%Y-%m-%d at %H:%M:%S%:z')" >> $output_file_path
  echo "# Secret map release: $SECRET_MAP_RELEASE" >> $output_file_path
  echo '' >> $output_file_path


  # content itself
  for var_name in "${env_variables[@]}"; do
    # if local env variable override is present, use that
    var_value=$(echo "${!var_name}")
    if [ -n "$var_value" ]; then
      echo "# overridden from local env: $var_name" >> $output_file_path
    else
      # otherwise, use value from secret map
      var_value=$(yq e ".profiles.$target_profile.$var_name | explode(.)" $SECRET_MAP)
      if [ "$(echo $var_value | cut -c1-3)" == ":::" ] && [ "$SKIP_OP_USE" != "1" ]; then
        var_value=$(op read "$(echo $var_value | cut -c4- | xargs)" 2> /dev/null)
      fi
    fi

    # if we are including blank values, write those to file
    if [ -n "$var_value" ] || [ "$INCLUDE_BLANK" = "1" ]; then
      re_num='^[0-9]+$'
      re_yaml_bool=$allowed_boolean_regexp
      if ! [[ $var_value =~ $re_num ]] && ! [[ $var_value =~ $re_yaml_bool ]]; then
        # the strings that are not numbers or booleans are quoted
        if [[ $var_value = *\$* ]]; then
          var_value="\"${var_value}\""
        else
          # else surround non-numeric values with single quotes
          var_value="'${var_value}'"
        fi
      fi
      echo "${var_name}=${var_value}" >> $output_file_path
    else
      echo "# '${var_name}' is blank (use INCLUDE_BLANK=1 to include it here anyway)" >> $output_file_path
    fi
  done
done

### How to handle stuff in CI per package:
# echo <<parameters.package>>
# # name_orig="<<parameters.package>>"; name_snakecase="${name_orig//-/_}"; var_part=$(echo "$name_snakecase" | tr '[:lower:]' '[:upper:]') # remove _${var_part}_ from var names to get katedraali-dev vars
