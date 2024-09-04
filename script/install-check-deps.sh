#!/bin/sh
op --version > /dev/null 2>&1 || {
  echo "op is not installed. Please install it from https://1password.com/downloads/command-line/."
  exit 1
}
bun install
