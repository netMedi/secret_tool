#!/bin/sh
# create secret_tool's symlink
SECRET_TOOL_DIR_SRC=${SECRET_TOOL_DIR_SRC:-.}
SECRET_TOOL_DIR_INSTALL=${SECRET_TOOL_DIR_INSTALL:-/usr/local/bin}

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

token_name='GITHUB_TOKEN'
if op read "op://Employee/$token_name/credential" 2> /dev/null | wc -l | grep -q 0; then
  echo 'Create Github token: https://github.com/settings/tokens'
  printf 'Enter your GitHub [read:packages] token: '
  read -r token \
    && sh -c "op item create \
      --vault Private \
      --title '$token_name' \
      --tags guthub,secret_tool \
      --category 'API Credential' \
        'credential=$token' \
        'expires=2999-12-31' \
    " > /dev/null \
    || echo "[ERROR] Failed to create '$token_name' in 1password"
else
  echo "[INFO] '$token_name' already exists in 1password"
fi

### make sure the binary has been built
$SECRET_TOOL_DIR_SRC/utils/build.sh || exit 1

### create symlink if missing
if command -v secret_tool > /dev/null 2>&1 && [ "$(readlink $(command -v secret_tool))" = "$(realpath "$script_dir/dist/secret_tool")" ]; then
  secret_tool --version > /dev/null 2>&1 && {
    echo '[INFO] Secret tool is already symlinked'
    exit 0
  }
fi

echo 'Creating global secret_tool symlink'
sudo sh -c "mkdir -p '$SECRET_TOOL_DIR_INSTALL'; cp '$script_dir/$SECRET_TOOL_EXE' '$SECRET_TOOL_DIR_INSTALL/secret_tool' && chmod +x '$SECRET_TOOL_DIR_INSTALL/secret_tool'" \
  && echo '[DONE] Secret tool has been installed. You may need to restart terminal, if the "secret_tool" command is not immediately available' \
  || {
    echo '[ERROR] Failed to install secret tool with sudo.'
    echo '[INFO] You can set up the alias instead:'
    echo
    echo "  alias secret_tool=\"$script_dir/dist/secret_tool\""
    echo '  # ^ add this line to your shell profile (e.g. ~/.bashrc, ~/.zshrc, etc.)'
  }
