#!/bin/sh

for file in ./*.sh; do
  echo
  echo "[INFO] Checking script: $file ..."
  sed '/^'"# --- SHELLCHECK BELOW ---"'/,$!s/.*/ /' "$file" | shellcheck - \
    && echo "[PASS] Checking script: $file" \
    || echo "[FAIL] Checking script: $file"
done
