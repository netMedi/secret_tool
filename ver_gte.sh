#!/bin/bash
# Script: ver_gte.sh
# Purpose: Validates present version to be newer or equal to required version

# Usage: ./ver_gte.sh [required_version] [present_version]
#
# Examples:
#   ./ver_gte.sh 1.0.0 1.0.0  # exit code 0 (second SEMVER is newer)
#   ./ver_gte.sh 1.0.0 1.0.1  # exit code 0 (second SEMVER is newer)
#   ./ver_gte.sh 9.9.9 1.2.3  # exit code 1 (second SEMVER is older)

[ -z "$1" ] && exit 1
[ -z "$2" ] && exit 1

if [ "$2" == "latest" ]; then
  NEWER_VERSION="$2"
else
  NEWER_VERSION=$(printf "$1\n$2\n" | sort -t '.' -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g | tail -n 1)
fi

if [[ "$NEWER_VERSION" == "$2" ]]; then
  echo "Your version is OK (present: $2, required: $1)"
  exit 0
else
  echo "Your version is too old (present: $2, required: $1)"
  exit 1
fi
