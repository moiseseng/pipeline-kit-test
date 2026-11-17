#!/usr/bin/env bash
# Stands in for a real server: reports what would be published and touches nothing.
# The fingerprint changes whenever any published file changes, so two runs can be compared.
set -euo pipefail

manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT

files=0
while IFS= read -r -d '' file; do
  (cd "$SITE_PATH" && shasum -a 256 "$file") >> "$manifest"
  files=$((files + 1))
done < <(cd "$SITE_PATH" && find . -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z)

fingerprint="$(shasum -a 256 "$manifest" | cut -d' ' -f1)"

report() {
  echo "### $SITE_NAME to $DEPLOY_ENV (simulated)"
  echo
  echo "- Commit: \`$RELEASE_SHA\`"
  echo "- Files: $files"
  echo "- Fingerprint: \`$fingerprint\`"
  echo
  echo "<details><summary>First files</summary>"
  echo
  echo '```'
  head -n 50 "$manifest"
  echo '```'
  echo
  echo "</details>"
}

report
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  report >> "$GITHUB_STEP_SUMMARY"
fi
