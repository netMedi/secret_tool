#!/bin/sh
# delete secret_tool's symlink
SYMLINK_DIR=${SYMLINK_DIR:-/usr/local/bin}

symlink_path=$(command -v secret_tool 2> /dev/null)
if [ -z "$symlink_path" ]; then
  echo '[INFO] Secret tool is not symlinked'
  exit 0
fi

echo 'Removing global secret_tool symlink'
sudo rm "${SYMLINK_DIR:-/usr/local/bin}/secret_tool" \
  && echo '[DONE] Secret tool has been uninstalled' \
  || echo '[ERROR] Failed to uninstall secret tool'
