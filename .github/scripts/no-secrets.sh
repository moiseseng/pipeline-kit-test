#!/usr/bin/env bash
# Fails when the repository holds a private key or a secrets file.
set -euo pipefail

found=0

if git grep -nIE -e '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' -- .; then
  echo "A private key is committed in the lines above." >&2
  found=1
fi

secret_files="$(git ls-files | grep -E '(^|/)(\.env(\.[^/]*)?|id_(rsa|dsa|ecdsa|ed25519))$' \
  | grep -vE '\.env\.(example|sample|template)$' || true)"
if [[ -n "$secret_files" ]]; then
  echo "$secret_files"
  echo "The files above look like secrets and shouldn't be committed." >&2
  found=1
fi

if [[ "$found" -eq 0 ]]; then
  echo "No private keys or secrets files found."
fi
exit "$found"
