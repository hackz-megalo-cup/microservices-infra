#!/usr/bin/env bash
set -euo pipefail

AGE_KEY_DIR="${HOME}/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"

if [ -f "$AGE_KEY_FILE" ]; then
  echo "Age key already exists at ${AGE_KEY_FILE}"
  echo "Public key:"
  age-keygen -y "$AGE_KEY_FILE"
  exit 0
fi

mkdir -p "$AGE_KEY_DIR"
age-keygen -o "$AGE_KEY_FILE"
echo ""
echo "Key generated at ${AGE_KEY_FILE}"
echo "Add the public key above to .sops.yaml"
