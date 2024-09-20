#!/bin/sh
# create secret_tool's symlink
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-$(realpath .)}
SECRET_TOOL_DIR_INSTALL=${SECRET_TOOL_DIR_INSTALL:-/usr/local/bin}
CONTAINER_TOOL=${CONTAINER_TOOL:-docker}
SKIP_OP_USE=${SKIP_OP_USE:-0}

if [ "$SKIP_OP_USE" = "0" ]; then
  echo '[INFO] Trying to log in to 1password...'
  op whoami > /dev/null 2>&1 \
    || eval "$(op signin --account netmedi)"

  APPROVED_TOOL_VERSION=$(op read op://Employee/SECRET_TOOL/version 2> /dev/null)
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo '[ERROR] You must have access to 1password and your employee vault must contain the "SECRET_TOOL/version" item'
    echo '  Refer to installation instructions:'
    echo '    https://github.com/netMedi/secret_tool?tab=readme-ov-file#first-time-install'
    exit 1
  fi

  # TODO: move this token creation/check somewhere else, it is not directly related secret_tool's installer
  # token_name='GITHUB_TOKEN'
  # if op read "op://Employee/$token_name/credential" 2> /dev/null | wc -l | grep -q 0; then
  #   echo 'Create Github token: https://github.com/settings/tokens'
  #   printf 'Enter your GitHub [read:packages] token: '
  #   # vault Employee = Private
  #   read -r token \
  #     && sh -c "op item create \
  #       --vault Private \
  #       --title '$token_name' \
  #       --tags guthub,secret_tool \
  #       --category 'API Credential' \
  #         'credential=$token' \
  #         'expires=2999-12-31' \
  #     " > /dev/null \
  #     || echo "[ERROR] Failed to create '$token_name' in 1password employee vault"
  # else
  #   echo "[INFO] '$token_name' is present in 1password employee vault"
  # fi

  CURRENT_TOOL_VERSION=$(grep '"version": ' $SECRET_TOOL_DIR_SRC/package.json | cut -d '"' -f 4)
  PROMPT_OK='[INFO] Approved version check' \
    PROMPT_FAIL='[INFO] Approved version check failed' \
    $SECRET_TOOL_DIR_SRC/ver_gte.sh $CURRENT_TOOL_VERSION $APPROVED_TOOL_VERSION || {
    echo "[INFO] Approved secret_tool's version in 1password employee vault: \"$APPROVED_TOOL_VERSION\""
    echo

    xyz=''
    while [ "$xyz" = "" ]; do
      echo "Do you approve version \"$CURRENT_TOOL_VERSION\"?"
      echo "  X (or Enter) - no, just exit"
      echo "  y = yes, approve version \"$CURRENT_TOOL_VERSION\""
      echo "  z = yes, approve latest version"
      read -r xyz
      case "$xyz" in
        [Yy]* )
          xyz='y'
          echo
          echo "[INFO] setting approved version to \"$CURRENT_TOOL_VERSION\"..."
          op item edit --vault Private SECRET_TOOL version="$CURRENT_TOOL_VERSION" > /dev/null 2>&1
          exit_code=$?
          ;;
        [Zz]* )
          echo '[INFO] setting approved version to "latest"...'
          op item edit --vault Private SECRET_TOOL version=latest > /dev/null 2>&1
          exit_code=$?
          ;;
        * )
          # XxNn or anything else is considered as "no"
          [ -z "$xyz" ] && {
            kill 0
          } || {
            echo '[ Please answer "x", "y", or "z" (single letter, no quotes) ]'
            echo
            xyz=''
          }
          ;;
      esac
    done

    [ "$exit_code" -ne 0 ] && exit $exit_code
    # continue if the version has been approved
  }
fi

### make sure the binary has been built
$SECRET_TOOL_DIR_SRC/utils/build.sh || exit 1

### create symlink if missing
if command -v secret_tool > /dev/null 2>&1 && [ "$(shasum -a 256 $(command -v secret_tool))" = "$(shasum -a 256 "$SECRET_TOOL_DIR_SRC/dist/secret_tool")" ]; then
  secret_tool --version > /dev/null 2>&1 && {
    echo '[INFO] Secret tool is already installed'
    exit 0
  }
fi

echo "Installing secret_tool to $SECRET_TOOL_DIR_INSTALL..."
sudo sh -c "mkdir -p '$SECRET_TOOL_DIR_INSTALL'; rm '$SECRET_TOOL_DIR_INSTALL/secret_tool' > /dev/null 2>&1; cp -f '$SECRET_TOOL_DIR_SRC/dist/secret_tool' '$SECRET_TOOL_DIR_INSTALL/secret_tool' && chmod +x '$SECRET_TOOL_DIR_INSTALL/secret_tool'" \
  && echo "[DONE] Secret tool has been installed. You may need to restart terminal, if the \"secret_tool\" command is not immediately available. Install info: $($SECRET_TOOL_DIR_INSTALL/secret_tool --version)" \
  || {
    echo '[ERROR] Failed to install secret_tool with sudo.'
    echo '[INFO] You can set up the alias instead:'
    echo
    echo "  alias secret_tool=\"$(realpath $SECRET_TOOL_DIR_SRC)/dist/secret_tool\""
    echo '  # ^ add this line to your shell profile (e.g. ~/.bashrc, ~/.zshrc, etc.)'
    echo
  }
