#!/bin/sh
# delete secret_tool's symlink
SECRET_TOOL_DIR_INSTALL=${SECRET_TOOL_DIR_INSTALL:-/usr/local/bin}

actual_install_path=$(command -v secret_tool 2> /dev/null)
if [ -z "$actual_install_path" ]; then
  echo '[INFO] Secret tool is not installed'
  exit 0
fi

echo 'Removing secret_tool installation'
sudo rm "${SECRET_TOOL_DIR_INSTALL:-/usr/local/bin}/secret_tool" \
  && echo '[DONE] Secret tool has been uninstalled' \
  || echo '[ERROR] Failed to uninstall secret tool'
