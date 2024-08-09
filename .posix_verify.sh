#!/bin/sh

for file in ./*.sh; do
  echo
  echo "[INFO] Checking script: $file ..."
  sed '/^'"# --- SHELLCHECK BELOW ---"'/,$!s/.*/ /' "$file" | shellcheck - \
    && echo "[PASS] Checking script with 'shellcheck': $file" \
    || echo "[FAIL] Checking script with 'shellcheck': $file"

  checkbashisms --force "$file" \
    && echo "[PASS] Checking script with 'checkbashisms': $file" \
    || echo "[FAIL] Checking script with 'checkbashisms': $file"
  echo
done
