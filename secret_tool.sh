#!/bin/sh
cmd_name=$(basename "$0")
# shellcheck disable=SC2140
help_text="
  Script: $cmd_name
  Purpose: Dump secrets from 1password and secret map to .env file

  Usage: [OVERRIDES] $cmd_name [PROFILE_NAME(S)]
  (if any dashed arguments are present, all other arguments are ignored)
    $cmd_name --version                        # print version info and exit
    $cmd_name --help                           # print help and exit
    $cmd_name --update                         # perform self-update and exit (only for full git install)
    $cmd_name --test                           # perform self-test and exit (only for full git install)
    $cmd_name --profiles                       # list all available profiles and exit

  Examples:
    $cmd_name staging                          # dump secrets for this profile
    $cmd_name dev test                         # dump secrets for these two profiles
    VAR123='' $cmd_name                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' $cmd_name test  # use this map file
    INCLUDE_BLANK=1 $cmd_name dev              # dump all, also empty values
    FILE_NAME_BASE="/tmp/.env" $cmd_name dev   # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX='.sh' $cmd_name prod          # append this to file name end (.env.prod.sh)
    PROFILES='ci test' $cmd_name               # set target profiles via variable (same as \`$cmd_name ci test\`)
    SKIP_OP_USE=1 $cmd_name ci                     # do not use 1password
"
# shellcheck enable=SC2140

actual_path=$(readlink -f "$0")
script_dir=$(dirname "$actual_path")

get_file_modified_date() {
  {
    # try grabbing info from git
    file_date=$(git log -1 --pretty="format:%cI" -- "$1" 2> /dev/null)
    commit=$(git log -1 --pretty="commit %H" -- "$1" 2> /dev/null)
  } || {
    # fallback to file modification date
    if [ "$(uname)" = "Darwin" ]; then
      file_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S%z" "$1")
    else
      file_date=$(date +'%Y-%m-%d at %H:%M:%S%z' -r "$1")
    fi
    commit=''
  }
  modified_date_string="$file_date $commit"
  modified_date_string=${modified_date_string/T/ at }
  echo "$modified_date_string"
}

if [ "$1" = "--version" ]; then
  st_file_name=secret_tool.sh
  [ -f "$script_dir/secret_utils.sh" ] \
    && cd "$script_dir" \
    || st_file_name=secret_tool

  st_version="$(cat ./$st_file_name | tail -n 2 | xargs | cut -d' ' -f2) $(get_file_modified_date ./$st_file_name)" || exit 1
  echo "$st_version"
  exit 0
fi

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
  echo "$help_text" | head -n -1 | tail -n +2
  exit 0
fi

if [ "$1" = "--update" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    echo '[WARN] Standalone installation (secret_utils.sh is not available). Self update is not possible.'
    exit 1
  fi
  "$script_dir/secret_utils.sh" update || exit 1
  exit 0
fi

if [ "$1" = "--test" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    echo '[WARN] Standalone installation (secret_utils.sh is not available). Skipping tests.'
    exit 1
  fi
  "$script_dir/secret_utils.sh" test || exit 1
  exit 0
fi

if [ -n "$SECRET_MAP" ] && [ ! -f "$SECRET_MAP" ]; then
  echo "[ERROR] Secret map file not found: $SECRET_MAP"
  echo "[INFO] Please, change working directory or submit correct value via a SECRET_MAP variable"
  exit 1
fi

if [[ "$*" == *"--profiles"* ]]; then
  yq e ".profiles | keys | .[]" "$SECRET_MAP" | tail -n +1 | grep -v '^--'
  exit 0
fi

if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ]; then
  export PROFILES="ci"
fi

if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ] || [ "$SKIP_OP_USE" = "1" ] || [[ "$*" == *"--help"* ]] || [[ "$*" == *"--profiles"* ]]; then
  export SKIP_OP_USE=1
else
  # signin manually if 1password eval signin has not been done yet
  op whoami > /dev/null 2>&1 || eval "$(op signin --account netmedi)" || exit 1
  # eval $(op signin --account netmedi); op whoami 2> /dev/null &> /dev/null || exit 1
  echo '[INFO] Extracting values...'
fi

for target_profile in $target_environments; do
  # verify that target profile exists
  if yq e ".profiles | keys | .[] | select(. == \"${target_profile}\" )" "$SECRET_MAP" | wc -l | grep "0" > /dev/null 2>&1; then
    echo "[ERROR] Profile validation failed: profile '${target_profile}' was not found in $SECRET_MAP"
    FAILED=1
  fi
done
[ "$FAILED" = "1" ] && exit 1

duplicates_check() {
  input_array=("$@")
  for ((i=0; i<${#input_array[@]}; i++)); do
    for ((j=i+1; j<${#input_array[@]}; j++)); do
      if [[ "${input_array[i]}" == "${input_array[j]}" ]]; then
        echo "[WARN] Duplicate keys detected: ${input_array[i]}"
      fi
    done
  done
}

# block of overridable defaults
env_variables_defaults=$(yq -r ".profiles.--defaults | to_entries | .[] | .key" "$SECRET_MAP")
duplicates_check "${env_variables_defaults[@]}"

for target_profile in $target_environments; do
  output_file_path="${FILE_NAME_BASE}.${target_profile}${FILE_POSTFIX}"

  # block of target environment
  env_variables=$(yq -r ".profiles.$target_profile | to_entries | .[] | .key" "$SECRET_MAP")

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
  IFS=$'\n' env_variables=($(printf '%s\n' "${clean_env[@]}" | LC_ALL=C sort))


  # uncomment next line for debugging
  # echo "All env variables: ${env_variables[@]}"

  echo '' > "$output_file_path"

  # content itself
  for var_name in "${env_variables[@]}"; do
    # if local env variable override is present, use that
    var_value="${!var_name}"
    if [ -n "$var_value" ]; then
      echo "# overridden from local env: $var_name" >> "$output_file_path.tmp"
    else
      # otherwise, use value from secret map
      var_value=$(yq e ".profiles.$target_profile.$var_name | select(.)" "$SECRET_MAP")
      if [ "$(echo "$var_value" | cut -c1-3)" = ":::" ]; then
        if [ "$SKIP_OP_USE" = "1" ]; then
          var_value=''
        else
          var_value=$(op read "$(echo "$var_value" | cut -c4- | xargs)" 2> /dev/null)
        fi
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
      echo "${var_name}=${var_value}" >> "$output_file_path.tmp"
    else
      [ "$DEBUG" = '1' ] && echo "[DEBUG] ${target_profile} | '${var_name}' is blank (use INCLUDE_BLANK=1 to include it anyway)" #>> $output_file_path.tmp
    fi
  done

  sort "$output_file_path.tmp" | uniq > "$output_file_path"
  rm "$output_file_path.tmp"

  # headers
  cat <<EOF > "$output_file_path"
# Content type: environment variables and secrets
# File path: $(realpath "$output_file_path")
# Map path: $(realpath "$SECRET_MAP")
# Profile: ${target_profile}
# Generated via secret_tool on $(date +'%Y-%m-%d at %H:%M:%S%:z')
# Secret tool version: $($actual_path --version)
# Secret map release: $(get_file_modified_date "$SECRET_MAP")

$(cat "$output_file_path")
EOF

done

# v1.3.2
