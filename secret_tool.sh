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
    $cmd_name test -- ./.env.test:MY_VAR=123   # extract profile and append override to it

  Examples:
    $cmd_name staging                          # dump secrets for this profile
    $cmd_name dev test                         # dump secrets for these two profiles
    VAR123='' $cmd_name                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' $cmd_name test  # use this map file
    INCLUDE_BLANK=1 $cmd_name dev              # dump all, also empty values
    FILE_NAME_BASE='/tmp/.env.' $cmd_name dev  # start file name with this (create file /tmp/.env.dev)
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
      file_date=$(stat --format="%y" "$1")
      file_date=$(printf '%s\n' "$file_date" | tr 'T' ' at ')
    fi
    commit=''
  }
  modified_date_string="$file_date $commit"
  modified_date_string=$(printf '%s\n' "$modified_date_string" | tr 'T' ' at ')
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

  st_version="$(cat "$script_dir/$st_file_name" | tail -n 2 | xargs | cut -d' ' -f2) $(get_file_modified_date "$script_dir/$st_file_name")" || exit 1
  echo "$st_version"
  exit 0
fi

## 100% opinionated JSON only:
allowed_boolean_regexp='^(true|false)$'

## All that YAML supports (https://yaml.org/type/bool.html):
# allowed_boolean_regexp='^(y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF)$'

[ "$1" = "--help" ] && show_help

FORMAT=${FORMAT:-envfile}
FORMAT=$(echo "$FORMAT" | tr '[:upper:]' '[:lower:]')

SECRET_MAP=${SECRET_MAP:-./secret_map.yml}
FILE_NAME_BASE=${FILE_NAME_BASE:-./.env.} # this can be also be path
FILE_POSTFIX=${FILE_POSTFIX:-''} # this can be also be file extension

VERBOSITY=${VERBOSITY:-1} # by default output INFO and WARN messages

if [ "$1" = "--update" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    [ "$VERBOSITY" -ge "1" ] && echo '[INFO] Standalone installation (secret_utils.sh is not available). Attempting update in-place...'

    [ -z "$VERSION" ] && VERSION="$(curl -sL https://api.github.com/repos/netMedi/secret_tool/releases/latest | jq -r '.tag_name')"

    wget -qO ./secret_tool "https://raw.githubusercontent.com/netMedi/secret_tool/$VERSION/secret_tool.sh" || exit 1
    {
      sh -c "mv ./secret_tool '$actual_path'; chmod +x '$actual_path' 2> /dev/null" || exit 1
    } || {
      sudo sh -c "mv ./secret_tool '$actual_path'; chmod +x '$actual_path' 2> /dev/null" || exit 1
    } || {
      rm ./secret_tool
      exit 1
    }

    exit 0
  fi
  VERSION=$VERSION "$script_dir/secret_utils.sh" update || exit 1
  exit 0
fi

if [ "$1" = "--test" ]; then
  if [ ! -f "$script_dir/secret_utils.sh" ]; then
    [ "$VERBOSITY" -ge "1" ] && echo '[WARN] Standalone installation (secret_utils.sh is not available). Skipping tests.'
    exit 1
  fi
  "$script_dir/secret_utils.sh" test || exit 1
  exit 0
fi

__=${*:-''}
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
  [ "$VERBOSITY" -ge "1" ] && echo "[INFO] Please, change working directory or submit correct value via a SECRET_MAP variable"
  exit 1
fi

if [ "$1" = "--profiles" ] || [ "$1" = "--all" ]; then
  express_dump_commands=''
  target_profiles=$(yq e ".profiles | keys | .[]" "$SECRET_MAP" | tail -n +1 | grep -v '^--')
  [ "$1" = "--profiles" ] && {
    echo "$target_profiles"
    exit 0
  }
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
  FORMAT="$2"

  [ "$FORMAT" != "yml" ] && [ "$FORMAT" != "yaml" ] && FORMAT='json'
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
  # TODO: if key part is an integer, it is treated as an array index
  build_nested_object() {
    key=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    value="$2"
    json="$3"

    # Replace double underscores with dots
    while [ "${key#*__}" != "$key" ]; do
      key="${key%%__*}.${key#*__}"
    done

    # Use yq to set the value in the nested structure
    json=$(echo "$json" | yq eval ".${key} = $value" -)

    echo "$json"
  }

  # Read each line from the environment file
  while IFS= read -r line; do
    # Split the line into key and value
    key=$(echo "$line" | cut -d '=' -f 1)
    value=$(echo "$line" | cut -d '=' -f 2-)

    # Remove surrounding single or double quotes from the value
    if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ]; then
      value="${value#\"}"
      value="${value%\"}"
    elif [ "${value#\'}" != "$value" ] && [ "${value%\'}" != "$value" ]; then
      value="${value#\'}"
      value="${value%\'}"
    fi

    # Handle numeric and string values correctly
    if expr "$value" : '^[0-9]\+$' > /dev/null; then
      yq_object=$(build_nested_object "$key" "$value" "$yq_object")
    else
      yq_object=$(build_nested_object "$key" "\"$value\"" "$yq_object")
    fi

  done < "$env_file"

  inline_js_fixup="""
    const unoptimised_obj=\`$(echo "$yq_object" | yq -o=json '.')\`;

    const areAllKeysIntegers = obj => Object.keys(obj).every(key => /^\d+$/.test(key));
    const normalizeJSON = (obj) => {
      const result = {};
      for (const key in obj) {
        if (obj.hasOwnProperty(key)) {
          const value = obj[key];
          if (typeof value === 'object' && !Array.isArray(value)) {
            const normalized = normalizeJSON(value);
            result[key] = areAllKeysIntegers(normalized) ? Object.values(normalized) : normalized;
          } else {
            result[key] = Array.isArray(value) ? Object.fromEntries(value.map((v, i) => [i, v])) : value;
          }
        }
      }
      return result;
    };

    console.log(
      JSON.stringify(normalizeJSON(JSON.parse(unoptimised_obj)), null, 2)
    );
  """

  # use JS runtime to normalise nested arrays
  json_obj_normalised="$(echo "$inline_js_fixup" | bun run - 2> /dev/null)" \
    || json_obj_normalised="$(echo "$inline_js_fixup" | node)"

  # Print the final JSON object
  if [ "$FORMAT" = "json" ]; then
    [ -n "$json_obj_normalised" ] && {
      echo "$json_obj_normalised"
    } || {
      echo "$yq_object" | yq -o=json '.' -P
    }
  elif [ "$FORMAT" = "yml" ] || [ "$FORMAT" = "yaml" ]; then
    [ -n "$json_obj_normalised" ] && {
      echo "$json_obj_normalised" | yq -Poy
    } || {
      echo "$yq_object"
    }
  fi
}

if [ -f "$SKIP_OP_MARKER" ]; then
  [ "$DEBUG" = "1" ] && echo "[DEBUG] SKIP_OP_MARKER: $SKIP_OP_MARKER"
  export SKIP_OP_USE=1
elif [ -n "$CIRCLECI" ] || [ -n "$GITHUB_WORKFLOW" ] || [ "$SKIP_OP_USE" = "1" ]; then
  export SKIP_OP_USE=1
else
  [ "$(env | grep OP_SESSION_ | wc -c)" -gt "1" ] && {
    [ "$VERBOSITY" -ge "1" ] && echo '[INFO] 1password login confirmed'
  } || {
    [ "$VERBOSITY" -ge "1" ] && echo '[INFO] Trying to log in to 1password...'
    xyn='y'
    # signin manually if 1password eval signin has not been done yet
    while [ "$xyn" = "y" ]; do
      op whoami > /dev/null 2>&1 \
        && {
          xyn=''
          rm "$SKIP_OP_MARKER" 2> /dev/null
        } || {
          OP_VAL=$(op signin --account netmedi -f | head -n 1)
        }

      OP_SESSION_EVAL=$(echo "$OP_VAL" | grep export)
      [ -n "$OP_SESSION_EVAL" ] && {
        eval "$(echo "$OP_SESSION_EVAL")" && xyn=''
      }

      if [ "$xyn" = "y" ]; then
        xyn=''
        while [ "$xyn" = "" ]; do
          echo "Do you want to retry logging in to 1password?"
          echo "  Y (or Enter) = yes, retry"
          echo "  n = no, continue without 1password"
          echo "  x - just exit"
          read -r xyn

          case "$xyn" in
            [Yy]* )
              xyn='y'
              [ "$VERBOSITY" -ge "1" ] && {
                echo
                echo '[INFO] retrying to log in to 1password...'
              }
              ;;
            [Nn]* )
              SKIP_OP_USE=1
              ;;
            [Xx]* )
              kill 0
              ;;
            * )
              [ -z "$xyn" ] && {
                xyn='y'
              } || {
                echo '[ Please answer "y", "n", or "x" (single letter, no quotes) ]'
                echo
                xyn=''
              }
              ;;
          esac
        done
      fi
    done
  }
fi

if [ -n "$SKIP_OP_USE" ]; then
  [ -n "$SKIP_OP_MARKER_WRITE" ] && {
    touch "$SKIP_OP_MARKER"
    [ "$DEBUG" = "1" ] && echo "[DEBUG] SKIP_OP_MARKER written: $SKIP_OP_MARKER"
  }
fi

if [ -n "$target_profiles" ]; then
  [ "$VERBOSITY" -ge "1" ] && {
    echo
    echo "[INFO] Extracting values ($target_profiles)..."
  }

  for target_profile in $target_profiles; do
    # verify that target profile exists
    if yq e ".profiles | keys | .[] | select(. == \"${target_profile}\" )" "$SECRET_MAP" | wc -l | grep "0" > /dev/null 2>&1; then
      echo "[ERROR] Profile validation failed: profile '${target_profile}' was not found in $SECRET_MAP"
      FAILED=1
    fi
  done
  [ "$FAILED" = "1" ] && exit 1

  case "$FORMAT" in
    yml|yaml)
      extension='.yml'
      ;;
    json)
      extension='.json'
      ;;
    *)
      extension=''
      ;;
  esac

  for target_profile in $target_profiles; do
    output_file_path="${FILE_NAME_BASE}${target_profile}${FILE_POSTFIX}"

    inline_js_fixup="""
      const profile_vars=JSON.parse(\`$(yq -o=json '.' "$SECRET_MAP")\`)['profiles']['$target_profile'];

      // flatten nested arrays by adding index to key using double underscore as delimiter
      const flattenNestedArray = (obj, prefix = '') =>
        Object.keys(obj).reduce((acc, k) => {
          const pre = prefix.length ? prefix + '__' : '';
          if (Array.isArray(obj[k])) {
            obj[k].forEach((v, i) => {
              acc[pre + k + '__' + i] = v;
            });
          } else if (typeof obj[k] === 'object' && obj[k] !== null) {
            Object.assign(acc, flattenNestedArray(obj[k], pre + k));
          } else {
            acc[pre + k] = obj[k];
          }
          return acc;
        }, {});

      // flatten nested objects using double underscore as delimiter
      const flattenNestedObjects = (obj, prefix = '') =>
        Object.keys(obj).reduce((acc, k) => {
          const pre = prefix.length ? prefix + '__' : '';
          if (typeof obj[k] === 'object' && obj[k] !== null && !Array.isArray(obj[k])) {
            Object.assign(acc, flattenNestedObjects(obj[k], pre + k));
          } else {
            acc[pre + k] = obj[k];
          }
          return acc;
        }, {});

      Object.entries(flattenNestedObjects(flattenNestedArray(profile_vars))).forEach(([key, value]) => {
        console.log(key.toUpperCase() + '=\'\'\'' + value + '\'\'\'');
      });
    """
    env_variables="$(echo "$inline_js_fixup" | bun run - 2> /dev/null)" \
      || env_variables="$(echo "$inline_js_fixup" | node)"

    # uncomment next line for debugging
    # echo "All env variables: $env_variables"

    # ensure buffer is empty (prevent possible injections)
    printf "" > "$output_file_path.tmp"

    # content itself
    echo "$env_variables" | while IFS= read -r var_line; do
      var_name=${var_line%%=*}

      # unwrap var_value (the substring in between of triple quotes of var_line)
      var_value=${var_line#*=\'\'\'}
      var_value=${var_value%\'\'\'}

      # if local env variable override is present, use that
      local_override=$(env | grep "^${var_name}=")
      local_override=${local_override#*=}

      if [ -n "$local_override" ]; then
        var_value="${local_override}"
        [ "$FORMAT" = "envfile" ] && echo "# $var_name <- overridden from local env" >> "$output_file_path.tmp"
      else
        # otherwise, use value from secret map
        extract_value_from_op_ref "$var_value" > /dev/null
      fi

      # if we are including blank values, write those to file
      if [ -n "$var_value" ] || [ "$INCLUDE_BLANK" = "1" ]; then
        re_num='^[0-9]+$'
        re_yaml_bool=$allowed_boolean_regexp
        if ! (echo "$var_value" | grep -Eq "$re_num") && ! (echo "$var_value" | grep -Eq "$re_yaml_bool"); then
          # the strings that are not numbers or booleans are quoted
          case "$var_value" in
            *\$*)
              var_value="\"${var_value}\""
              ;;
            *)
              # else surround non-numeric values with single quotes
              var_value="'${var_value}'"
              ;;
          esac
        fi
        echo "${var_name}=${var_value}" >> "$output_file_path.tmp"
      else
        [ "$DEBUG" = '1' ] && echo "[DEBUG] ${target_profile} | '${var_name}' is blank (use INCLUDE_BLANK=1 to include it anyway)" #>> $output_file_path.tmp
      fi
    done
    unset IFS

    header_1='Content type'
    value_1='environment variables and secrets'

    header_2='File path'
    value_2="$(realpath "${FILE_NAME_BASE}${target_profile}${extension}")"

    header_3='Map path'
    value_3="$(realpath "$SECRET_MAP")"

    header_4='Profile'
    value_4="${target_profile}"

    header_5='Generated via secret_tool'
    value_5="$(date +'%Y-%m-%d at %H:%M:%S%:z')"

    header_6='Secret tool version'
    value_6="$($actual_path --version)"

    header_7='Secret map release'
    value_7="$(get_file_modified_date "$SECRET_MAP")"

    [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers() {
      cat <<EOF > "$1"
# ${header_1}: ${value_1}
# ${header_2}: ${value_2}
# ${header_3}: ${value_3}
# ${header_4}: ${value_4}
# ${header_5}: ${value_5}
# ${header_6}: ${value_6}
# ${header_7}: ${value_7}

$(cat "$1")
EOF
    }

    case "$FORMAT" in
      yml|yaml)
        produce_configmap "$output_file_path.tmp" yml > "$output_file_path.yml"
        [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers "$output_file_path.yml"
        ;;
      json)
        produce_configmap "$output_file_path.tmp" json > "$output_file_path.json"

        [ "$SKIP_HEADERS_USE" != "1" ] && yq eval ". += {\"//\": {\"# ${header_1}\": \"${value_1}\", \"# ${header_2}\": \"${value_2}\", \"# ${header_3}\": \"${value_3}\", \"# ${header_4}\": \"${value_4}\", \"# ${header_5}\": \"${value_5}\", \"# ${header_6}\": \"${value_6}\", \"# ${header_7}\": \"${value_7}\"}}" "$output_file_path.json" -i

        # sort top level json keys alphabetically with yq
        yq eval 'sort_keys(.)' "$output_file_path.json" -i
        ;;
      *)
        FORMAT='envfile'
        touch "$output_file_path"
        sort "$output_file_path.tmp" | uniq > "$output_file_path"
        [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers "$output_file_path"
        ;;
    esac

    [ "$VERBOSITY" -ge "1" ] && {
      echo "[INFO] Output: $(realpath "${output_file_path}${extension}")"
    }
    rm "$output_file_path.tmp"
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

# v1.4.3
