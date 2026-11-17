#!/usr/bin/env bash
# Publishes one site to one environment by handing over to the script for its target type.
# Reads: SITE_NAME, SITE_PATH, TARGET_TYPE, TARGET_JSON, DEPLOY_ENV, RELEASE_SHA.
set -euo pipefail

: "${SITE_NAME:?}" "${SITE_PATH:?}" "${TARGET_TYPE:?}" "${DEPLOY_ENV:?}" "${RELEASE_SHA:?}"
if [[ -z "${TARGET_JSON:-}" ]]; then
  TARGET_JSON='{}'
fi
export TARGET_JSON

if [[ ! "$TARGET_TYPE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Target type '$TARGET_TYPE' is not a valid name." >&2
  exit 1
fi

script="$(cd "$(dirname "$0")" && pwd)/targets/$TARGET_TYPE.sh"
if [[ ! -f "$script" ]]; then
  echo "There is no deploy script for target type '$TARGET_TYPE'." >&2
  exit 1
fi
if [[ ! -d "$SITE_PATH" ]]; then
  echo "The folder to publish, '$SITE_PATH', doesn't exist." >&2
  exit 1
fi

exec bash "$script"
