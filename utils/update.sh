#!/bin/sh
# perform secret_tool's update
STOOL_ROOT_DIR=${STOOL_ROOT_DIR:-.}
SYMLINK_DIR=${SYMLINK_DIR:-/usr/local/bin}

git -C "$script_dir" stash > /dev/null # this may produce stashes, maybe reset instead?

if [ -n "$VERSION" ]; then
  git -C "$script_dir" fetch --tags > /dev/null
  if [ "$VERSION" = "stable" ]; then
    VERSION=$(git ls-remote --tags origin | cut --delimiter='/' --fields=3 | sort -r | grep "^v" | head -n 1)
  fi
  git -C "$script_dir" checkout "$VERSION" > /dev/null
else
  git -C "$script_dir" checkout latest > /dev/null # switch to default ("latest") branch for update
fi
git -C "$script_dir" pull > /dev/null
echo

### make sure the binary is installed
export SYMLINK_DIR
$STOOL_ROOT_DIR/utils/install.sh || exit 1

secret_tool --version
