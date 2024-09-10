#!/bin/sh
# verify secret_tool's functionality
STOOL_ROOT_DIR=${STOOL_ROOT_DIR:-.}
STOOL_EXECUTABLE=${STOOL_EXECUTABLE:-$STOOL_ROOT_DIR/src/secret_tool.ts}
DEBUG=${DEBUG:-0}
errors=0

echo "Running secret_tool's self-tests [$STOOL_EXECUTABLE]..."
echo

export FILE_NAME_BASE="$STOOL_ROOT_DIR/tests/.env."
export SECRET_MAP="${SECRET_MAP:-$STOOL_ROOT_DIR/tests/secret_map.yml}"
export SKIP_OP_MARKER="$STOOL_ROOT_DIR/tests/.env.SKIP_OP_MARKER"
rm "$SKIP_OP_MARKER" 2> /dev/null

SKIP_OP_MARKER_WRITE=1 \
TEST_VAR_LOCAL_OVERRIDE1=overridden \
TEST_VAR_LOCAL_OVERRIDE2='!!' \
  "$STOOL_EXECUTABLE" \
    all_tests pat

if [ "$SKIP_OP_USE" = "1" ] || [ -f "$SKIP_OP_MARKER" ]; then
  echo '[DEBUG] Skipping 1password tests'
fi
export SKIP_OP_USE=1 # this is to skip OP use in following tests only

FORMAT=json \
TEST_VAR_LOCAL_OVERRIDE1=overridden \
TEST_VAR_LOCAL_OVERRIDE2='!!' \
  "$STOOL_EXECUTABLE" \
    all_tests

FORMAT=yml \
TEST_VAR_LOCAL_OVERRIDE1=overridden \
TEST_VAR_LOCAL_OVERRIDE2='!!' \
  "$STOOL_EXECUTABLE" \
    all_tests

export SKIP_HEADERS_USE=1
FORMAT=envfile "$STOOL_EXECUTABLE" configmap
FORMAT=json "$STOOL_EXECUTABLE" configmap
FORMAT=yml "$STOOL_EXECUTABLE" configmap

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

# local env override 1
if (grep -q "^TEST_VAR_LOCAL_OVERRIDE1='overridden'" "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] Locally overridden value 1 was used'
else
  echo '[ERROR] Locally overridden value 1 was ignored'
  errors=$((errors + 1))
fi

# local env override 2
if (grep -q "^TEST_VAR_LOCAL_OVERRIDE2='present'" "${FILE_NAME_BASE}all_tests"); then
  echo '[ERROR] Locally overridden value 2 was ignored (discard)'
  errors=$((errors + 1))
else
  echo '[OK] Locally overridden value 2 was used (discard)'
fi

# simple number
if (grep -q ^TEST_VAR_NUMBER "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] Numeric value is present'
else
  echo '[ERROR] Numeric value is missing'
  errors=$((errors + 1))
fi

# simple string
if (grep -q ^TEST_VAR_STRING "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] String value is present'
else
  echo '[ERROR] String value is missing'
  errors=$((errors + 1))
fi

# verify base profile values has been inherited
if (grep -q ^TEST_VAR_INHERITANCE_1=1 "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] YAML inheritance test passed'
else
  echo '[ERROR] YAML inheritance test failed'
  errors=$((errors + 1))
fi

# verify array (flat)
if (grep -q "^TEST_NEST__ARR__0__NESTED_OBJECT__KEY1='value1-1'" "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] Nested array (flat) generated correctly'
else
  echo '[ERROR] Nested array (flat) generated with errors'
  errors=$((errors + 1))
fi

# verify array (nested)
if (grep -q "^TEST_NEST_OBJ__VARIABLE__ARR_SIMPLE__0='value1'" "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] Nested array (nested) generated correctly'
else
  echo '[ERROR] Nested array (nested) generated with errors'
  errors=$((errors + 1))
fi

# verify array (complex nested)
if (grep -q "^TEST_NEST_COMPLEX__ARR_COMPLEX__0__NESTED_OBJECT__KEY1='value1-1'" "${FILE_NAME_BASE}all_tests"); then
  echo '[OK] Nested array (complex nested) generated correctly'
else
  echo '[ERROR] Nested array (complex nested) generated with errors'
  errors=$((errors + 1))
fi

# verify configmap generation from express command: JSON
if cmp -s "$STOOL_ROOT_DIR/tests/validator.env.configmap.json" "${FILE_NAME_BASE}configmap.json"; then
  echo '[OK] Configmap (JSON) generated correctly'
else
  echo '[ERROR] Configmap (JSON) generated with errors'
  errors=$((errors + 1))
fi

## --- New secret_tool always uses double quotes for YAML ---
## TODO: change to single quotes if value contains no single quotes or $
## verify configmap generation from express command: YAML
# if cmp -s "$STOOL_ROOT_DIR/tests/validator.env.configmap.yml" "${FILE_NAME_BASE}configmap.yml"; then
#   echo '[OK] Configmap (YAML) generated correctly'
# else
#   echo '[ERROR] Configmap (YAML) generated with errors'
#   errors=$((errors + 1))
# fi

# verify 1password integration is working
if [ -f "$SKIP_OP_MARKER" ]; then
  echo '[INFO] 1password reference value is missing (skipped)'
else
  if (grep -q ^TEST_VAR_1PASSWORD_REF "${FILE_NAME_BASE}pat"); then
    echo '[OK] 1password reference value is present'
  else
    echo '[ERROR] 1password reference value is missing'
    echo '  Refer to installation instructions:'
    echo '    https://github.com/netMedi/Holvikaari/blob/master/docs/holvikaari-dev-overview.md#installation'
    errors=$((errors + 1))
  fi
fi

# verify GITHUB_TOKEN is set
if [ -f "$SKIP_OP_MARKER" ]; then
  echo '[INFO] GITHUB_TOKEN (1password) is missing (skipped)'
else
  if (grep -q ^TEST_OP_GITHUB_TOKEN "${FILE_NAME_BASE}pat"); then
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
"$STOOL_EXECUTABLE" --version
echo

# clean up unless debugging is enabled
printf '[ Press Enter to clean up and exit... ]'
read -r REPLY
printf "\n"

[ "$DEBUG" = "0" ] && rm "$FILE_NAME_BASE"* 2> /dev/null
[ "$errors" -eq "0" ] && exit 0 || exit 1