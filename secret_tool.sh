#!/bin/sh

TOOL_VERSION='1.6.4 (deprecation notice!)'
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
    $cmd_name --all                            # dump secrets for all profiles

  Examples:
    $cmd_name staging                          # dump secrets for this profile
    $cmd_name dev test                         # dump secrets for these two profiles
    VAR123='' $cmd_name                        # ignore local override of this variable
    SECRET_MAP='~/alt-map.yml' $cmd_name test  # use this map file
    EXCLUDE_EMPTY_STRINGS=1 $cmd_name dev      # dump all, exclude blank values
    FILE_NAME_BASE='/tmp/.env.' $cmd_name dev  # start file name with this (create file /tmp/.env.dev)
    FILE_POSTFIX='.sh' $cmd_name prod          # append this to file name end (.env.prod.sh)
    EXTRACT='ci test' $cmd_name                # set target profiles via variable (same as \`$cmd_name ci test\`)
    SKIP_OP_USE=1 $cmd_name ci                 # do not use 1password
"
# shellcheck enable=SC2140

actual_path=$(readlink -f "$0")
script_dir=$(dirname "$actual_path")

get_file_modified_date() {
  filesystem_info_only="$2"
  [ -z "$filesystem_info_only" ] && {
    # try grabbing info from git
    file_date=$(git log -1 --pretty="format:%cI" -- "$1" 2> /dev/null)
    commit=$(git log -1 --pretty="commit %H" -- "$1" 2> /dev/null)
  } || {
    # fallback to file modification date
    if [ "$(uname)" = "Darwin" ]; then
      file_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S%z" "$1")
    else
      file_date=$(stat --format="%y" "$1")
      file_date=$(printf '%s\n' "$file_date")
    fi
    commit=''
  }
  modified_date_string="$file_date $commit"
  modified_date_string=$(printf '%s\n' "$modified_date_string")
  echo "$modified_date_string"
}

show_help() {
  echo "$help_text" | head -n -1 | tail -n +2
  exit 0
}

get_own_version() {
  st_file_name=secret_tool.sh
  [ -f "$script_dir/secret_utils.sh" ] \
    && cd "$script_dir" \
    || st_file_name=secret_tool

  st_version="$TOOL_VERSION $(get_file_modified_date "$script_dir/$st_file_name")" || exit 1
  echo "$st_version"
}

validate_minimal_version() {
  NEWER_VERSION=$(printf "$1\n$2\n" | sort -t '.' -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g | tail -n 1)

  if [ "$NEWER_VERSION" = "$2" ]; then
    return 0
  else
    return 1
  fi
}

validate_approved_version() {
  APPROVED_TOOL_VERSION=$(op read op://Employee/SECRET_TOOL/version 2> /dev/null)
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    [ "$DEBUG" = "1" ] && echo "[ERROR] Could not read approved version from 1password"
    return 1
  fi

  if [ "$APPROVED_TOOL_VERSION" = "latest" ]; then
    return 0
  elif [ -n "$APPROVED_TOOL_VERSION" ] && validate_minimal_version $TOOL_VERSION $APPROVED_TOOL_VERSION; then
    return 0
  else
    [ -n "$APPROVED_TOOL_VERSION" ] && echo "[INFO] Approved secret tool version: $APPROVED_TOOL_VERSION"
    echo "[ERROR] You need to approve version '$TOOL_VERSION' of secret_tool in 1password to continue (https://github.com/netMedi/Holvikaari/blob/master/docs/holvikaari-dev-overview.md#installation)"

    [ -n "$SKIP_OP_MARKER_WRITE" ] && {
      touch "$SKIP_OP_MARKER"
      [ "$DEBUG" = "1" ] && echo "[DEBUG] SKIP_OP_MARKER written: $SKIP_OP_MARKER"
    }

    # continue without 1password or exit
    if [ "$xyn" = "y" ]; then
      xyn=''
      while [ "$xyn" = "" ]; do
        echo "Try extracting OP secrets regardless?"
        echo "  Y (or Enter) = yes, ignore version mismatch"
        echo "  n = no, continue without 1password"
        echo "  x - just exit"
        read -r xyn

        case "$xyn" in
          [Yy]* )
            [ "$VERBOSITY" -ge "1" ] && {
              echo
              echo '[INFO] trying to extract OP secrets...'
            }
            ;;
          [Nn]* )
            SKIP_OP_USE=1
            return 0
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
  fi
}

if [ "$1" = "--version" ]; then
  get_own_version
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
EXCLUDE_EMPTY_STRINGS=${EXCLUDE_EMPTY_STRINGS:-1}
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
  echo '[INFO] Running in CI. Make sure to either use SKIP_OP_USE=1 or pass through 1password session'
fi

if [ -n "$EXTRACT" ]; then
  __=$EXTRACT
fi
target_profiles="${__%%--*}"
[ "${__#--}" != "$__" ] && target_profiles=""

if [ -n "$target_profiles" ] && [ ! -f "$SECRET_MAP" ]; then
  echo "[ERROR] Secret map file not found: $SECRET_MAP"
  [ "$VERBOSITY" -ge "1" ] && echo "[INFO] Please, change working directory or submit correct value via a SECRET_MAP variable"
  exit 1
fi

# compare top level tool_version key value from secret map with current tool version
if [ "$SKIP_REQ_CHECK" != "1" ]; then
  MINIMALLY_REQUIRED_VERSION=$(yq -r '.tool_version' "$SECRET_MAP")
  validate_minimal_version $MINIMALLY_REQUIRED_VERSION $TOOL_VERSION || {
    echo "[ERROR] Minimally required secret_tool version for secret_map \"$SECRET_MAP\": ${MINIMALLY_REQUIRED_VERSION}. Update secret_tool or use SKIP_REQ_CHECK=1 to bypass this check."
    echo
    get_own_version
    exit 1
  }
fi

if [ "$1" = "--profiles" ] || [ "$1" = "--all" ]; then
  express_dump_commands=''
  target_profiles=$(yq e ".profiles | keys | .[]" "$SECRET_MAP" | tail -n +1 | grep -v '^--' | sort)
  [ "$1" = "--profiles" ] && {
    echo "$target_profiles"
    exit 0
  }
fi

# print help (head of current file) if no arguments are provided
[ -z "$express_dump_commands" ] && [ -z "$target_profiles" ] && show_help

bak_prev_file() {
  filename="$1"
  if [ -f "$filename" ]; then
    filename_friendly_date_string="$(get_file_modified_date "$filename" 1 | tr ' ' '_' | tr ':' '-')"
    filename_friendly_date_string=${filename_friendly_date_string%%.*}
    bak_filename="${filename}.${filename_friendly_date_string}.bak"
    mv "$filename" "$bak_filename"
  fi
}

rebuff() {
  filename="$1"
  rm "$filename" 2> /dev/null
  directory="$(dirname "$filename")"
  [ ! -d "${directory}" ] && mkdir -p "${directory}"
  touch "$filename"
}

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

flat_obj_to_nest() {
  env_file="$1" # flat json or yaml configmap file that we want to convert into nested
  FORMAT="$2"

  if [ "$FORMAT" = "json" ]; then
    env_file=$(cat "$env_file")
  else
    # convert yaml file to json
    env_file=$(yq eval -o=json '.' "$env_file")
  fi
  # convert flat json to nested json
  inline_js_fixup="""
    const flat_env_obj = JSON.parse(\`$(echo "$env_file")\`);

    // convert flat object to nested object
    const nestify = (obj) => {
      const result = {};
      for (const key in obj) {
        const keys = key.toLowerCase().split('__'); // convert key to lowercase
        keys.reduce((acc, k, i) => {
          if (i === keys.length - 1) {
            acc[k] = obj[key];
          } else {
            acc[k] = acc[k] || {};
          }
          return acc[k];
        }, result);
      }
      return result;
    };

    const nested_env_obj = nestify(flat_env_obj);

    const areAllKeysIntegers = obj => Object.keys(obj).every(key => /^\d+$/.test(key));
    const isEmptyObject = obj => Object.keys(obj).length === 0 && obj.constructor === Object;

    const normaliseJSON = (obj) => {
      const result = {};
      for (const key in obj) {
        if (obj.hasOwnProperty(key)) {
          const value = obj[key];
          if (Array.isArray(value)) {
            result[key] = value;
          } else if (typeof value === 'object' && value !== null) {
            result[key] = normaliseJSON(value);
          } else {
            result[key] = value;
          }
        }
      }
      return !isEmptyObject(result) && areAllKeysIntegers(result) ? Object.values(result) : result;
    };

    console.log(JSON.stringify(normaliseJSON(nested_env_obj), null, 2));
  """
  if [ "$FORMAT" = "json" ]; then
    {
      echo "$inline_js_fixup" | bun run - 2> /dev/null
    } || {
      echo "$inline_js_fixup" | node
    }
  else # yaml
    {
      json_obj="$(echo "$inline_js_fixup" | bun run - 2> /dev/null)"
    } || {
      json_obj="$(echo "$inline_js_fixup" | node)"
    }
    # convert json to yaml
    echo "$json_obj" | yq -P
  fi
}

if [ -f "$SKIP_OP_MARKER" ]; then
  [ "$DEBUG" = "1" ] && echo "[DEBUG] SKIP_OP_MARKER: $SKIP_OP_MARKER"
  export SKIP_OP_USE=1
elif [ "$SKIP_OP_USE" != "1" ]; then

  [ "$DEBUG" = "1" ] && echo "[DEBUG] Checking 1password login status..."

  if [ "$(env | grep OP_SESSION_ | wc -c)" -gt "1" ] && validate_approved_version; then
    [ "$VERBOSITY" -ge "1" ] && echo '[INFO] 1password login confirmed'
  else
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
        eval "$(echo "$OP_SESSION_EVAL")" && {
          validate_approved_version && xyn='' || exit 1
        }
      }

      if [ "$xyn" = "y" ]; then
        xyn=''
        while [ "$xyn" = "" ]; do
          echo "Retry logging in to 1password?"
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
  fi
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
    echo "[INFO] Extracting values ($(echo "$target_profiles" | xargs))..."
  }

  for target_profile in $target_profiles; do
    # verify that target profile exists
    found_profile=false
    for profile in $(yq e ".profiles | keys | .[]" "$SECRET_MAP"); do
      if [ "$profile" = "$target_profile" ]; then
        found_profile=true
        break
      fi
    done

    if [ "$found_profile" = false ]; then
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
    rebuff "$output_file_path.tmp"
    rm "$output_file_path"*.tmp > /dev/null 2>&1

    inline_js_fixup="""
      const profile_vars=JSON.parse(\`$(yq -o=json '.' "$SECRET_MAP")\`)['profiles']['$target_profile'];

      // flatten nested arrays by adding index to key using double underscore as delimiter
      const flattenNestedArray = (obj, prefix = '') =>
        Object.keys(obj).reduce((acc, k) => {
          const pre = prefix.length ? prefix + '__' : '';
          if (Array.isArray(obj[k])) {
        if (obj[k].length === 0) {
          acc[pre + k] = []; // Include empty arrays
        } else {
          obj[k].forEach((v, i) => {
            acc[pre + k + '__' + i] = v;
          });
        }
          } else if (typeof obj[k] === 'object' && obj[k] !== null) {
        if (Object.keys(obj[k]).length === 0) {
          acc[pre + k] = {}; // Include empty objects
        } else {
          Object.assign(acc, flattenNestedArray(obj[k], pre + k));
        }
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
            if (Object.keys(obj[k]).length === 0) {
              acc[pre + k] = {}; // Include empty objects
            } else {
              Object.assign(acc, flattenNestedObjects(obj[k], pre + k));
            }
          } else {
            acc[pre + k] = obj[k];
          }
          return acc;
        }, {});

      const flat_env_obj = flattenNestedObjects(flattenNestedArray(profile_vars));
      const flat_yaml_env = Object.entries(flat_env_obj)
        .map(([key, value]) => {

          if (Array.isArray(value) && value.length === 0) {
            return key.toLowerCase() + ': []';
          } else if (typeof value === 'object' && Object.keys(value).length === 0) {
            return key.toLowerCase() + ': {}';
          } else {
            return key.toLowerCase() + ': \'' + value + '\''; // this will fail if value contains single quotes !!!
          }
        })
        .join(String.fromCharCode(10));

      console.log(flat_yaml_env);
    """
    env_variables="$(echo "$inline_js_fixup" | bun run - 2> /dev/null)" \
      || env_variables="$(echo "$inline_js_fixup" | node)"
    [ "$DEBUG" = "1" ] && echo '[DEBUG] env_variables:' && echo "$env_variables" | while IFS= read -r line; do
      echo "  $line"
    done

    # uncomment next line for debugging
    # echo "All env variables: $env_variables"

    # record locally overriden and blank variables
    locally_overriden_variables=''
    excluded_blank_variables=''

    # ensure buffer is empty (prevent possible injections)
    rebuff "$output_file_path.yml.tmp"

    # temporary file is a flat YAML secret list
    echo "$env_variables" | while IFS= read -r var_line; do
      empty=''
      var_name=${var_line%%:*}

      # unwrap var_value (the substring in between of triple quotes of var_line)
      var_value=${var_line#*: \'}
      var_value=${var_value%\'}

      # ignore empty arrays and objects
      if [ "$var_value" = "$var_name: []" ]; then
        empty='array'
        var_value=''
      elif [ "$var_value" = "$var_name: {}" ]; then
        empty='object'
        var_value=''
      fi

      # if local env variable override is present, use that
      env_var_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
      local_override=$(env | grep "^${env_var_name}=")
      local_override=${local_override#*=}

      if [ -n "$local_override" ]; then
        # treat "!!" as a sign to set empty variable
        if [ "$local_override" = "!![]" ]; then
          empty='array'
          var_value=''
        elif [ "$local_override" = "!!{}" ]; then
          empty='object'
          var_value=''
        elif [ "$local_override" = "!!" ]; then
          empty='string'
          var_value=''
        else
          var_value="${local_override}"
        fi
        locally_overriden_variables="${locally_overriden_variables} ${var_name}"
      elif [ -z "$var_value" ]; then
        [ -z "$empty" ] && empty='string'
      fi

      var_value=$(extract_value_from_op_ref "$var_value")
      if [ -z "$var_value" ]; then
        [ -z "$empty" ] && empty='string'
      fi

      [ "$DEBUG" = '1' ] && echo "[DEBUG] ${target_profile} | '${var_name}' = '${var_value}'"

      # if we are including blank values, write those to file
      if [ -n "$empty" ]; then
        if [ "$empty" = "array" ]; then
          echo "${var_name}: []" >> "$output_file_path.yml.tmp"
        elif [ "$empty" = "object" ]; then
          echo "${var_name}: {}" >> "$output_file_path.yml.tmp"
        else
          if [ "$EXCLUDE_EMPTY_STRINGS" = "1" ]; then
            excluded_blank_variables="${excluded_blank_variables} ${var_name}"
          else
            [ "$DEBUG" = '1' ] && echo "[DEBUG] ${target_profile} | '${var_name}' is blank (use EXCLUDE_EMPTY_STRINGS=1 to exclude it from output)"
            echo "${var_name}: ''" >> "$output_file_path.yml.tmp"
          fi
        fi
      elif [ -n "$var_value" ]; then
        re_num='^[0-9]+$'
        re_yaml_bool=$allowed_boolean_regexp
        if ! (echo "$var_value" | grep -Eq "$re_num") && ! (echo "$var_value" | grep -Eq "$re_yaml_bool"); then
          # the strings that are not numbers or booleans are quoted
          case "$var_value" in
            *\$*|*\'*)
              # if value has dollar sign or single quotes, surround with "
              var_value="\"${var_value}\""
              ;;
            *)
              # else surround non-numeric values with '
              var_value="'${var_value}'"
              ;;
          esac
        fi
        echo "${var_name}: ${var_value}" >> "$output_file_path.yml.tmp"
      fi

      rebuff "$output_file_path.override.tmp"
      echo "$locally_overriden_variables" > "$output_file_path.override.tmp"

      [ "$EXCLUDE_EMPTY_STRINGS" = "1" ] && {
        rebuff "$output_file_path.excluded.tmp"
        echo "$excluded_blank_variables" > "$output_file_path.excluded.tmp"
      }
    done

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

    header_8='Locally overriden variables'
    locally_overriden_variables=$(cat "$output_file_path.override.tmp" | tr '[:lower:]' '[:upper:]' | xargs)
    value_8="%w[${locally_overriden_variables}]"

    header_9='Excluded (blank) string variables'
    [ "$EXCLUDE_EMPTY_STRINGS" = "1" ] && excluded_blank_variables=$(cat "$output_file_path.excluded.tmp" | tr '[:lower:]' '[:upper:]' | xargs)
    value_9="%w[${excluded_blank_variables}]"

    [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers() {
      cat <<EOF > "$1"
# ${header_1}: ${value_1}
# ${header_2}: ${value_2}
# ${header_3}: ${value_3}
# ${header_4}: ${value_4}
# ${header_5}: ${value_5}
# ${header_6}: ${value_6}
# ${header_7}: ${value_7}
# ${header_8}: ${value_8}
# ${header_9}: ${value_9}

$(cat "$1")
EOF
    }

    case "$FORMAT" in
      yml|yaml)
        extension='.yml'
        [ "$LIVE_DANGEROUSLY" != "1" ] && bak_prev_file "$output_file_path${extension}"

        rebuff "$output_file_path.yml"

        flat_obj_to_nest "$output_file_path.yml.tmp" yml > "$output_file_path.yml"
        [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers "$output_file_path${extension}"
        ;;
      json)
        extension='.json'
        [ "$LIVE_DANGEROUSLY" != "1" ] && bak_prev_file "$output_file_path${extension}"

        rebuff "$output_file_path.json.tmp"
        cat "$output_file_path.yml.tmp" | yq eval -o=json '.' >> "$output_file_path.json.tmp"

        flat_obj_to_nest "$output_file_path.json.tmp" json > "$output_file_path${extension}"

        [ "$SKIP_HEADERS_USE" != "1" ] && yq eval ". += {\"//\": {\"# ${header_1}\": \"${value_1}\", \"# ${header_2}\": \"${value_2}\", \"# ${header_3}\": \"${value_3}\", \"# ${header_4}\": \"${value_4}\", \"# ${header_5}\": \"${value_5}\", \"# ${header_6}\": \"${value_6}\", \"# ${header_7}\": \"${value_7}\", \"# ${header_8}\": \"${value_8}\", \"# ${header_9}\": \"${value_9}\"}}" "$output_file_path${extension}" -i

        # sort top level json keys alphabetically with yq
        yq eval 'sort_keys(.)' "$output_file_path${extension}" -i
        ;;
      *)
        FORMAT='envfile'
        [ "$LIVE_DANGEROUSLY" != "1" ] && bak_prev_file "$output_file_path"

        rebuff "$output_file_path.tmp"
        while IFS= read -r var_line; do
          empty=''
          var_name=${var_line%%:*}

          # make names uppercase and replace dashes with underscores
          var_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

          var_value=${var_line#*: }

          # ignore empty arrays and objects
          if [ "$var_value" = "[]" ]; then
            empty='array'
            var_value=''
          elif [ "$var_value" = "{}" ]; then
            empty='object'
            var_value=''
          fi

          # if we are including blank values, write those to file
          if [ -n "$empty" ]; then
            if [ "$empty" = "array" ]; then
              echo "# ${var_name} is an empty array" >> "$output_file_path.tmp"
            elif [ "$empty" = "object" ]; then
              echo "# ${var_name} is an empty object" >> "$output_file_path.tmp"
            fi
          else #if [ -n "$var_value" ]; then
            echo "${var_name}=${var_value}" >> "$output_file_path.tmp"
          fi
        done < "$output_file_path.yml.tmp"
        unset IFS

        touch "$output_file_path"
        sort "$output_file_path.tmp" | uniq > "$output_file_path"
        [ "$SKIP_HEADERS_USE" != "1" ] && prepend_headers "$output_file_path"
        ;;
    esac

    [ "$VERBOSITY" -ge "1" ] && {
      echo "[INFO] Output: $(realpath "${output_file_path}${extension}")"
    }
    [ "$DEBUG" = "1" ] || rm "$output_file_path"*.tmp
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
        || flat_obj_to_nest "$file_path" "${FORMAT:-json}"
    else
      echo "[ERROR] File not found: $file_path"
      exit 1
    fi
  }
done
