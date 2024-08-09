#!/bin/sh
FALLBACK=$(ps -p $$ -o comm=)

BEST_CHOICE=1; SHELL_NAME="bash" # [!!!] WIP this line prevents forced switch to POSIX shell

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

cmd_name=$(basename "$0")
# shellcheck disable=SC2140
help_text="
  Script: $cmd_name
  Purpose: Produce file(s) with environment variables and secrets from 1password using secret map

  Usage: [OVERRIDES] $cmd_name [PROFILE_NAME(S)]
  (if any dashed arguments are present, all other arguments are ignored)
    $cmd_name --version                        # print version info and exit
    $cmd_name --help                           # print help and exit
    $cmd_name --update                         # perform self-update and exit (only for full git install)
    $cmd_name --test                           # perform self-test and exit (only for full git install)
    $cmd_name --profiles                       # list all available profiles and exit
    $cmd_name --profiles                       # list all available profiles and exit
    $cmd_name -- .env.test:MY_VAR=123          # express dump variable into file (append to existing or create new)
    $cmd_name test -- ./.env.test:MY_VAR=123     # extract profile and append override to it

  Examples:
    $cmd_name staging                          # dump secrets for this profile
    $cmd_name dev test                         # dump secrets for these two profiles
    VAR123='' $cmd_name                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' $cmd_name test  # use this map file
    INCLUDE_BLANK=1 $cmd_name dev              # dump all, also empty values
    FILE_NAME_BASE='/tmp/.env' $cmd_name dev   # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX='.sh' $cmd_name prod          # append this to file name end (.env.prod.sh)
    PROFILES='ci test' $cmd_name               # set target profiles via variable (same as \`$cmd_name ci test\`)
    SKIP_OP_USE=1 $cmd_name ci                 # do not use 1password
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

show_help() {
  echo "$help_text" | head -n -1 | tail -n +2
  exit 0
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

[ "$1" = "--help" ] && show_help

# FORMAT=${FORMAT:-envfile}
SECRET_MAP=${SECRET_MAP:-./secret_map.yml}
FILE_NAME_BASE=${FILE_NAME_BASE:-./.env} # this can be also be path
FILE_POSTFIX=${FILE_POSTFIX:-''} # this can be also be file extension

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

__=${@:-''}
express_dump_commands="${__#*--}"
[ "$express_dump_commands" = "$__" ] && express_dump_commands=""

if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ]; then
  export PROFILES="ci"
fi

if [ -n "$PROFILES" ]; then
  __=$PROFILES
fi
target_profiles="${__%%--*}"
[ "${__#--}" != "$__" ] && target_profiles=""

if [ -n "$target_profiles" ] && [ ! -f "$SECRET_MAP" ]; then
  echo "[ERROR] Secret map file not found: $SECRET_MAP"
  echo "[INFO] Please, change working directory or submit correct value via a SECRET_MAP variable"
  exit 1
fi

if [ "$1" = "--profiles" ]; then
  yq e ".profiles | keys | .[]" "$SECRET_MAP" | tail -n +1 | grep -v '^--'
  exit 0
fi

# print help (head of current file) if no arguments are provided
[ -z "$express_dump_commands" ] && [ -z "$target_profiles" ] && show_help

extract_value_from_op_ref() {
  var_value="$1"
  if [ "$(echo "$var_value" | cut -c1-3)" = ":::" ]; then
    if [ "$SKIP_OP_USE" = "1" ]; then
      var_value=''
    else
      var_value=$(op read "$(echo "$var_value" | cut -c4- | xargs)" 2> /dev/null)
    fi
  fi
  echo "$var_value"
}

substr_in_str() {
  echo "$1" | grep -q "$2"
}

produce_configmap() {
  env_file="$1"
  FORMAT="${2:-json}"
  extension="${env_file##*.}"

  if [ ! -f "$env_file" ]; then
    echo "[ERROR] File not found: $env_file"
    exit 1
  fi

  [ "$extension" = "json" ] && {
    cat "$env_file"
    exit 0
  }

  [ "$extension" = "yml" ] || [ "$extension" = "yaml" ] && {
    yq -o=json '.' "$env_file"
    exit 0
  }

  yq_object="{}"

  # Function to build nested objects using dots as delimiters
  build_nested_object() {
    local key="$1"
    local value="$2"
    local json="$3"

    # Replace double underscores with dots
    key=$(echo "$key" | sed 's/__/\./g')

    # Use yq to set the value in the nested structure
    json=$(echo "$json" | yq eval ".${key} = $value" -)

    echo "$json"
  }

  # Read each line from the environment file
  while IFS= read -r line; do
    # Split the line into key and value
    key=$(echo "$line" | cut -d '=' -f 1)
    value=$(echo "$line" | cut -d '=' -f 2-)

    # Handle numeric and string values correctly
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      yq_object=$(build_nested_object "$key" "$value" "$yq_object")
    else
      yq_object=$(build_nested_object "$key" "\"$value\"" "$yq_object")
    fi

  done < "$env_file"

  # Print the final JSON object
  if [ "$FORMAT" = "yml" ] || [ "$FORMAT" = "yaml" ]; then
    echo "$yq_object"
  elif [ "$FORMAT" = "json" ]; then
    echo "$yq_object" | yq -o=json '.'
  fi
}

if [ -n "$target_profiles" ]; then
  if [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ] || [ "$SKIP_OP_USE" = "1" ]; then
    export SKIP_OP_USE=1
  else
    [ "$(env | grep OP_SESSION_ | wc -c)" -gt "1" ] && {
      echo '[INFO] 1password login confirmed'
    } || {
      echo '[INFO] Trying to log in to 1password...'
      xyn='y'
      # signin manually if 1password eval signin has not been done yet
      while [ "$xyn" = "y" ]; do
        op whoami > /dev/null 2>&1 \
          || OP_VAL=$(op signin --account netmedi -f | head -n 1) \
          || { echo "$OP_VAL"; xyn='y'; }

        OP_SESSION_EVAL=$(echo "$OP_VAL" | grep export)
        [ -n "$OP_SESSION_EVAL" ] && {
          eval "$(echo $OP_SESSION_EVAL)"
          xyn=''
        }

        if [ "$xyn" = "y" ]; then
          echo "Do you want to retry?"
          echo "  Y (or Enter) = yes, retry"
          echo "  n = no, continue without 1password"
          echo "  x - just exit"
          read -n 1 xyn
          case $xyn in
            [Yy]* ) xyn='y'; echo "retrying to log in to 1password...";;
            [Nn]* ) SKIP_OP_USE=1;;
            [Xx]* ) exit 1;;
            * ) [ -z "$xyn" ] && xyn='y'; echo 'Please answer "y", "n", or "x" (single letter, no quotes)';;
          esac
        fi
      done
    }

    echo
    echo '[INFO] Extracting values...'
  fi

  for target_profile in $target_profiles; do
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

  for target_profile in $target_profiles; do
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
        extract_value_from_op_ref "$var_value" > /dev/null
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
fi

for var_value in $express_dump_commands; do
  var_path=${var_value%%=*}

  substr_in_str "$var_value" '=' && {
    mode='set'
    var_value=${var_value#*=}
  } || {
    mode='get'
    var_value=''
  }

  file_path=${var_path%%:*}
  substr_in_str "$var_path" ':' \
    && var_path=${var_path#*:} \
    || var_path=''

  [ "$mode" = "set" ] && {
    # set mode writes data to file
    dirname "$file_path" | xargs mkdir -p > /dev/null 2>&1
    echo "$var_path=$(extract_value_from_op_ref "$var_value")" >> "$file_path"
  } || {
    # get mode reads data from file
    if [ -f "$file_path" ]; then
      [ -n "$var_path" ] \
        && grep "^$var_path=" "$file_path" | cut -d'=' -f2 \
        || produce_configmap "$file_path" "${FORMAT:-json}"
    else
      echo "[ERROR] File not found: $file_path"
      exit 1
    fi
  }
done

# v1.4beta
